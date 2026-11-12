import Foundation

public struct BilibiliIdentity: Equatable, Sendable {
    public var bvid: String?
    public var aid: Int?
    public var page: Int?

    public init(bvid: String? = nil, aid: Int? = nil, page: Int? = nil) {
        self.bvid = bvid
        self.aid = aid
        self.page = page
    }
}

public enum LinkParser {
    private static let urlRegex: NSRegularExpression = {
        // Trim common trailing punctuation in a second pass so the pattern stays simple.
        try! NSRegularExpression(pattern: #"https?://[^\s<>"'，。！？、]+"#)
    }()

    private static let bvRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"BV[0-9A-Za-z]{10}"#)
    }()

    private static let avRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"(?i)(?:^|[/._-])av(\d+)"#)
    }()

    public static func extractURLs(from text: String) -> [URL] {
        let range = NSRange(text.startIndex..., in: text)
        return urlRegex.matches(in: text, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: text) else { return nil }
            var raw = String(text[swiftRange])
            while let last = raw.last, ".,);]）】>\"'".contains(last) {
                raw.removeLast()
            }
            return URL(string: raw)
        }
    }

    public static func firstBVID(in text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = bvRegex.firstMatch(in: text, range: range),
              let swiftRange = Range(match.range, in: text) else { return nil }
        return String(text[swiftRange])
    }

    public static func firstAID(in text: String) -> Int? {
        if let url = URL(string: text), let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let aid = components.queryItems?.first(where: { $0.name == "aid" })?.value,
           let value = Int(aid) {
            return value
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = avRegex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
              let swiftRange = Range(match.range(at: 1), in: text) else { return nil }
        return Int(text[swiftRange])
    }

    public static func identity(from url: URL) -> BilibiliIdentity? {
        let page = pageNumber(from: url)
        if let bvid = firstBVID(in: url.absoluteString) {
            return BilibiliIdentity(bvid: bvid, aid: nil, page: page)
        }
        if let aid = firstAID(in: url.absoluteString) {
            return BilibiliIdentity(bvid: nil, aid: aid, page: page)
        }
        return nil
    }

    public static func bilibiliIdentity(in text: String) -> BilibiliIdentity? {
        for url in extractURLs(from: text) where isBilibiliHost(url) {
            if let identity = identity(from: url) {
                return identity
            }
            // Short codes still belong to Bilibili; the source follows the redirect.
            return BilibiliIdentity(page: pageNumber(from: url))
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if extractURLs(from: trimmed).isEmpty {
            if let bvid = firstBVID(in: trimmed) {
                return BilibiliIdentity(bvid: bvid)
            }
            if let aid = firstAID(in: trimmed), trimmed.range(of: #"av\d+"#, options: [.regularExpression, .caseInsensitive]) != nil {
                return BilibiliIdentity(aid: aid)
            }
        }
        return nil
    }

    public static func isBilibiliHost(_ url: URL) -> Bool {
        let host = (url.host ?? "").lowercased()
        return host == "b23.tv" || host.hasSuffix(".b23.tv") || host.contains("bilibili.com")
    }

    public static func isDouyinHost(_ url: URL) -> Bool {
        let host = (url.host ?? "").lowercased()
        return host.contains("douyin.com") || host.contains("iesdouyin.com")
    }

    public static func douyinID(in url: URL) -> String? {
        if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            for name in ["modal_id", "aweme_id", "item_id", "item_ids", "vid"] {
                if let value = items.first(where: { $0.name == name })?.value, isAwemeID(value) {
                    return value
                }
            }
        }
        for part in url.path.split(separator: "/") {
            let text = String(part)
            if isAwemeID(text) { return text }
        }
        return nil
    }

    public static func isAwemeID(_ text: String) -> Bool {
        let digits = text.allSatisfy(\.isNumber)
        return digits && (15...20).contains(text.count)
    }

    public static func pageNumber(from url: URL) -> Int? {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let raw = items.first(where: { $0.name == "p" })?.value,
              let page = Int(raw), page > 0 else { return nil }
        return page
    }
}
