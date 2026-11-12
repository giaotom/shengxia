import Foundation

struct Track: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var artist: String
    var sourceName: String
    var sourceURL: String?
    var relativePath: String
    var coverRelativePath: String?
    var duration: TimeInterval
    var formatLabel: String
    var addedAt: Date
    var byteCount: Int64
}

struct LibraryIndex: Codable {
    var version: Int
    var tracks: [Track]
}
