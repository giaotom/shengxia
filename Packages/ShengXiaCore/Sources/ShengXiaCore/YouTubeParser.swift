import Foundation

enum YouTubeParseResult {
    case ready(ResolvedMedia)
    case retry
    case noAudio
}

enum YouTubeParser {
    static func parse(_ data: Data, videoID: String, headers: [String: String]) throws -> YouTubeParseResult {
        let root = try JSON.object(from: data)
        let playability = JSON.dictionary(root, "playabilityStatus") ?? [:]
        let status = (JSON.string(playability, "status") ?? "").uppercased()
        let reason = reasonText(playability)
        let details = JSON.dictionary(root, "videoDetails") ?? [:]
        if JSON.bool(details, "isPrivate") == true {
            throw ResolveError.youtubePrivate
        }
        if let returnedID = JSON.string(details, "videoId"), !returnedID.isEmpty, returnedID != videoID {
            return .retry
        }
        switch classify(status: status, reason: reason) {
        case .age:
            throw ResolveError.youtubeAgeRestricted
        case .members:
            throw ResolveError.youtubeMembersOnly
        case .privateVideo:
            throw ResolveError.youtubePrivate
        case .live:
            throw ResolveError.youtubeLiveUnsupported
        case .region:
            throw ResolveError.youtubeRegionBlocked
        case .unavailable:
            throw ResolveError.youtubeUnavailable
        case .retry:
            return .retry
        case .ok:
            break
        }

        let streaming = JSON.dictionary(root, "streamingData") ?? [:]
        let adaptive = candidates(JSON.array(streaming, "adaptiveFormats") ?? [])
        let progressive = candidates(JSON.array(streaming, "formats") ?? [])
        guard let pick = pickAudio(adaptive: adaptive, progressive: progressive) else {
            let direct = adaptive + progressive
            let onlyWebM = direct.contains { $0.url != nil && $0.mime.hasPrefix("audio/webm") }
            return onlyWebM ? .noAudio : .retry
        }
        guard let url = pick.url else { return .noAudio }
        let title = (JSON.string(details, "title") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let author = (JSON.string(details, "author") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let length = TimeInterval(JSON.int(details, "lengthSeconds") ?? 0)
        return .ready(ResolvedMedia(
            title: title.isEmpty ? "未命名视频" : title,
            author: author.isEmpty ? "YouTube" : author,
            coverURL: coverURL(details),
            duration: length > 0 ? length : nil,
            sourceName: "YouTube",
            pageURL: "https://www.youtube.com/watch?v=\(videoID)",
            stream: RemoteStream(
                urls: [url],
                headers: headers,
                kind: pick.kind,
                fileExtension: pick.fileExtension,
                formatLabel: "M4A（AAC）"
            )
        ))
    }

    private enum Playability {
        case ok
        case age
        case members
        case privateVideo
        case live
        case region
        case unavailable
        case retry
    }

    private static func classify(status: String, reason: String) -> Playability {
        let text = normalize(reason)
        if status == "LIVE_STREAM" || text.contains("live event will begin") {
            return .live
        }
        if text.contains("confirm your age") || text.contains("age-restricted") || text.contains("age restricted")
            || text.contains("年龄") || text.contains("inappropriate for some users") {
            return .age
        }
        if text.contains("member") || text.contains("join this channel") || text.contains("会员") {
            return .members
        }
        if text.contains("private") || text.contains("私密") || text.contains("私人") || text.contains("私享") {
            return .privateVideo
        }
        if text.contains("not a bot") || text.contains("not a robot") || text.contains("机器人") {
            return .retry
        }
        if text.contains("country") || text.contains("region") || text.contains("所在的国家") || text.contains("地区无法") {
            return .region
        }
        if status == "OK" {
            return .ok
        }
        if status == "LOGIN_REQUIRED" {
            return .retry
        }
        if status == "ERROR" || status == "UNPLAYABLE" || text.contains("unavailable") || text.contains("removed")
            || text.contains("deleted") || text.contains("不可用") || text.contains("已删除") || text.contains("已移除") {
            return .unavailable
        }
        if status.isEmpty {
            return .retry
        }
        return .unavailable
    }

    private struct Candidate {
        var itag: Int
        var mime: String
        var bitrate: Int
        var url: URL?
        var kind: StreamKind
        var fileExtension: String
    }

    /// Prefer itag 140 (128kbps AAC). Otherwise the highest AAC, with itag 139 last.
    /// WebM/Opus is ignored because AVFoundation cannot play it. Muxed MP4 is only
    /// used when no audio-only AAC URL exists, and the app extracts the audio later.
    private static func pickAudio(adaptive: [Candidate], progressive: [Candidate]) -> Candidate? {
        let aac = adaptive.filter { $0.kind == .audio && $0.url != nil && $0.mime.hasPrefix("audio/mp4") }
        if let preferred = aac.first(where: { $0.itag == 140 }) { return preferred }
        let better = aac.filter { $0.itag != 139 }
        if let best = better.max(by: { $0.bitrate < $1.bitrate }) { return best }
        if let low = aac.first(where: { $0.itag == 139 }) { return low }
        let muxed = progressive.filter { $0.url != nil && $0.mime.hasPrefix("video/mp4") }
        if let itag18 = muxed.first(where: { $0.itag == 18 }) { return itag18 }
        return muxed.max(by: { $0.bitrate < $1.bitrate })
    }

    private static func candidates(_ items: [Any]) -> [Candidate] {
        items.compactMap { item in
            guard let dict = item as? [String: Any] else { return nil }
            if JSON.string(dict, "url") == nil { return nil }
            let mime = (JSON.string(dict, "mimeType") ?? "").lowercased()
            let audio = mime.hasPrefix("audio/")
            return Candidate(
                itag: JSON.int(dict, "itag") ?? 0,
                mime: mime,
                bitrate: JSON.int(dict, "bitrate") ?? JSON.int(dict, "averageBitrate") ?? 0,
                url: URLText.httpsURL(JSON.string(dict, "url")),
                kind: audio ? .audio : .video,
                fileExtension: audio ? "m4a" : "mp4"
            )
        }
    }

    private static func coverURL(_ details: [String: Any]) -> URL? {
        guard let thumbs = JSON.dictionary(details, "thumbnail").flatMap({ JSON.array($0, "thumbnails") }) else {
            return nil
        }
        let ranked: [(Int, URL)] = thumbs.compactMap { item in
            guard let dict = item as? [String: Any], let url = URLText.httpsURL(JSON.string(dict, "url")) else {
                return nil
            }
            return (JSON.int(dict, "width") ?? 0, url)
        }
        return ranked.max(by: { $0.0 < $1.0 })?.1
    }

    private static func reasonText(_ playability: [String: Any]) -> String {
        var parts: [String] = []
        if let reason = JSON.string(playability, "reason") { parts.append(reason) }
        if let messages = JSON.array(playability, "messages") {
            for item in messages {
                if let text = item as? String { parts.append(text) }
            }
        }
        return parts.joined(separator: " ")
    }

    private static func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
    }
}
