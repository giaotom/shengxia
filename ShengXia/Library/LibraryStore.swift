import AVFoundation
import Foundation
import ShengXiaCore

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var tracks: [Track] = []
    @Published var lastError: String?

    private let fm = FileManager.default
    private var didBoot = false
    private let audioExtensions: Set<String> = ["mp3", "m4a", "flac"]

    private var documentsURL: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var supportURL: URL {
        fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ShengXia", isDirectory: true)
    }

    private var indexURL: URL {
        supportURL.appendingPathComponent("library.json")
    }

    var musicURL: URL {
        documentsURL.appendingPathComponent("Music", isDirectory: true)
    }

    func bootstrap() async {
        if didBoot {
            await refreshFromDisk()
            return
        }
        didBoot = true
        try? fm.createDirectory(at: musicURL, withIntermediateDirectories: true)
        try? fm.createDirectory(at: supportURL, withIntermediateDirectories: true)
        loadIndex()
        await refreshFromDisk()
    }

    func fileURL(for track: Track) -> URL {
        documentsURL.appendingPathComponent(track.relativePath)
    }

    func coverURL(for track: Track) -> URL? {
        guard let relative = track.coverRelativePath else { return nil }
        let url = documentsURL.appendingPathComponent(relative)
        return fm.fileExists(atPath: url.path) ? url : nil
    }

    func reserveAudioFile(title: String, extension ext: String) throws -> URL {
        try fm.createDirectory(at: musicURL, withIntermediateDirectories: true)
        let filename = FileNameSanitizer.filename(title: title, extension: ext)
        return uniqueFile(in: musicURL, filename: filename)
    }

    func commit(
        audioURL: URL,
        coverURL: URL?,
        title: String,
        artist: String,
        sourceName: String,
        sourceURL: String?,
        formatLabel: String,
        duration: TimeInterval
    ) async throws -> Track {
        let bytes = fileSize(audioURL)
        let probed = duration > 0 ? duration : await Self.probeDuration(audioURL)
        let relative = relativePath(for: audioURL)
        let coverRelative = coverURL.map { relativePath(for: $0) }
        if let index = tracks.firstIndex(where: { $0.relativePath == relative }) {
            tracks[index].title = title
            tracks[index].artist = artist
            tracks[index].sourceName = sourceName
            tracks[index].sourceURL = sourceURL
            tracks[index].coverRelativePath = coverRelative
            tracks[index].duration = probed
            tracks[index].formatLabel = formatLabel
            tracks[index].byteCount = bytes
            saveIndex()
            return tracks[index]
        }
        let track = Track(
            id: UUID(),
            title: title,
            artist: artist,
            sourceName: sourceName,
            sourceURL: sourceURL,
            relativePath: relative,
            coverRelativePath: coverRelative,
            duration: probed,
            formatLabel: formatLabel,
            addedAt: Date(),
            byteCount: bytes
        )
        tracks.insert(track, at: 0)
        saveIndex()
        return track
    }

    func delete(_ track: Track) {
        let audio = fileURL(for: track)
        try? fm.removeItem(at: audio)
        if let cover = coverURL(for: track) {
            try? fm.removeItem(at: cover)
        }
        tracks.removeAll { $0.id == track.id }
        saveIndex()
    }

    func refreshFromDisk() async {
        let files = audioFiles()
        let live = Set(files.map { relativePath(for: $0) })
        tracks.removeAll { !live.contains($0.relativePath) }
        for file in files {
            let relative = relativePath(for: file)
            let bytes = fileSize(file)
            if let index = tracks.firstIndex(where: { $0.relativePath == relative }) {
                tracks[index].byteCount = bytes
                if tracks[index].coverRelativePath == nil, let cover = sidecarCover(for: file) {
                    tracks[index].coverRelativePath = relativePath(for: cover)
                }
                continue
            }
            let ext = file.pathExtension.lowercased()
            let title = file.deletingPathExtension().lastPathComponent
            let cover = sidecarCover(for: file)
            let duration = await Self.probeDuration(file)
            let track = Track(
                id: UUID(),
                title: title.isEmpty ? "未命名音轨" : title,
                artist: "本地文件",
                sourceName: "文件",
                sourceURL: nil,
                relativePath: relative,
                coverRelativePath: cover.map { relativePath(for: $0) },
                duration: duration,
                formatLabel: Self.label(for: ext),
                addedAt: Date(),
                byteCount: bytes
            )
            tracks.insert(track, at: 0)
        }
        saveIndex()
    }

    private func audioFiles() -> [URL] {
        guard let enumerator = fm.enumerator(
            at: documentsURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator {
            if audioExtensions.contains(url.pathExtension.lowercased()) {
                files.append(url)
            }
        }
        return files.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func sidecarCover(for audio: URL) -> URL? {
        let base = audio.deletingPathExtension()
        for ext in ["jpg", "jpeg", "png"] {
            let url = base.appendingPathExtension(ext)
            if fm.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    private func relativePath(for url: URL) -> String {
        let root = documentsURL.standardizedFileURL.path
        let full = url.standardizedFileURL.path
        if full.hasPrefix(root + "/") {
            return String(full.dropFirst(root.count + 1))
        }
        return url.lastPathComponent
    }

    private func uniqueFile(in directory: URL, filename: String) -> URL {
        let ext = (filename as NSString).pathExtension
        let base = (filename as NSString).deletingPathExtension
        var candidate = directory.appendingPathComponent(filename)
        var index = 2
        while fm.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            candidate = directory.appendingPathComponent(name)
            index += 1
        }
        return candidate
    }

    private func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL),
              let index = try? JSONDecoder.library.decode(LibraryIndex.self, from: data) else { return }
        tracks = index.tracks
    }

    private func saveIndex() {
        let index = LibraryIndex(version: 1, tracks: tracks)
        guard let data = try? JSONEncoder.library.encode(index) else { return }
        try? fm.createDirectory(at: supportURL, withIntermediateDirectories: true)
        try? data.write(to: indexURL, options: .atomic)
    }

    private static func label(for ext: String) -> String {
        switch ext {
        case "mp3": return "MP3"
        case "flac": return "FLAC"
        case "m4a": return "M4A"
        default: return ext.uppercased()
        }
    }

    private static func probeDuration(_ url: URL) async -> TimeInterval {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return 0 }
        let seconds = duration.seconds
        return seconds.isFinite && seconds > 0 ? seconds : 0
    }
}

private extension JSONEncoder {
    static var library: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var library: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
