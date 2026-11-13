import AVFoundation
import PhotosUI
import ShengXiaCore
import SwiftUI
import UIKit

struct MetadataEditor: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let trackID: UUID
    @State private var title: String
    @State private var artist: String
    @State private var cover: UIImage?
    @State private var photo: PhotosPickerItem?
    @State private var message: String?
    @State private var grabbing = false

    init(track: Track) {
        trackID = track.id
        _title = State(initialValue: track.title)
        _artist = State(initialValue: track.artist)
    }

    private var track: Track? { library.track(id: trackID) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        coverPreview
                        Spacer()
                    }
                    PhotosPicker(selection: $photo, matching: .images) {
                        Label("从相册选择封面", systemImage: "photo")
                    }
                    Button {
                        grabbing = true
                        Task { await grabFrame() }
                    } label: {
                        Label("从视频里抓一帧", systemImage: "film")
                    }
                    .disabled(grabbing)
                    if let message {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("信息") {
                    TextField("标题", text: $title)
                    TextField("作者", text: $artist)
                }
                if let track, track.sourceURL != nil {
                    Section {
                        Button("打开原视频") { LinkOpener.open(track) }
                    }
                }
            }
            .navigationTitle("编辑信息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save() } }
            }
            .onAppear {
                if cover == nil, let track, let url = library.coverURL(for: track) {
                    cover = UIImage(contentsOfFile: url.path)
                }
            }
            .onChange(of: photo) { item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        cover = image
                        message = nil
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var coverPreview: some View {
        if let cover {
            Image(uiImage: cover)
                .resizable()
                .scaledToFill()
                .frame(width: 160, height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(SX.cinnabar.opacity(0.15))
                .frame(width: 160, height: 160)
                .overlay(Image(systemName: "music.note").font(.largeTitle).foregroundStyle(SX.cinnabar))
        }
    }

    private func grabFrame() async {
        defer { grabbing = false }
        guard let track else { return }
        if let image = await AudioWorkbench.videoFrame(at: library.fileURL(for: track), seconds: min(1, max(track.duration / 2, 0))) {
            cover = image
            message = "已抓到一帧，保存后会换成封面。"
        } else {
            message = "这条音轨没有画面。封面请从相册里选。"
        }
    }

    private func save() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }
        library.update(trackID) { item in
            item.title = cleanTitle
            item.artist = cleanArtist.isEmpty ? item.artist : cleanArtist
        }
        if let cover, let data = cover.jpegData(compressionQuality: 0.86) {
            library.setCoverData(data, trackID: trackID)
        }
        dismiss()
    }
}

struct TrimEditor: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let track: Track
    @State private var bars: [Float] = []
    @State private var start: Double = 0
    @State private var end: Double = 1
    @State private var duration: Double = 1
    @State private var dragging = false
    @State private var exporting = false
    @State private var error: String?
    @StateObject private var preview = ClipPreview()

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(track.title).font(.headline).lineLimit(2)
                Text("拖动波形选择要留下的一段，再存成新音轨。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                waveform
                HStack {
                    Text(Clock.string(start))
                    Spacer()
                    Text("\(Clock.string(end - start))")
                        .foregroundStyle(SX.cinnabar)
                    Spacer()
                    Text(Clock.string(end))
                }
                .font(.caption.monospacedDigit())
                HStack {
                    Button { preview.play(url: library.fileURL(for: track), from: start, to: end) } label: {
                        Label("试听选区", systemImage: "play.fill")
                    }
                    .sxGlassButton()
                    Button("导出为新音轨") { Task { await export() } }
                        .sxGlassButton(prominent: true)
                        .disabled(exporting || end - start < 0.4)
                }
                if exporting { ProgressView("正在导出…") }
                if let error { Text(error).font(.footnote).foregroundStyle(SX.cinnabar) }
                Spacer()
            }
            .padding(20)
            .navigationTitle("剪一段")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
            .task {
                duration = track.duration > 0 ? track.duration : max(await AudioExporter.duration(of: library.fileURL(for: track)), 1)
                end = duration
                bars = await AudioWorkbench.waveform(for: library.fileURL(for: track), bars: 48)
            }
            .onDisappear { preview.stop() }
        }
    }

    private var waveform: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            ZStack(alignment: .leading) {
                HStack(alignment: .center, spacing: 2) {
                    ForEach(bars.indices, id: \.self) { index in
                        Capsule()
                            .fill(barColor(index: index, count: bars.count))
                            .frame(height: max(4, CGFloat(bars[index]) * geo.size.height))
                    }
                }
                handle(at: start, width: width)
                handle(at: end, width: width)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragging = true
                        let point = min(max(0, Double(value.location.x / width) * duration), duration)
                        let nearerStart = abs(point - start) <= abs(point - end)
                        let range = nearerStart
                            ? AudioMath.clampClip(start: point, end: end, duration: duration)
                            : AudioMath.clampClip(start: start, end: point, duration: duration)
                        start = range.lowerBound
                        end = range.upperBound
                    }
                    .onEnded { _ in dragging = false }
            )
        }
        .frame(height: 96)
        .padding(12)
        .sxGlass(cornerRadius: 18)
    }

    private func barColor(index: Int, count: Int) -> Color {
        guard count > 0, duration > 0 else { return .white.opacity(0.4) }
        let time = Double(index) / Double(count) * duration
        return (start...end).contains(time) ? SX.cinnabar : SX.ink.opacity(0.25)
    }

    private func handle(at time: Double, width: CGFloat) -> some View {
        Circle()
            .fill(Color.white)
            .overlay(Circle().strokeBorder(SX.cinnabar, lineWidth: 2))
            .frame(width: 22, height: 22)
            .offset(x: CGFloat(time / duration) * width - 11)
            .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
    }

    private func export() async {
        exporting = true
        error = nil
        defer { exporting = false }
        do {
            let dest = try library.reserveAudioFile(title: track.title + " 片段", extension: "m4a")
            try await AudioWorkbench.render(
                from: library.fileURL(for: track),
                to: dest,
                range: start...end,
                gainDB: 0
            ) { _ in }
            _ = try await library.commit(
                audioURL: dest,
                coverURL: library.coverURL(for: track),
                title: track.title + "（片段）",
                artist: track.artist,
                sourceName: track.sourceName,
                sourceURL: track.sourceURL,
                formatLabel: "M4A（AAC）",
                duration: end - start,
                sourceKey: "clip:\(UUID().uuidString)",
                clippedFrom: track.id,
                processingNote: "片段 \(Clock.string(start))–\(Clock.string(end))"
            )
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

@MainActor
final class ClipPreview: ObservableObject {
    private let player = AVPlayer()
    private var token: Any?

    func play(url: URL, from start: Double, to end: Double) {
        if player.currentItem == nil {
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
        }
        let stopAt = end
        player.seek(to: CMTime(seconds: start, preferredTimescale: 600))
        player.play()
        if let token { player.removeTimeObserver(token) }
        token = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.2, preferredTimescale: 600), queue: .main) { [weak player] time in
            if time.seconds >= stopAt { player?.pause() }
        }
    }

    func stop() {
        player.pause()
        if let token { player.removeTimeObserver(token) }
        token = nil
    }
}
