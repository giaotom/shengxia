import ShengXiaCore
import SwiftUI
import UIKit

struct MiniPlayerBar: View {
    var showsGlass: Bool
    @EnvironmentObject private var player: PlayerModel
    @EnvironmentObject private var shell: ShellState

    var body: some View {
        HStack(spacing: 10) {
            Button { shell.showPlayer = true } label: {
                HStack(spacing: 10) {
                    CoverThumb(track: player.current, side: 40, radius: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.current?.title ?? "未在播放")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(SX.ink)
                            .lineLimit(1)
                        Text(player.current.map { "\($0.formatLabel) · \($0.artist)" } ?? "")
                            .font(.caption)
                            .foregroundStyle(SX.brass)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("打开正在播放")
            Button { player.toggle() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.plain)
            .foregroundStyle(SX.cinnabar)
            .accessibilityLabel(player.isPlaying ? "暂停" : "播放")
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .padding(.vertical, 6)
        .background(alignment: .bottom) { progressLine }
        .modifier(MiniGlass(on: showsGlass))
    }

    private var progress: CGFloat {
        guard player.duration > 0 else { return 0 }
        return CGFloat(min(max(player.currentTime / player.duration, 0), 1))
    }

    private var progressLine: some View {
        GeometryReader { geo in
            Capsule()
                .fill(SX.cinnabar)
                .frame(width: max(4, geo.size.width * progress), height: 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .frame(height: 2)
    }
}

private struct MiniGlass: ViewModifier {
    var on: Bool
    @ViewBuilder
    func body(content: Content) -> some View {
        if on { content.sxGlass(cornerRadius: 18) } else { content }
    }
}

private enum PlayerPanel: String, Identifiable {
    case queue, sleep, speed, edit, trim, lyrics
    var id: String { rawValue }
}

struct PlayerScreen: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerModel
    @Environment(\.dismiss) private var dismiss
    @State private var panel: PlayerPanel?
    @State private var artwork: UIImage?
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let top = max(geo.safeAreaInsets.top, Self.windowSafeArea.top)
            let bottom = max(geo.safeAreaInsets.bottom, Self.windowSafeArea.bottom)
            let width = geo.size.width
            let height = max(0, geo.size.height - top - bottom)
            Group {
                    if let track = player.current {
                        controls(track, width: width, height: height)
                    } else {
                        VStack(spacing: 14) {
                            Button { dismiss() } label: {
                                Image(systemName: "chevron.down")
                                    .font(.body.weight(.bold))
                                    .frame(width: 40, height: 40)
                            }
                            .buttonStyle(.plain)
                            .modifier(CircleGlass())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel("关闭")
                            Spacer()
                            Text("还没有在播的音轨").font(.headline)
                            Button("关闭") { dismiss() }.sxGlassButton()
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .foregroundStyle(.white)
                    }
                }
                .frame(width: width, height: height)
                .position(x: width / 2, y: top + height / 2)
        }
        .background { backdrop }
        .offset(y: dragOffset)
        .ignoresSafeArea()
        .task(id: player.current?.coverRelativePath) { loadArtwork() }
        .sheet(item: $panel) { item in
            switch item {
            case .queue: QueueSheet()
            case .sleep: SleepSheet()
            case .speed: SpeedSheet()
            case .edit:
                if let track = player.current { MetadataEditor(track: track) }
            case .trim:
                if let track = player.current { TrimEditor(track: track) }
            case .lyrics:
                LyricsSheet(text: player.lyricText ?? "")
            }
        }
    }

    private static var windowSafeArea: UIEdgeInsets {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first
        return window?.safeAreaInsets ?? .zero
    }

    private var backdrop: some View {
        ZStack {
            if let artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 48)
                    .scaleEffect(1.15)
            } else {
                LinearGradient(colors: [SX.cinnabar, Color(red: 0.25, green: 0.08, blue: 0.06)], startPoint: .top, endPoint: .bottom)
            }
            LinearGradient(colors: [Color.black.opacity(0.25), Color.black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }

    private func controls(_ track: Track, width: CGFloat, height: CGFloat) -> some View {
        let coverSide = fittedCover(width: width, height: height)
        return VStack(spacing: 0) {
            VStack(spacing: 0) {
                topBar(track)
                Spacer(minLength: 6)
                cover(track, side: coverSide)
                Spacer(minLength: 8)
                titles(track)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .simultaneousGesture(swipeToDismiss(limitY: .greatestFiniteMagnitude))
            sourceBadge(track)
                .padding(.top, 8)
            scrubber
                .padding(.top, 10)
            modeRow
                .padding(.top, 2)
            transport
                .padding(.top, 8)
            actions(track)
                .padding(.top, 10)
            if let playbackError = player.playbackError {
                Text(playbackError)
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .frame(width: width, height: height, alignment: .top)
    }

    private func fittedCover(width: CGFloat, height: CGFloat) -> CGFloat {
        let reserved: CGFloat = 392
        let available = height - reserved
        return min(width - 88, 248, max(112, available))
    }

    private func swipeToDismiss(limitY: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 18, coordinateSpace: .local)
            .onChanged { value in
                guard value.startLocation.y < limitY else { return }
                let travel = value.translation.height
                guard travel > 0, travel > abs(value.translation.width) else { return }
                dragOffset = travel
            }
            .onEnded { value in
                let travel = value.translation.height
                let shouldClose = value.startLocation.y < limitY
                    && travel > 110
                    && travel > abs(value.translation.width) * 1.15
                if shouldClose {
                    dismiss()
                } else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        dragOffset = 0
                    }
                }
            }
    }

    private func topBar(_ track: Track) -> some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.body.weight(.bold))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .modifier(CircleGlass())
            .accessibilityLabel("关闭")
            Spacer(minLength: 8)
            Menu {
                if let lyrics = player.lyricText, !lyrics.isEmpty {
                    Button { panel = .lyrics } label: { Label("歌词", systemImage: "quote.bubble") }
                }
                Button { panel = .edit } label: { Label("编辑信息", systemImage: "pencil") }
                    .disabled(track.relativePath.isEmpty)
                Button { panel = .trim } label: { Label("剪一段", systemImage: "scissors") }
                    .disabled(track.relativePath.isEmpty)
                Button { LinkOpener.open(track) } label: { Label("打开原视频", systemImage: "arrow.up.right.square") }
                    .disabled(track.sourceURL == nil)
                Button(role: .destructive) { library.delete(track) } label: { Label("删除这首", systemImage: "trash") }
                    .disabled(track.relativePath.isEmpty)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.bold))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .modifier(CircleGlass())
            .accessibilityLabel("更多")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private func cover(_ track: Track, side: CGFloat) -> some View {
        let radius = max(22, side * 0.13)
        return CoverThumb(track: track, side: side, radius: radius)
            .shadow(color: .black.opacity(0.35), radius: 18, y: 12)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
            )
    }

    private func titles(_ track: Track) -> some View {
        VStack(spacing: 4) {
            Text(track.title)
                .font(.title3.weight(.bold))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity)
                .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
            Text(track.artist)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.84))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity)
            if track.byteCount > 0 || track.processingNote != nil {
                Text(detailLine(track))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private func sourceBadge(_ track: Track) -> some View {
        Text("来自 \(sourceLabel(track))")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(badgeColor(track.sourceKind), in: Capsule())
            .foregroundStyle(.white)
    }

    private func sourceLabel(_ track: Track) -> String {
        if track.sourceKind == .local, !track.sourceName.isEmpty, track.sourceName != "文件", track.sourceName != "本地" {
            return track.sourceName
        }
        return track.sourceKind.shortName
    }

    private func badgeColor(_ kind: SourceKind) -> Color {
        switch kind {
        case .bilibili: return Color(red: 0.09, green: 0.47, blue: 0.85)
        case .douyin: return Color(red: 0.12, green: 0.12, blue: 0.14)
        case .youtube: return Color(red: 0.78, green: 0.12, blue: 0.12)
        case .local: return SX.brass
        }
    }

    private var scrubber: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(get: { player.currentTime }, set: { player.currentTime = $0 }),
                in: 0...max(player.duration, 0.1),
                onEditingChanged: { editing in
                    player.isScrubbing = editing
                    if !editing { player.seek(to: player.currentTime) }
                }
            )
            .tint(.white)
            .accessibilityLabel("播放进度")
            HStack {
                Text(Clock.string(player.currentTime))
                Spacer()
                Text(Clock.string(player.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity)
    }

    private var modeRow: some View {
        HStack {
            modeButton("shuffle", "随机播放", player.shuffle) { player.toggleShuffle() }
            Spacer(minLength: 8)
            modeButton(player.repeatMode.symbol, player.repeatMode.title, player.repeatMode != .off) { player.cycleRepeat() }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
    }

    private var transport: some View {
        HStack(spacing: 26) {
            plainTransport("backward.fill", "上一首") { player.playPrevious() }
            Button { player.toggle() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 26, weight: .bold))
                    .frame(width: 64, height: 64)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .modifier(CircleGlass(emphasis: true))
            .accessibilityLabel(player.isPlaying ? "暂停" : "播放")
            plainTransport("forward.fill", "下一首") { player.playNext(automatic: false) }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 8)
        .sxCapsuleGlass()
        .frame(maxWidth: .infinity)
    }

    private func actions(_ track: Track) -> some View {
        let row = HStack(spacing: 8) {
            round("list.bullet", "队列", false) { panel = .queue }
            round(player.abActive ? "b.circle.fill" : "a.circle", player.abTitle, player.abActive) { player.toggleAB() }
            round("speedometer", player.rate == 1 ? "倍速" : "\(formatRate(player.rate))×", player.rate != 1) { panel = .speed }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                round("moon.zzz", player.sleepCaption(at: context.date) ?? "定时", player.sleepCaption(at: context.date) != nil) { panel = .sleep }
            }
            round(track.isFavorite ? "heart.fill" : "heart", "喜欢", track.isFavorite) { library.toggleFavorite(track.id) }
        }
        .frame(maxWidth: .infinity)
        return Group {
            if #available(iOS 26, *) {
                GlassEffectContainer(spacing: 8) { row }
            } else {
                row
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func round(_ symbol: String, _ title: String, _ active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 46, height: 46)
                    .modifier(CircleGlass(active: active))
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.92))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func plainTransport(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.title2).frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func modeButton(_ symbol: String, _ label: String, _ active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.body.weight(.semibold)).frame(width: 44, height: 36)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.white.opacity(active ? 1 : 0.62))
        .accessibilityLabel(label)
    }

    private func detailLine(_ track: Track) -> String {
        var pieces = [track.formatLabel]
        if track.byteCount > 0 { pieces.append(ByteText.string(track.byteCount)) }
        if let note = track.processingNote, !note.isEmpty { pieces.append(note) }
        return pieces.joined(separator: " · ")
    }

    private func formatRate(_ rate: Float) -> String {
        let hundred = (rate * 100).rounded() / 100
        if abs(hundred - hundred.rounded()) < 0.001 { return String(format: "%.0f", hundred) }
        return String(format: "%.2f", hundred)
    }

    private func loadArtwork() {
        guard let track = player.current, let url = library.coverURL(for: track) else {
            artwork = nil
            return
        }
        artwork = UIImage(contentsOfFile: url.path)
    }
}

private struct QueueSheet: View {
    @EnvironmentObject private var player: PlayerModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let current = player.current {
                    Section("正在播放") {
                        Text(current.title).font(.body.weight(.semibold)).lineLimit(1).truncationMode(.tail)
                        Text(current.artist).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Section("接下来") {
                    if player.upcomingTracks.isEmpty {
                        Text("队列后面是空的").foregroundStyle(.secondary)
                    } else {
                        ForEach(player.upcomingTracks) { track in
                            Button { player.jumpUpcoming(track) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(track.title).foregroundStyle(SX.ink).lineLimit(1)
                                    Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                        }
                        .onMove { player.moveUpcoming(from: $0, to: $1) }
                        .onDelete { player.removeUpcoming(at: $0) }
                    }
                }
            }
            .navigationTitle("队列")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(player.shuffle ? "关闭随机" : "随机播放") { player.toggleShuffle() }
                        Button(player.repeatMode.title) { player.cycleRepeat() }
                        Button("清空后面") { player.clearUpcoming() }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct SleepSheet: View {
    @EnvironmentObject private var player: PlayerModel
    @Environment(\.dismiss) private var dismiss
    private let choices = [15, 30, 45, 60, 90]

    var body: some View {
        NavigationStack {
            List {
                if let caption = player.sleepCaption() {
                    Section {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text("定时还剩 \(player.sleepCaption(at: context.date) ?? caption)")
                        }
                    }
                }
                Section {
                    ForEach(choices, id: \.self) { minutes in
                        Button("\(minutes) 分钟") {
                            player.startSleep(minutes: minutes)
                            dismiss()
                        }
                    }
                    Button("播完这首") {
                        player.sleepAtEndOfTrack()
                        dismiss()
                    }
                }
                if player.sleepCaption() != nil {
                    Section {
                        Button("关闭定时", role: .destructive) {
                            player.cancelSleep()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("定时关闭")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}

private struct SpeedSheet: View {
    @EnvironmentObject private var player: PlayerModel
    @Environment(\.dismiss) private var dismiss
    private let presets: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text(String(format: "%.2f×", player.rate))
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                Slider(value: Binding(get: { Double(player.rate) }, set: { player.setRate(Float($0)) }), in: 0.5...2)
                    .tint(SX.cinnabar)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 10) {
                    ForEach(presets, id: \.self) { preset in
                        Button(preset == floor(preset) ? String(format: "%.0f×", preset) : String(format: "%.2f×", preset)) {
                            player.setRate(preset)
                        }
                        .sxGlassButton(prominent: abs(player.rate - preset) < 0.01)
                    }
                }
                Spacer()
            }
            .padding(20)
            .navigationTitle("倍速")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}

private struct LyricsSheet: View {
    var text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .font(.body)
                    .foregroundStyle(SX.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            .background(SXBackground())
            .navigationTitle("歌词")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }
    }
}
