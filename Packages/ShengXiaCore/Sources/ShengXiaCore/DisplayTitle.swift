import Foundation

public enum DisplayTitle {
    public static let limit = 10

    /// First `limit` extended grapheme clusters. Existing library rows are not rewritten here.
    public static func shortened(_ raw: String, limit: Int = DisplayTitle.limit) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "未命名音轨" : trimmed
        guard base.count > limit else { return base }
        return String(base.prefix(limit))
    }
}
