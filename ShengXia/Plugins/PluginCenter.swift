import Foundation
import Security
import ShengXiaCore
import UIKit

struct PluginSettingField: Codable, Equatable, Identifiable, Sendable {
    var key: String
    var label: String
    var help: String
    var id: String { key }
}

struct PluginRecord: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var pluginID: String
    var name: String
    var version: String
    var author: String
    var repository: String
    var source: String
    var summary: String
    var license: String
    var enabled: Bool
    var entry: String
    var network: [String]
    var settings: [PluginSettingField]
    var values: [String: String]
    var phrases: [String: String]
}

struct PluginSong: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var artist: String
    var duration: TimeInterval
    var pageURL: String?
}

struct PluginSearchPage: Equatable, Sendable {
    var tracks: [PluginSong] = []
    var playlists: [PluginSong] = []
    var message: String?
}

struct PluginCatalogItem: Identifiable {
    var repo: String
    var name: String
    var note: String
    var id: String { repo }
    var source: String { "https://github.com/\(repo)" }
}

enum PluginCatalog {
    static let verified: [PluginCatalogItem] = [
        .init(repo: "hubandad/mygo-music-netease", name: "网易云音乐", note: "匿名搜索可用。原唱有时会要登录，同一次结果里的公开版本能拿到 mp3。"),
        .init(repo: "AkinoKaede/mygo-music-netease-cloud-music", name: "网易云音乐（另一只）", note: "仓库本身是 TypeScript，声匣会下 GitHub Release 里编好的包。和上一只 id 相同，会分开安装。"),
        .init(repo: "dddaniel1/mygo-plugin-qqmusic", name: "QQ 音乐", note: "《晴天》在未登录时拿到了 mp3。超出账号权限时，插件自己会变成 60 秒试听。"),
        .init(repo: "Lorpaves/mygo-music-qqmusic", name: "QQ 音乐（另一只）", note: "有的歌要登录。匿名时《晴天（超盛大弦乐）》能播。"),
        .init(repo: "dddaniel1/mygo-plugin-kugou", name: "酷狗", note: "第一条常要求登录，后面的公开版本能拿到 mp3。"),
        .init(repo: "bitbyte404/mygo-music-kugou-lite", name: "酷狗概念版", note: "公开版本能播。设置里的每日 VIP 是插件自己去问酷狗，声匣不加额外权限。"),
        .init(repo: "amqsy/mygo-music-bodian", name: "波点", note: "前几条可能被拒绝，同一次搜索里靠后的公开版本能播。"),
        .init(repo: "GentleM4dman/mygo-music-bilibili", name: "哔哩哔哩", note: "标准音质是直接的 m4a。需要 ffmpeg 的音质不会播，声匣不启动外部程序。"),
        .init(repo: "popeyelau/mygo-queyue", name: "雀乐", note: "搜索要登录。没登录时，首页每日推荐可以播。"),
        .init(repo: "djyde/mygo-lizhi", name: "李志", note: "不用登录。曲目来自公开的歌曲仓库。"),
        .init(repo: "GYRYEZ/mygo-music-roamdial", name: "RoamDial", note: "电台，不是曲库。搜索电台名可以拿到直播流。")
    ]
}

@MainActor
final class PluginCenter: ObservableObject {
    @Published private(set) var records: [PluginRecord] = []
    @Published var pages: [String: PluginSearchPage] = [:]
    @Published var notice: String?
    @Published var busy: String?
    @Published var prompt: String?
    @Published var webJob: WebJob?

    let library: LibraryStore
    let player: PlayerModel
    private var engines: [String: PluginEngine] = [:]
    private var memories: [String: PluginMemory] = [:]
    private let vault = PluginVault()

    init(library: LibraryStore, player: PlayerModel) {
        self.library = library
        self.player = player
        records = (try? Self.loadIndex()) ?? []
    }

    func install(from raw: String) async {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        busy = "正在下载插件…"
        defer { busy = nil }
        do {
            let bundle = try await PluginFetcher.fetch(text)
            adopt(bundle, source: text)
            notice = "已安装「\(bundle.manifest.name)」。新安装的插件是关的，打开开关后再搜。更新会保留原来的开关。"
        } catch {
            notice = error.localizedDescription
        }
    }

    func setEnabled(_ id: String, _ enabled: Bool) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].enabled = enabled
        if !enabled {
            engines[id] = nil
            memories[id] = nil
        }
        saveIndex()
    }

    func uninstall(_ id: String) {
        engines[id] = nil
        memories[id] = nil
        vault.delete(id)
        try? FileManager.default.removeItem(at: Self.directory(id))
        records.removeAll { $0.id == id }
        pages[id] = nil
        saveIndex()
    }

    func update(_ record: PluginRecord) async {
        busy = "正在检查 \(record.name)…"
        defer { busy = nil }
        do {
            let bundle = try await PluginFetcher.fetch(record.source)
            let same = bundle.manifest.version == record.version
            adopt(bundle, source: record.source)
            notice = same ? "「\(record.name)」已经是 \(record.version)。" : "「\(record.name)」更新到 \(bundle.manifest.version)。"
        } catch {
            notice = error.localizedDescription
        }
    }

    func setValue(_ id: String, key: String, value: String) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].values[key] = value
        memories[id]?.setSetting(key, value)
        saveIndex()
    }

    func search(query: String) async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let enabled = records.filter(\.enabled)
        guard !enabled.isEmpty else {
            notice = "先打开至少一个插件。"
            return
        }
        busy = "正在搜…"
        pages = [:]
        defer { busy = nil }
        await withTaskGroup(of: (String, PluginSearchPage).self) { group in
            for record in enabled {
                group.addTask { @MainActor in
                    await self.page(for: record, query: text)
                }
            }
            for await (id, page) in group {
                pages[id] = page
            }
        }
    }

    func playHome(_ record: PluginRecord) async {
        busy = "正在打开 \(record.name)…"
        defer { busy = nil }
        do {
            let engine = try engine(for: record)
            guard engine.exports().contains("home") else {
                notice = "这个插件没有首页。"
                return
            }
            let json = try await engine.call("home", timeout: 25)
            let tracks = PluginJSON.songs(in: json, key: "tracks")
            guard let song = tracks.first else {
                pages[record.id] = PluginSearchPage(message: "首页没有可以直接播的曲目。")
                return
            }
            pages[record.id] = PluginSearchPage(tracks: tracks)
            try await play(song, on: record)
        } catch {
            notice = Self.describe(error)
        }
    }

    func play(_ song: PluginSong, on record: PluginRecord) async throws {
        if let existing = library.tracks.first(where: { $0.sourceKey == Self.sourceKey(record, song) }) {
            player.play(existing, in: library.tracks)
            return
        }
        busy = "正在连接 \(song.name)…"
        defer { busy = nil }
        let engine = try engine(for: record)
        let stream = try await Self.stream(engine: engine, id: song.id, preferred: record.values["quality"])
        guard let url = URL(string: stream.url) else { throw PluginInstallError.message("播放地址打不开") }
        let lyrics = await Self.lyrics(engine: engine, id: song.id)
        player.playStream(
            url: url,
            headers: stream.headers,
            title: song.name,
            artist: song.artist,
            sourceName: record.name,
            format: stream.format,
            lyrics: lyrics
        )
    }

    func save(_ song: PluginSong, on record: PluginRecord) async {
        let key = Self.sourceKey(record, song)
        if library.tracks.contains(where: { $0.sourceKey == key }) {
            notice = "「\(DisplayTitle.shortened(song.name))」已经在资料库里。"
            return
        }
        busy = "正在保存 \(song.name)…"
        defer { busy = nil }
        do {
            let engine = try engine(for: record)
            let stream = try await Self.stream(engine: engine, id: song.id, preferred: record.values["quality"])
            guard let url = URL(string: stream.url) else { throw PluginInstallError.message("播放地址打不开") }
            let file = try library.reserveAudioFile(title: song.name, extension: stream.fileExtension)
            var request = URLRequest(url: url)
            stream.headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<400).contains(status), !data.isEmpty else {
                throw PluginInstallError.message("下载没有成功（\(status)）")
            }
            try data.write(to: file, options: .atomic)
            if let lyrics = await Self.lyrics(engine: engine, id: song.id) {
                let sidecar = file.deletingPathExtension().appendingPathExtension("lrc")
                try? lyrics.write(to: sidecar, atomically: true, encoding: .utf8)
            }
            _ = try await library.commit(
                audioURL: file,
                coverURL: nil,
                title: DisplayTitle.shortened(song.name),
                artist: song.artist,
                sourceName: record.name,
                sourceURL: song.pageURL ?? stream.url,
                formatLabel: stream.format,
                duration: song.duration,
                sourceKey: key
            )
            notice = "已保存「\(DisplayTitle.shortened(song.name))」。"
        } catch {
            notice = Self.describe(error)
        }
    }

    func importPlaylist(id rawID: String, on record: PluginRecord) async {
        let playlistID = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !playlistID.isEmpty else { return }
        busy = "正在导入歌单…"
        defer { busy = nil }
        do {
            let engine = try engine(for: record)
            guard engine.exports().contains("playlist") else {
                notice = "这个插件不能按编号导入歌单。"
                return
            }
            let json = try await engine.call("playlist", json: PluginJSON.text(["id": playlistID]), timeout: 30)
            let songs = Array(PluginJSON.songs(in: json, key: "tracks").prefix(12))
            guard !songs.isEmpty else {
                notice = "这个歌单里没有曲目。"
                return
            }
            var saved: [UUID] = []
            for song in songs {
                await save(song, on: record)
                if let track = library.tracks.first(where: { $0.sourceKey == Self.sourceKey(record, song) }) {
                    saved.append(track.id)
                }
            }
            guard !saved.isEmpty else { return }
            let name = PluginJSON.title(in: json) ?? record.name
            let playlist = library.createPlaylist(name: name)
            library.add(saved, to: playlist.id)
            notice = "已把 \(saved.count) 首放进歌单「\(playlist.name)」。"
        } catch {
            notice = Self.describe(error)
        }
    }

    func finishWeb(_ result: Result<String, Error>) {
        webJob?.finish(result)
        webJob = nil
    }

    private func page(for record: PluginRecord, query: String) async -> (String, PluginSearchPage) {
        do {
            let engine = try engine(for: record)
            guard engine.exports().contains("search") else {
                return (record.id, PluginSearchPage(message: "这个插件没有搜索。可以试「首页」。"))
            }
            let json = try await engine.call("search", json: PluginJSON.text(["query": query, "kind": "tracks", "offset": 0]), timeout: 30)
            var tracks = PluginJSON.songs(in: json, key: "tracks")
            if tracks.isEmpty {
                tracks = PluginJSON.songs(in: json, key: "shows")
            }
            let playlists = PluginJSON.songs(in: json, key: "playlists")
            if tracks.isEmpty && playlists.isEmpty {
                return (record.id, PluginSearchPage(message: "没有结果。"))
            }
            return (record.id, PluginSearchPage(tracks: tracks, playlists: playlists))
        } catch {
            return (record.id, PluginSearchPage(message: Self.describe(error)))
        }
    }

    private func engine(for record: PluginRecord) throws -> PluginEngine {
        if let engine = engines[record.id] { return engine }
        let files = try Self.scripts(in: Self.directory(record.id))
        let memory = PluginMemory(storage: vault.load(record.id), settings: record.values, phrases: record.phrases)
        let installID = record.id
        let vault = self.vault
        memory.onStorage = { snapshot in
            vault.save(installID, snapshot)
        }
        let engine = try PluginEngine(
            files: files,
            entry: record.entry,
            network: record.network,
            directory: Self.directory(record.id).path,
            memory: memory
        )
        engine.webSignInHandler = { [weak self] request in
            guard let self else { throw PluginInstallError.message("插件页已经关了") }
            return try await self.waitForWeb(request)
        }
        engine.signInPromptHandler = { [weak self] json in
            Task { @MainActor in self?.prompt = json }
        }
        engine.openURLHandler = { url in
            guard let link = URL(string: url), link.scheme == "https" || link.scheme == "http" else { return }
            Task { @MainActor in
                UIApplication.shared.open(link)
            }
        }
        engines[record.id] = engine
        memories[record.id] = memory
        return engine
    }

    private func waitForWeb(_ request: PluginWebSignIn) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                self.webJob = WebJob(request: request) { result in
                    continuation.resume(with: result)
                }
            }
        }
    }

    private func adopt(_ bundle: FetchedPlugin, source: String) {
        let owner = bundle.repository.split(separator: "/").first.map(String.init) ?? "custom"
        let existing = records.first {
            $0.source == source || (bundle.repository.contains("/") && $0.repository == bundle.repository)
        }
        let collided = records.contains { $0.pluginID == bundle.manifest.id && $0.repository != bundle.repository && $0.id != existing?.id }
        let installID = existing?.id ?? (collided ? "\(bundle.manifest.id)@\(owner)" : bundle.manifest.id)
        let folder = Self.directory(installID)
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (path, data) in bundle.files {
            let url = folder.appendingPathComponent(path)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
        engines[installID] = nil
        memories[installID] = nil
        var values = existing?.values ?? [:]
        for field in bundle.manifest.settings where values[field.key] == nil {
            values[field.key] = ""
        }
        let record = PluginRecord(
            id: installID,
            pluginID: bundle.manifest.id,
            name: bundle.manifest.name,
            version: bundle.manifest.version,
            author: bundle.author,
            repository: bundle.repository,
            source: source,
            summary: bundle.manifest.summary,
            license: bundle.license,
            enabled: existing?.enabled ?? false,
            entry: bundle.manifest.entry,
            network: bundle.manifest.network,
            settings: bundle.manifest.settings,
            values: values,
            phrases: bundle.phrases
        )
        if let index = records.firstIndex(where: { $0.id == installID }) {
            records[index] = record
        } else {
            records.insert(record, at: 0)
        }
        saveIndex()
    }

    private static func stream(engine: PluginEngine, id: String, preferred: String?) async throws -> RemoteStream {
        var order = ["standard", "high", "128", "320", "flac", "higher", "exhigh", "lossless", "hires", "low"]
        if let preferred, !preferred.isEmpty {
            order.removeAll { $0 == preferred }
            order.insert(preferred, at: 0)
        }
        var last = "没有拿到播放地址"
        for quality in order {
            do {
                let json = try await engine.call("stream", json: PluginJSON.text(["id": id, "quality": quality]), timeout: 25)
                if let stream = RemoteStream(json: json) { return stream }
            } catch {
                last = describe(error)
            }
        }
        throw PluginInstallError.message(last)
    }

    private static func lyrics(engine: PluginEngine, id: String) async -> String? {
        guard engine.exports().contains("lyrics") else { return nil }
        guard let json = try? await engine.call("lyrics", json: PluginJSON.text(["id": id]), timeout: 15) else { return nil }
        return PluginJSON.lyrics(json)
    }

    private static func sourceKey(_ record: PluginRecord, _ song: PluginSong) -> String {
        "plugin:\(record.id):\(song.id)"
    }

    private static func describe(_ error: Error) -> String {
        if let error = error as? PluginCallError {
            switch error {
            case .timeout: return "插件超时了，稍后再试。"
            case .script(let message): return message
            case .failed(let message, _): return message
            }
        }
        return error.localizedDescription
    }

    private static func scripts(in folder: URL) throws -> [String: String] {
        var files: [String: String] = [:]
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey]) else {
            throw PluginInstallError.message("插件文件不在了")
        }
        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "js" else { continue }
            let root = folder.standardizedFileURL.path
            let full = url.standardizedFileURL.path
            guard full.hasPrefix(root + "/") else { continue }
            let relative = String(full.dropFirst(root.count + 1))
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            files[relative] = text
        }
        if files.isEmpty { throw PluginInstallError.message("插件里没有可以运行的脚本") }
        return files
    }

    private func saveIndex() {
        do {
            try FileManager.default.createDirectory(at: Self.supportURL, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(records)
            try data.write(to: Self.indexURL, options: .atomic)
        } catch {
            notice = "插件列表没有写下来：\(error.localizedDescription)"
        }
    }

    private static func loadIndex() throws -> [PluginRecord] {
        let data = try Data(contentsOf: indexURL)
        return try JSONDecoder().decode([PluginRecord].self, from: data)
    }

    private static var supportURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ShengXia", isDirectory: true)
    }

    private static var indexURL: URL { supportURL.appendingPathComponent("plugins.json") }
    private static func directory(_ id: String) -> URL { supportURL.appendingPathComponent("Plugins/\(id)", isDirectory: true) }
}

final class WebJob: Identifiable {
    let id = UUID()
    let request: PluginWebSignIn
    private let resume: (Result<String, Error>) -> Void
    private var finished = false

    init(request: PluginWebSignIn, resume: @escaping (Result<String, Error>) -> Void) {
        self.request = request
        self.resume = resume
    }

    func finish(_ result: Result<String, Error>) {
        guard !finished else { return }
        finished = true
        resume(result)
    }
}

private struct RemoteStream {
    var url: String
    var format: String
    var headers: [String: String]
    var fileExtension: String {
        switch format.lowercased() {
        case "mp3": return "mp3"
        case "flac": return "flac"
        case "wav": return "wav"
        case "aac": return "aac"
        case "ogg": return "ogg"
        default: return "m4a"
        }
    }

    init?(json: String) {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let url = object["url"] as? String, !url.isEmpty else { return nil }
        self.url = url
        let type = (object["type"] as? String)?.lowercased() ?? ""
        if type.isEmpty, let ext = URL(string: url)?.pathExtension.lowercased(), !ext.isEmpty {
            format = ext
        } else {
            format = type.isEmpty ? "m4a" : type
        }
        if let raw = object["headers"] as? [String: Any] {
            headers = raw.mapValues { String(describing: $0) }
        } else {
            headers = [:]
        }
    }
}

private enum PluginJSON {
    static func text(_ object: [String: String]) -> String {
        (try? String(data: JSONSerialization.data(withJSONObject: object), encoding: .utf8)) ?? "{}"
    }

    static func songs(in json: String, key: String) -> [PluginSong] {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        var rows = object[key] as? [[String: Any]] ?? []
        if rows.isEmpty, let sections = object["sections"] as? [[String: Any]] {
            rows = sections.flatMap { $0[key] as? [[String: Any]] ?? [] }
        }
        var seen = Set<String>()
        return rows.compactMap { row in
            guard let item = song(row), seen.insert(item.id).inserted else { return nil }
            return item
        }
    }

    static func lyrics(_ json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let lrc = object["lrc"] as? String, !lrc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return lrc
        }
        if let lines = object["lines"] as? [[String: Any]] {
            let text = lines.compactMap { $0["text"] as? String }.joined(separator: "\n")
            return text.isEmpty ? nil : text
        }
        return nil
    }

    static func title(in json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let playlist = object["playlist"] as? [String: Any], let name = playlist["name"] as? String { return name }
        return object["name"] as? String
    }

    private static func song(_ object: [String: Any]) -> PluginSong? {
        let name = (object["name"] as? String) ?? (object["title"] as? String) ?? ""
        guard !name.isEmpty else { return nil }
        let id = string(object["id"]) ?? name
        let artists = (object["artists"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
        let milliseconds = (object["duration"] as? NSNumber)?.doubleValue ?? 0
        return PluginSong(
            id: id,
            name: name,
            artist: artists.joined(separator: "、"),
            duration: milliseconds > 0 ? milliseconds / 1000 : 0,
            pageURL: object["url"] as? String
        )
    }

    private static func string(_ value: Any?) -> String? {
        if let text = value as? String, !text.isEmpty { return text }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }
}

private struct PluginManifest {
    var id: String
    var name: String
    var version: String
    var summary: String
    var entry: String
    var network: [String]
    var settings: [PluginSettingField]
}

private struct FetchedPlugin {
    var files: [String: Data]
    var manifest: PluginManifest
    var repository: String
    var author: String
    var license: String
    var phrases: [String: String]
}

private enum PluginInstallError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case .message(let text) = self { return text }
        return nil
    }
}

private enum PluginFetcher {
    static func fetch(_ raw: String) async throws -> FetchedPlugin {
        if raw.lowercased().hasSuffix(".js"), let url = URL(string: raw), url.scheme == "https" {
            return try await script(url)
        }
        if raw.lowercased().hasSuffix(".zip"), let url = URL(string: raw) {
            return try unpack(try await data(url), repository: url.host ?? "zip")
        }
        guard let repo = repository(raw) else { throw PluginInstallError.message("认不出这个地址。可以是 GitHub 仓库、zip 或 .js 链接。") }
        if let release = try? await releaseZip(repo) {
            return try unpack(release, repository: repo)
        }
        for branch in ["main", "master"] {
            let url = URL(string: "https://codeload.github.com/\(repo)/zip/refs/heads/\(branch)")!
            if let body = try? await data(url) {
                return try unpack(body, repository: repo)
            }
        }
        throw PluginInstallError.message("没有下到 \(repo)。")
    }

    private static func script(_ url: URL) async throws -> FetchedPlugin {
        let body = try await data(url)
        guard let source = String(data: body, encoding: .utf8), !source.isEmpty else {
            throw PluginInstallError.message("脚本是空的")
        }
        let name = url.deletingPathExtension().lastPathComponent
        let manifest = PluginManifest(
            id: name.isEmpty ? "custom" : name,
            name: name.isEmpty ? "自定义插件" : name,
            version: "0",
            summary: "从链接安装的单个脚本",
            entry: "index.js",
            network: ["*"],
            settings: []
        )
        return FetchedPlugin(
            files: ["index.js": body, "plugin.json": Data("{}".utf8)],
            manifest: manifest,
            repository: url.host ?? "script",
            author: url.host ?? "未知",
            license: "见原链接",
            phrases: [:]
        )
    }

    private static func releaseZip(_ repo: String) async throws -> Data {
        let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
        let body = try await data(url)
        guard let object = try JSONSerialization.jsonObject(with: body) as? [String: Any],
              let assets = object["assets"] as? [[String: Any]] else {
            throw PluginInstallError.message("没有 Release")
        }
        let zips = assets.compactMap { asset -> (String, String)? in
            guard let name = asset["name"] as? String, name.hasSuffix(".zip"), !name.hasSuffix(".sha256"),
                  let link = asset["browser_download_url"] as? String else { return nil }
            return (name.lowercased(), link)
        }
        let preferred = zips.first { name, _ in
            !name.contains("darwin") && !name.contains("windows") && !name.contains("linux") && !name.contains("macos")
        } ?? zips.first
        guard let link = preferred?.1, let fileURL = URL(string: link) else {
            throw PluginInstallError.message("Release 里没有通用 zip")
        }
        return try await data(fileURL)
    }

    private static func unpack(_ data: Data, repository: String) throws -> FetchedPlugin {
        let archive = try PluginZip.extract(data)
        let manifests = archive.keys.filter { $0.hasSuffix("plugin.json") }.sorted { $0.count < $1.count }
        guard let manifestPath = manifests.first(where: { path in
            guard let manifest = try? manifest(from: archive[path] ?? Data()) else { return false }
            let root = (path as NSString).deletingLastPathComponent
            let entry = root.isEmpty ? manifest.entry : root + "/" + manifest.entry
            return archive[entry] != nil
        }) ?? manifests.first else {
            throw PluginInstallError.message("压缩包里没有 plugin.json")
        }
        let parsed = try manifest(from: archive[manifestPath] ?? Data())
        let root = (manifestPath as NSString).deletingLastPathComponent
        var files: [String: Data] = [:]
        for (path, bytes) in archive {
            let relative: String
            if root.isEmpty { relative = path }
            else if path == root { continue }
            else if path.hasPrefix(root + "/") { relative = String(path.dropFirst(root.count + 1)) }
            else { continue }
            guard keep(relative) else { continue }
            files[relative] = bytes
        }
        let entryPath = parsed.entry
        guard files[entryPath] != nil else {
            throw PluginInstallError.message("找不到入口 \(entryPath)。如果仓库还是源码，等作者发 Release 再装。")
        }
        let license = licenseText(in: files)
        let phrases = phrases(in: files)
        let author = repository.split(separator: "/").first.map(String.init) ?? "未知"
        return FetchedPlugin(files: files, manifest: parsed, repository: repository, author: author, license: license, phrases: phrases)
    }

    private static func manifest(from data: Data) throws -> PluginManifest {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PluginInstallError.message("plugin.json 读不了")
        }
        let id = (object["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !id.isEmpty else { throw PluginInstallError.message("插件没有 id") }
        let permissions = object["permissions"] as? [String: Any]
        let settings = (object["settings"] as? [[String: Any]] ?? []).compactMap { item -> PluginSettingField? in
            guard let key = item["key"] as? String, !key.isEmpty else { return nil }
            return PluginSettingField(
                key: key,
                label: (item["label"] as? String) ?? key,
                help: (item["help"] as? String) ?? ""
            )
        }
        return PluginManifest(
            id: id,
            name: (object["name"] as? String) ?? id,
            version: (object["version"] as? String) ?? "0",
            summary: (object["description"] as? String) ?? "",
            entry: (object["main"] as? String)?.replacingOccurrences(of: "^\\./", with: "", options: .regularExpression) ?? "index.js",
            network: permissions?["network"] as? [String] ?? [],
            settings: settings
        )
    }

    private static func keep(_ path: String) -> Bool {
        let file = (path as NSString).lastPathComponent.lowercased()
        if file.contains("..") || path.contains("..") { return false }
        let ext = (file as NSString).pathExtension
        if ["js", "json", "md", "txt", "png", "jpg", "jpeg", "svg"].contains(ext) { return true }
        return file.contains("license") || file.contains("notice") || file == "copying"
    }

    private static func licenseText(in files: [String: Data]) -> String {
        let key = files.keys.first { ($0 as NSString).lastPathComponent.lowercased().contains("license") }
        guard let key, let text = String(data: files[key] ?? Data(), encoding: .utf8) else { return "见原仓库" }
        let line = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? "见原仓库"
        return String(line.prefix(80))
    }

    private static func phrases(in files: [String: Data]) -> [String: String] {
        let key = files.keys.first { $0.hasSuffix("locales/zh-CN.json") || $0 == "zh-CN.json" }
        guard let key, let object = try? JSONSerialization.jsonObject(with: files[key] ?? Data()) as? [String: Any] else { return [:] }
        return object.compactMapValues { $0 as? String }
    }

    private static func repository(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\.git$", with: "", options: .regularExpression)
        if trimmed.contains("github.com") {
            guard let url = URL(string: trimmed), let host = url.host, host.contains("github.com") else { return nil }
            let parts = url.path.split(separator: "/").map(String.init)
            guard parts.count >= 2 else { return nil }
            return "\(parts[0])/\(parts[1])"
        }
        let parts = trimmed.split(separator: "/").map(String.init)
        guard parts.count == 2, !parts[1].contains(".") else { return nil }
        return trimmed
    }

    private static func data(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("shengxia", forHTTPHeaderField: "User-Agent")
        let (body, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw PluginInstallError.message("下载失败（\(status)）") }
        return body
    }
}

private final class PluginVault: @unchecked Sendable {
    private let lock = NSLock()
    private let service = "com.giaotom.shengxia.plugins"

    func load(_ id: String) -> [String: String] {
        lock.lock()
        defer { lock.unlock() }
        if let values = keychain(id) { return values }
        return file(id) ?? [:]
    }

    func save(_ id: String, _ values: [String: String]) {
        lock.lock()
        defer { lock.unlock() }
        if !writeKeychain(id, values) { writeFile(id, values) }
    }

    func delete(_ id: String) {
        lock.lock()
        defer { lock.unlock() }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id
        ]
        SecItemDelete(query as CFDictionary)
        try? FileManager.default.removeItem(at: fileURL(id))
    }

    private func keychain(_ id: String) -> [String: String]? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id,
            kSecReturnData as String: true
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let values = try? JSONDecoder().decode([String: String].self, from: data) else { return nil }
        return values
    }

    private func writeKeychain(_ id: String, _ values: [String: String]) -> Bool {
        guard let data = try? JSONEncoder().encode(values) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess {
            return SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecSuccess
        }
        var add = query
        add[kSecValueData as String] = data
        let result = SecItemAdd(add as CFDictionary, nil)
        return result == errSecSuccess
    }

    private func file(_ id: String) -> [String: String]? {
        guard let data = try? Data(contentsOf: fileURL(id)) else { return nil }
        return try? JSONDecoder().decode([String: String].self, from: data)
    }

    private func writeFile(_ id: String, _ values: [String: String]) {
        guard let data = try? JSONEncoder().encode(values) else { return }
        try? FileManager.default.createDirectory(at: fileURL(id).deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL(id), options: .atomic)
    }

    private func fileURL(_ id: String) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ShengXia/Plugins/\(id)/storage.json")
    }
}
