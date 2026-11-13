import Foundation

public enum MediaKey {
    public static func key(forInput text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for url in LinkParser.extractURLs(from: trimmed) {
            if let key = key(for: url) { return key }
        }
        if LinkParser.extractURLs(from: trimmed).isEmpty, let identity = LinkParser.bilibiliIdentity(in: trimmed) {
            return bilibiliKey(identity)
        }
        return nil
    }

    public static func key(for url: URL) -> String? {
        if LinkParser.isBilibiliHost(url) {
            let host = (url.host ?? "").lowercased()
            if host.hasSuffix("b23.tv"), LinkParser.firstBVID(in: url.absoluteString) == nil { return nil }
            guard let identity = LinkParser.identity(from: url) else { return nil }
            return bilibiliKey(identity)
        }
        if LinkParser.isYouTubeHost(url), let id = LinkParser.youtubeID(in: url) {
            return "youtube:\(id)"
        }
        if LinkParser.isDouyinHost(url), let id = LinkParser.douyinID(in: url) {
            return "douyin:\(id)"
        }
        return nil
    }

    static func bilibiliKey(_ identity: BilibiliIdentity) -> String? {
        let page = identity.page ?? 1
        let suffix = page > 1 ? ":p\(page)" : ""
        if let bvid = identity.bvid { return "bilibili:\(bvid)\(suffix)" }
        if let aid = identity.aid { return "bilibili:av\(aid)\(suffix)" }
        return nil
    }
}

public enum BatchInput {
    public static func jobs(from text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var jobs: [String] = []
        var seen = Set<String>()
        func add(_ job: String) {
            let identity = MediaKey.key(forInput: job) ?? job
            if seen.insert(identity).inserted { jobs.append(job) }
        }
        let urls = LinkParser.extractURLs(from: trimmed)
        for url in urls where isSupported(url) {
            add(url.absoluteString)
        }
        let remainder = trimmed.replacingOccurrences(of: #"https?://\S+"#, with: " ", options: .regularExpression)
        for bvid in allBVIDs(in: remainder) {
            add(bvid)
        }
        if jobs.isEmpty { return [trimmed] }
        return jobs
    }

    public static func containsSupportedLink(_ text: String) -> Bool {
        let urls = LinkParser.extractURLs(from: text)
        if urls.contains(where: isSupported) { return true }
        return urls.isEmpty && LinkParser.firstBVID(in: text) != nil
    }

    public static func isSupported(_ url: URL) -> Bool {
        LinkParser.isBilibiliHost(url) || LinkParser.isDouyinHost(url) || LinkParser.isYouTubeHost(url)
    }

    public static func sourceKind(of job: String) -> SourceKind? {
        if let url = LinkParser.extractURLs(from: job).first {
            if LinkParser.isBilibiliHost(url) { return .bilibili }
            if LinkParser.isDouyinHost(url) { return .douyin }
            if LinkParser.isYouTubeHost(url) { return .youtube }
            return nil
        }
        return LinkParser.firstBVID(in: job) != nil ? .bilibili : nil
    }

    private static func allBVIDs(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"BV[0-9A-Za-z]{10}"#) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        }
    }
}

public enum AppLink {
    public static let scheme = "shengxia"

    public static func extractURL(for text: String) -> URL? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#/:")
        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "\(scheme)://extract?text=\(encoded)")
    }

    public static func extractText(from url: URL) -> String? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let action = (components?.host ?? "").lowercased()
        guard action == "extract" || action == "add" || action.isEmpty else { return nil }
        let items = components?.queryItems ?? []
        let parts = items
            .filter { ["url", "text", "u", "t"].contains($0.name.lowercased()) }
            .compactMap { $0.value?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !parts.isEmpty { return parts.joined(separator: "\n") }
        let path = (components?.path ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let decoded = path.removingPercentEncoding ?? path
        return decoded.isEmpty ? nil : decoded
    }
}
