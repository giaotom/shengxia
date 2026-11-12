import Foundation

public struct RankedDouyinURL: Equatable, Sendable {
    public var url: URL
    public var score: Int
    public var kind: StreamKind

    public init(url: URL, score: Int, kind: StreamKind) {
        self.url = url
        self.score = score
        self.kind = kind
    }
}

public enum DouyinURLPicker {
    public static func rank(_ urls: [URL]) -> [RankedDouyinURL] {
        var seen = Set<String>()
        let ranked = urls.compactMap { url -> RankedDouyinURL? in
            guard seen.insert(url.absoluteString).inserted, !isJunk(url) else { return nil }
            return RankedDouyinURL(url: url, score: score(url), kind: kind(url))
        }
        return ranked.sorted { lhs, rhs in
            if lhs.score == rhs.score { return lhs.url.absoluteString < rhs.url.absoluteString }
            return lhs.score > rhs.score
        }
    }

    public static func isJunk(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return true }
        let host = (url.host ?? "").lowercased()
        let path = url.path.lowercased()
        let blob = (host + path + (url.query ?? "")).lowercased()
        if host.contains("douyinstatic") || host.contains("bytegoofy") || host.contains("zijieapi") || host.contains("bytescm") {
            return true
        }
        if path.contains("uuu_265") || blob.contains("uuu_265") { return true }
        return false
    }

    public static func isUnsigned(_ url: URL) -> Bool {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        for item in items {
            let name = item.name.lowercased()
            if name == "signature" || name == "x-signature" { return false }
            if name == "tk", (item.value ?? "").lowercased().contains("webid") { return false }
        }
        return true
    }

    public static func kind(_ url: URL) -> StreamKind {
        let blob = (url.absoluteString).lowercased()
        if blob.contains("media-audio") || blob.contains("mime_type=audio") || blob.contains("audio_mp4") {
            return .audio
        }
        return .video
    }

    private static func score(_ url: URL) -> Int {
        let blob = url.absoluteString.lowercased()
        let host = (url.host ?? "").lowercased()
        var score = 0
        let audio = kind(url) == .audio
        let videoOnly = blob.contains("media-video") || blob.contains("mime_type=video")
        if audio {
            score += 80
        } else if videoOnly && !blob.contains(".mp4") {
            score += 40
        } else {
            score += 100
        }
        if isUnsigned(url) { score += 20 }
        if host.contains("zjcdn.com") { score += 10 }
        if host.contains("douyinvod.com") { score += 5 }
        return score
    }
}
