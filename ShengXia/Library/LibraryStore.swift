import AVFoundation
import Foundation
import ShengXiaCore
import UIKit
import WebKit

struct StorageUsage: Equatable {
    var musicBytes: Int64
    var cacheBytes: Int64
}

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var tracks: [Track] = []
    @Published private(set) var playlists: [Playlist] = []
    @Published var lastError: String?

    private let fm = FileManager.default
    private var didBoot = false
    private let audioExtensions: Set<String> = ["mp3", "m4a", "flac", "wav", "aac", "caf"]
    private let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]

    private var documentsURL: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var supportURL: URL {
        fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ShengXia", isDirectory: true)
    }

    private var indexURL: URL { supportURL.appendingPathComponent("library.json") }

    var musicURL: URL { documentsURL.appendingPathComponent("Music", isDirectory: true) }

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

    func track(id: UUID) -> Track? { tracks.first { $0.id == id } }

    func track(sourceKey: String) -> Track? { tracks.first { $0.sourceKey == sourceKey } }

    func tracks(in playlist: Playlist) -> [Track] {
        playlist.trackIDs.compactMap { id in tracks.first { $0.id == id } }
    }

    func fileURL(for track: Track) -> URL { documentsURL.appendingPathComponent(track.relativePath) }

    func coverURL(for track: Track) -> URL? {
        guard let relative = track.coverRelativePath else { return nil }
        let url = documentsURL.appendingPathComponent(relative)
        return fm.fileExists(atPath: url.path) ? url : nil
    }

    func reserveAudioFile(title: String, extension ext: String) throws -> URL {
        try fm.createDirectory(at: musicURL, withIntermediateDirectories: true)
        return uniqueFile(in: musicURL, filename: FileNameSanitizer.filename(title: title, extension: ext))
    }

    @discardableResult
    func commit(
        audioURL: URL,
        coverURL: URL?,
        title: String,
        artist: String,
        sourceName: String,
        sourceURL: String?,
        formatLabel: String,
        duration: TimeInterval,
        sourceKey: String? = nil,
        clippedFrom: UUID? = nil,
        processingNote: String? = nil
    ) async throws -> Track {
        let bytes = fileSize(audioURL)
        let probed = duration > 0 ? duration : await Self.probeDuration(audioURL)
        let relative = relativePath(for: audioURL)
        let coverRelative = installedCover(coverURL, beside: audioURL)
        let key = sourceKey ?? sourceURL.flatMap { MediaKey.key(forInput: $0) }
        if let index = tracks.firstIndex(where: { $0.relativePath == relative }) {
            tracks[index].title = title
            tracks[index].artist = artist
            tracks[index].sourceName = sourceName
            tracks[index].sourceURL = sourceURL
            tracks[index].coverRelativePath = coverRelative ?? tracks[index].coverRelativePath
            tracks[index].duration = probed
            tracks[index].formatLabel = formatLabel
            tracks[index].byteCount = bytes
            if let key { tracks[index].sourceKey = key }
            if let clippedFrom { tracks[index].clippedFrom = clippedFrom }
            tracks[index].processingNote = processingNote ?? tracks[index].processingNote
            saveIndex()
            return tracks[index]
        }
        let track = Track(
            title: title,
            artist: artist,
            sourceName: sourceName,
            sourceURL: sourceURL,
            relativePath: relative,
            coverRelativePath: coverRelative,
            duration: probed,
            formatLabel: formatLabel,
            byteCount: bytes,
            sourceKey: key,
            clippedFrom: clippedFrom,
            processingNote: processingNote
        )
        tracks.insert(track, at: 0)
        saveIndex()
        return track
    }

    func update(_ id: UUID, _ body: (inout Track) -> Void) {
        guard let index = tracks.firstIndex(where: { $0.id == id }) else { return }
        body(&tracks[index])
        saveIndex()
    }

    func toggleFavorite(_ id: UUID) {
        update(id) { $0.isFavorite.toggle() }
    }

    func markPlayed(_ id: UUID) {
        update(id) {
            $0.playCount += 1
            $0.lastPlayedAt = Date()
        }
    }

    func setCoverData(_ data: Data, trackID: UUID) {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        let dest = fileURL(for: tracks[index]).deletingPathExtension().appendingPathExtension("jpg")
        do {
            try data.write(to: dest, options: .atomic)
        } catch {
            lastError = "封面没有写成：\(error.localizedDescription)"
            return
        }
        let previous = tracks[index].coverRelativePath
        tracks[index].coverRelativePath = relativePath(for: dest)
        if let previous, previous != tracks[index].coverRelativePath {
            let stillUsed = tracks.contains { $0.id != trackID && $0.coverRelativePath == previous }
            if !stillUsed { try? fm.removeItem(at: documentsURL.appendingPathComponent(previous)) }
        }
        saveIndex()
    }

    func delete(_ track: Track) {
        try? fm.removeItem(at: fileURL(for: track))
        if let cover = coverURL(for: track) {
            let relative = relativePath(for: cover)
            let shared = tracks.contains { $0.id != track.id && $0.coverRelativePath == relative }
            if !shared { try? fm.removeItem(at: cover) }
        }
        tracks.removeAll { $0.id == track.id }
        for index in playlists.indices { playlists[index].remove(track.id) }
        saveIndex()
    }

    @discardableResult
    func createPlaylist(name: String) -> Playlist {
        let playlist = Playlist(name: Playlist.cleanName(name))
        playlists.insert(playlist, at: 0)
        saveIndex()
        return playlist
    }

    func renamePlaylist(_ id: UUID, to name: String) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[index].name = Playlist.cleanName(name, fallback: playlists[index].name)
        playlists[index].updatedAt = Date()
        saveIndex()
    }

    func deletePlaylist(_ id: UUID) {
        playlists.removeAll { $0.id == id }
        saveIndex()
    }

    func add(_ trackIDs: [UUID], to playlistID: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[index].add(trackIDs)
        saveIndex()
    }

    func removeTracks(at offsets: IndexSet, playlistID: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[index].remove(atOffsets: offsets)
        saveIndex()
    }

    func moveTracks(in playlistID: UUID, from offsets: IndexSet, to destination: Int) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[index].move(fromOffsets: offsets, toOffset: destination)
        saveIndex()
    }

    func movePlaylists(from offsets: IndexSet, to destination: Int) {
        playlists.moveElements(fromOffsets: offsets, toOffset: destination)
        saveIndex()
    }

    func importExternal(_ urls: [URL]) async {
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let ext = url.pathExtension.lowercased()
            let title = url.deletingPathExtension().lastPathComponent
            do {
                if videoExtensions.contains(ext) {
                    let dest = try reserveAudioFile(title: title, extension: "m4a")
                    do {
                        try await AudioExporter.extractM4A(from: url, to: dest) { _ in }
                    } catch {
                        try? fm.removeItem(at: dest)
                        throw error
                    }
                    _ = try await commit(
                        audioURL: dest, coverURL: nil, title: title, artist: "本地文件",
                        sourceName: "文件", sourceURL: nil, formatLabel: "M4A（AAC）", duration: 0
                    )
                } else if audioExtensions.contains(ext) {
                    let dest = try reserveAudioFile(title: title, extension: ext)
                    if fm.fileExists(atPath: dest.path) { try? fm.removeItem(at: dest) }
                    try fm.copyItem(at: url, to: dest)
                    _ = try await commit(
                        audioURL: dest, coverURL: sidecarCover(for: url), title: title, artist: "本地文件",
                        sourceName: "文件", sourceURL: nil, formatLabel: Self.label(for: ext), duration: 0
                    )
                } else {
                    lastError = "「\(url.lastPathComponent)」不是声匣能收的音频"
                }
            } catch {
                lastError = "导入失败：\(error.localizedDescription)"
            }
        }
    }

    func refreshFromDisk() async {
        let files = audioFiles()
        let live = Set(files.map { relativePath(for: $0) })
        let removed = tracks.filter { !live.contains($0.relativePath) }.map(\.id)
        tracks.removeAll { !live.contains($0.relativePath) }
        if !removed.isEmpty {
            let gone = Set(removed)
            for index in playlists.indices { playlists[index].trackIDs.removeAll { gone.contains($0) } }
        }
        for file in files {
            let relative = relativePath(for: file)
            let bytes = fileSize(file)
            if let index = tracks.firstIndex(where: { $0.relativePath == relative }) {
                tracks[index].byteCount = bytes
                if tracks[index].coverRelativePath == nil, let cover = sidecarCover(for: file) {
                    tracks[index].coverRelativePath = relativePath(for: cover)
                }
                if tracks[index].sourceKey == nil, let source = tracks[index].sourceURL {
                    tracks[index].sourceKey = MediaKey.key(forInput: source)
                }
                continue
            }
            let ext = file.pathExtension.lowercased()
            let title = file.deletingPathExtension().lastPathComponent
            let cover = sidecarCover(for: file)
            let duration = await Self.probeDuration(file)
            tracks.insert(Track(
                title: title.isEmpty ? "未命名音轨" : title,
                artist: "本地文件",
                sourceName: "文件",
                relativePath: relative,
                coverRelativePath: cover.map { relativePath(for: $0) },
                duration: duration,
                formatLabel: Self.label(for: ext),
                byteCount: bytes
            ), at: 0)
        }
        saveIndex()
    }

    func storageUsage() -> StorageUsage {
        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first
        return StorageUsage(
            musicBytes: directorySize(musicURL),
            cacheBytes: directorySize(fm.temporaryDirectory) + (caches.map { directorySize($0) } ?? 0)
        )
    }

    func clearCache() async {
        URLCache.shared.removeAllCachedResponses()
        if let items = try? fm.contentsOfDirectory(at: fm.temporaryDirectory, includingPropertiesForKeys: nil) {
            for url in items { try? fm.removeItem(at: url) }
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            WKWebsiteDataStore.default().removeData(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                modifiedSince: .distantPast
            ) {
                continuation.resume()
            }
        }
    }

    func makeBackup() throws -> URL {
        let folder = documentsURL.appendingPathComponent("备份", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = folder.appendingPathComponent("声匣资料库-\(stamp).json")
        try LibraryIndex(tracks: tracks, playlists: playlists).encoded().write(to: url, options: .atomic)
        return url
    }

    func backupData() throws -> Data {
        try LibraryIndex(tracks: tracks, playlists: playlists).encoded()
    }

    private func installedCover(_ coverURL: URL?, beside audioURL: URL) -> String? {
        guard let coverURL, fm.fileExists(atPath: coverURL.path) else { return nil }
        let sidecar = audioURL.deletingPathExtension().appendingPathExtension(coverURL.pathExtension.isEmpty ? "jpg" : coverURL.pathExtension)
        if coverURL.standardizedFileURL != sidecar.standardizedFileURL {
            try? fm.removeItem(at: sidecar)
            try? fm.copyItem(at: coverURL, to: sidecar)
            if fm.fileExists(atPath: sidecar.path) { return relativePath(for: sidecar) }
        }
        return relativePath(for: coverURL)
    }

    private func audioFiles() -> [URL] {
        guard let enumerator = fm.enumerator(
            at: documentsURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator {
            if url.path.contains("/备份/") { continue }
            if audioExtensions.contains(url.pathExtension.lowercased()) { files.append(url) }
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
        if full.hasPrefix(root + "/") { return String(full.dropFirst(root.count + 1)) }
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
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    private func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            total += fileSize(file)
        }
        return total
    }

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL),
              let index = try? LibraryIndex.decode(data) else { return }
        tracks = index.tracks
        playlists = index.playlists
    }

    private func saveIndex() {
        var index = LibraryIndex(tracks: tracks, playlists: playlists)
        index.pruneDanglingReferences()
        playlists = index.playlists
        guard let data = try? index.encoded() else { return }
        try? fm.createDirectory(at: supportURL, withIntermediateDirectories: true)
        try? data.write(to: indexURL, options: .atomic)
    }

    private static func label(for ext: String) -> String {
        switch ext {
        case "mp3": return "MP3"
        case "flac": return "FLAC"
        case "m4a": return "M4A"
        case "wav": return "WAV"
        case "aac": return "AAC"
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
