import Foundation

public enum SourceKind: String, Codable, CaseIterable, Sendable {
    case bilibili
    case douyin
    case youtube
    case local

    public init(sourceName: String) {
        switch sourceName.lowercased() {
        case "哔哩哔哩", "b站", "bilibili": self = .bilibili
        case "抖音", "douyin": self = .douyin
        case "youtube": self = .youtube
        default: self = .local
        }
    }

    public var shortName: String {
        switch self {
        case .bilibili: return "B站"
        case .douyin: return "抖音"
        case .youtube: return "YouTube"
        case .local: return "本地"
        }
    }
}

public struct Track: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var artist: String
    public var sourceName: String
    public var sourceURL: String?
    public var relativePath: String
    public var coverRelativePath: String?
    public var duration: TimeInterval
    public var formatLabel: String
    public var addedAt: Date
    public var byteCount: Int64
    public var isFavorite: Bool
    public var sourceKey: String?
    public var playCount: Int
    public var lastPlayedAt: Date?
    public var clippedFrom: UUID?
    public var processingNote: String?

    public init(
        id: UUID = UUID(),
        title: String,
        artist: String,
        sourceName: String,
        sourceURL: String? = nil,
        relativePath: String,
        coverRelativePath: String? = nil,
        duration: TimeInterval,
        formatLabel: String,
        addedAt: Date = Date(),
        byteCount: Int64,
        isFavorite: Bool = false,
        sourceKey: String? = nil,
        playCount: Int = 0,
        lastPlayedAt: Date? = nil,
        clippedFrom: UUID? = nil,
        processingNote: String? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.sourceName = sourceName
        self.sourceURL = sourceURL
        self.relativePath = relativePath
        self.coverRelativePath = coverRelativePath
        self.duration = duration
        self.formatLabel = formatLabel
        self.addedAt = addedAt
        self.byteCount = byteCount
        self.isFavorite = isFavorite
        self.sourceKey = sourceKey
        self.playCount = playCount
        self.lastPlayedAt = lastPlayedAt
        self.clippedFrom = clippedFrom
        self.processingNote = processingNote
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, artist, sourceName, sourceURL, relativePath, coverRelativePath, duration
        case formatLabel, addedAt, byteCount, isFavorite, sourceKey, playCount, lastPlayedAt
        case clippedFrom, processingNote
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "未命名音轨"
        artist = try c.decodeIfPresent(String.self, forKey: .artist) ?? ""
        sourceName = try c.decodeIfPresent(String.self, forKey: .sourceName) ?? "文件"
        let rawURL = try c.decodeIfPresent(String.self, forKey: .sourceURL)
        sourceURL = (rawURL?.isEmpty == false) ? rawURL : nil
        relativePath = try c.decode(String.self, forKey: .relativePath)
        coverRelativePath = try c.decodeIfPresent(String.self, forKey: .coverRelativePath)
        duration = try c.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 0
        formatLabel = try c.decodeIfPresent(String.self, forKey: .formatLabel) ?? ""
        addedAt = try c.decodeIfPresent(Date.self, forKey: .addedAt) ?? Date()
        byteCount = try c.decodeIfPresent(Int64.self, forKey: .byteCount) ?? 0
        isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        sourceKey = try c.decodeIfPresent(String.self, forKey: .sourceKey)
            ?? sourceURL.flatMap { MediaKey.key(forInput: $0) }
        playCount = try c.decodeIfPresent(Int.self, forKey: .playCount) ?? 0
        lastPlayedAt = try c.decodeIfPresent(Date.self, forKey: .lastPlayedAt)
        clippedFrom = try c.decodeIfPresent(UUID.self, forKey: .clippedFrom)
        processingNote = try c.decodeIfPresent(String.self, forKey: .processingNote)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(artist, forKey: .artist)
        try c.encode(sourceName, forKey: .sourceName)
        try c.encodeIfPresent(sourceURL, forKey: .sourceURL)
        try c.encode(relativePath, forKey: .relativePath)
        try c.encodeIfPresent(coverRelativePath, forKey: .coverRelativePath)
        try c.encode(duration, forKey: .duration)
        try c.encode(formatLabel, forKey: .formatLabel)
        try c.encode(addedAt, forKey: .addedAt)
        try c.encode(byteCount, forKey: .byteCount)
        try c.encode(isFavorite, forKey: .isFavorite)
        try c.encodeIfPresent(sourceKey, forKey: .sourceKey)
        try c.encode(playCount, forKey: .playCount)
        try c.encodeIfPresent(lastPlayedAt, forKey: .lastPlayedAt)
        try c.encodeIfPresent(clippedFrom, forKey: .clippedFrom)
        try c.encodeIfPresent(processingNote, forKey: .processingNote)
    }

    public var sourceKind: SourceKind { SourceKind(sourceName: sourceName) }
}

public struct Playlist: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var trackIDs: [UUID]
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), name: String, trackIDs: [UUID] = [], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.trackIDs = trackIDs
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    @discardableResult
    public mutating func add(_ ids: [UUID]) -> Int {
        var added = 0
        for id in ids where !trackIDs.contains(id) {
            trackIDs.append(id)
            added += 1
        }
        if added > 0 { updatedAt = Date() }
        return added
    }

    public mutating func remove(atOffsets offsets: IndexSet) {
        for index in offsets.sorted(by: >) where trackIDs.indices.contains(index) {
            trackIDs.remove(at: index)
        }
        updatedAt = Date()
    }

    public mutating func remove(_ id: UUID) {
        trackIDs.removeAll { $0 == id }
        updatedAt = Date()
    }

    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        trackIDs.moveElements(fromOffsets: source, toOffset: destination)
        updatedAt = Date()
    }

    public static func cleanName(_ raw: String, fallback: String = "新歌单") -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return fallback }
        return String(trimmed.prefix(40))
    }
}

public struct LibraryIndex: Codable, Equatable, Sendable {
    public static let currentVersion = 2

    public var version: Int
    public var tracks: [Track]
    public var playlists: [Playlist]

    public init(version: Int = LibraryIndex.currentVersion, tracks: [Track], playlists: [Playlist] = []) {
        self.version = version
        self.tracks = tracks
        self.playlists = playlists
    }

    private enum CodingKeys: String, CodingKey { case version, tracks, playlists }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        tracks = try c.decodeIfPresent([Track].self, forKey: .tracks) ?? []
        playlists = try c.decodeIfPresent([Playlist].self, forKey: .playlists) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(tracks, forKey: .tracks)
        try c.encode(playlists, forKey: .playlists)
    }

    public mutating func pruneDanglingReferences() {
        let live = Set(tracks.map(\.id))
        for index in playlists.indices {
            playlists[index].trackIDs.removeAll { !live.contains($0) }
        }
    }

    public static func decode(_ data: Data) throws -> LibraryIndex {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var index = try decoder.decode(LibraryIndex.self, from: data)
        index.version = currentVersion
        index.pruneDanglingReferences()
        return index
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

public enum LibraryFilter: Hashable, Sendable {
    case all
    case favorites
    case source(SourceKind)

    public var title: String {
        switch self {
        case .all: return "全部"
        case .favorites: return "喜欢"
        case .source(let kind): return kind.shortName
        }
    }

    public static let chips: [LibraryFilter] = [.all, .favorites] + SourceKind.allCases.map { .source($0) }
}

public enum LibrarySort: String, CaseIterable, Sendable {
    case recent, title, artist, duration, mostPlayed

    public var title: String {
        switch self {
        case .recent: return "最近添加"
        case .title: return "标题"
        case .artist: return "作者"
        case .duration: return "时长"
        case .mostPlayed: return "最常播放"
        }
    }
}

public enum LibraryQuery {
    public static func apply(
        _ tracks: [Track],
        filter: LibraryFilter = .all,
        search: String = "",
        sort: LibrarySort = .recent
    ) -> [Track] {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = tracks.filter { track in
            switch filter {
            case .all: break
            case .favorites: if !track.isFavorite { return false }
            case .source(let kind): if track.sourceKind != kind { return false }
            }
            guard !needle.isEmpty else { return true }
            return track.title.lowercased().contains(needle)
                || track.artist.lowercased().contains(needle)
                || track.sourceKind.shortName.lowercased().contains(needle)
        }
        switch sort {
        case .recent:
            return filtered.sorted { $0.addedAt > $1.addedAt }
        case .title:
            return filtered.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .artist:
            return filtered.sorted {
                let order = $0.artist.localizedStandardCompare($1.artist)
                if order == .orderedSame { return $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                return order == .orderedAscending
            }
        case .duration:
            return filtered.sorted { $0.duration > $1.duration }
        case .mostPlayed:
            return filtered.sorted {
                if $0.playCount == $1.playCount { return $0.addedAt > $1.addedAt }
                return $0.playCount > $1.playCount
            }
        }
    }
}

extension Array {
    public mutating func moveElements(fromOffsets source: IndexSet, toOffset destination: Int) {
        let valid = source.filter { indices.contains($0) }
        guard !valid.isEmpty else { return }
        let moving = valid.map { self[$0] }
        let before = valid.filter { $0 < destination }.count
        for index in valid.sorted(by: >) { remove(at: index) }
        let target = Swift.max(0, Swift.min(count, destination - before))
        insert(contentsOf: moving, at: target)
    }
}
