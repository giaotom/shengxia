import Foundation

struct BilibiliPage: Equatable {
    var page: Int
    var cid: Int
    var part: String
}

struct BilibiliVideo: Equatable {
    var bvid: String
    var aid: Int
    var title: String
    var owner: String
    var cover: URL?
    var duration: TimeInterval
    var cid: Int
    var pages: [BilibiliPage]
}

struct BilibiliAudioPick: Equatable {
    var urls: [URL]
    var kind: StreamKind
    var fileExtension: String
    var formatLabel: String
}

enum BilibiliParser {
    static func parseView(_ data: Data) throws -> BilibiliVideo {
        let root = try JSON.object(from: data)
        let code = JSON.int(root, "code") ?? -1
        let message = JSON.string(root, "message") ?? ""
        try mapCode(code, message: message, context: "读取稿件")
        guard let data = JSON.dictionary(root, "data") else {
            throw ResolveError.bilibiliMessage("哔哩哔哩没有返回稿件信息")
        }
        let bvid = JSON.string(data, "bvid") ?? ""
        let aid = JSON.int(data, "aid") ?? 0
        let title = (JSON.string(data, "title") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let owner = JSON.dictionary(data, "owner").flatMap { JSON.string($0, "name") } ?? "哔哩哔哩"
        let cid = JSON.int(data, "cid") ?? 0
        let duration = TimeInterval(JSON.int(data, "duration") ?? 0)
        let pages = (JSON.array(data, "pages") ?? []).compactMap { item -> BilibiliPage? in
            guard let page = item as? [String: Any], let pageCID = JSON.int(page, "cid") else { return nil }
            return BilibiliPage(
                page: JSON.int(page, "page") ?? 1,
                cid: pageCID,
                part: JSON.string(page, "part") ?? ""
            )
        }
        return BilibiliVideo(
            bvid: bvid,
            aid: aid,
            title: title.isEmpty ? "未命名稿件" : title,
            owner: owner,
            cover: URLText.httpsURL(JSON.string(data, "pic")),
            duration: duration,
            cid: cid,
            pages: pages
        )
    }

    static func selectPage(_ video: BilibiliVideo, requested: Int?) throws -> BilibiliPage {
        if let requested {
            if let page = video.pages.first(where: { $0.page == requested }) {
                return page
            }
            throw ResolveError.bilibiliMessage("没有找到第 \(requested) P")
        }
        if let match = video.pages.first(where: { $0.cid == video.cid }) {
            return match
        }
        if let first = video.pages.first { return first }
        if video.cid > 0 {
            return BilibiliPage(page: 1, cid: video.cid, part: "")
        }
        throw ResolveError.bilibiliMessage("没有找到视频分P")
    }

    static func displayTitle(_ video: BilibiliVideo, page: BilibiliPage) -> String {
        let part = page.part.trimmingCharacters(in: .whitespacesAndNewlines)
        if part.isEmpty || part == video.title { return video.title }
        return "\(video.title) · \(part)"
    }

    static func parsePlay(_ data: Data) throws -> BilibiliAudioPick {
        let root = try JSON.object(from: data)
        let code = JSON.int(root, "code") ?? -1
        let message = JSON.string(root, "message") ?? ""
        try mapCode(code, message: message, context: "读取音频")
        guard let payload = JSON.dictionary(root, "data") else {
            throw ResolveError.bilibiliNoAudio
        }
        if let dash = JSON.dictionary(payload, "dash") {
            let candidates = audioCandidates(in: dash)
            if let best = candidates.max(by: { $0.bandwidth < $1.bandwidth }) {
                return BilibiliAudioPick(
                    urls: best.urls,
                    kind: .audio,
                    fileExtension: best.fileExtension,
                    formatLabel: best.formatLabel
                )
            }
        }
        let format = (JSON.string(payload, "format") ?? "").lowercased()
        if format.contains("flv") {
            throw ResolveError.bilibiliFLVOnly
        }
        if let durl = JSON.array(payload, "durl"),
           let first = durl.first as? [String: Any],
           let primary = URLText.httpsURL(JSON.string(first, "url")) {
            var urls = [primary]
            for item in JSON.array(first, "backup_url") ?? [] {
                if let text = item as? String, let url = URLText.httpsURL(text), !urls.contains(url) {
                    urls.append(url)
                }
            }
            return BilibiliAudioPick(urls: urls, kind: .video, fileExtension: "mp4", formatLabel: "MP4")
        }
        throw ResolveError.bilibiliNoAudio
    }

    static func mapCode(_ code: Int, message: String, context: String) throws {
        if message.contains("大会员") || message.contains("付费") {
            throw ResolveError.bilibiliVipBlocked
        }
        switch code {
        case 0:
            return
        case -404:
            throw ResolveError.bilibiliNotFound
        case -412:
            throw ResolveError.bilibiliBanned
        case -403, 62002, 62012:
            throw ResolveError.bilibiliHidden
        default:
            let detail = message.isEmpty ? "未知错误" : message
            throw ResolveError.bilibiliMessage("\(context)失败：\(detail)（\(code)）")
        }
    }

    private struct Candidate {
        var urls: [URL]
        var bandwidth: Int
        var fileExtension: String
        var formatLabel: String
    }

    private static func audioCandidates(in dash: [String: Any]) -> [Candidate] {
        var raw: [[String: Any]] = []
        for item in JSON.array(dash, "audio") ?? [] {
            if let audio = item as? [String: Any] { raw.append(audio) }
        }
        if let flac = JSON.dictionary(dash, "flac") {
            if let audio = JSON.dictionary(flac, "audio") {
                raw.append(audio)
            } else if let list = JSON.array(flac, "audio") {
                for item in list {
                    if let audio = item as? [String: Any] { raw.append(audio) }
                }
            }
        }
        return raw.compactMap(candidate(from:))
    }

    private static func candidate(from audio: [String: Any]) -> Candidate? {
        let codecs = JSON.string(audio, "codecs") ?? ""
        let mime = JSON.string(audio, "mimeType") ?? JSON.string(audio, "mime_type") ?? ""
        guard isPlayable(codecs: codecs, mime: mime) else { return nil }
        guard let primary = URLText.httpsURL(JSON.string(audio, "baseUrl") ?? JSON.string(audio, "base_url")) else {
            return nil
        }
        var urls = [primary]
        for key in ["backupUrl", "backup_url"] {
            for item in JSON.array(audio, key) ?? [] {
                if let text = item as? String, let url = URLText.httpsURL(text), !urls.contains(url) {
                    urls.append(url)
                }
            }
        }
        let codecLower = codecs.lowercased()
        let mimeLower = mime.lowercased()
        let isFLAC = codecLower.contains("flac") || mimeLower.contains("flac")
        return Candidate(
            urls: urls,
            bandwidth: JSON.int(audio, "bandwidth") ?? 0,
            fileExtension: isFLAC ? "flac" : "m4a",
            formatLabel: isFLAC ? "FLAC" : "M4A（AAC）"
        )
    }

    private static func isPlayable(codecs: String, mime: String) -> Bool {
        let codecs = codecs.lowercased()
        let mime = mime.lowercased()
        if codecs.contains("ac-4") || codecs.contains("ec-3") || codecs.contains("eac3") || codecs.contains("ac-3") {
            return false
        }
        return codecs.contains("mp4a") || codecs.contains("flac") || mime.contains("audio/mp4") || mime.contains("audio/flac")
    }
}
