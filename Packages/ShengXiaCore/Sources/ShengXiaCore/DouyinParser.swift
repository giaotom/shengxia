import Foundation

struct DouyinParsedItem: Equatable {
    var awemeID: String
    var title: String
    var author: String
    var coverURL: URL?
    var duration: TimeInterval?
    var playURLs: [URL]
    var isImagePost: Bool
}

enum DouyinDocumentParser {
    enum Result: Equatable {
        case media(DouyinParsedItem)
        case imagePost
        case needWeb(String?)
    }

    static func parse(_ text: String) -> Result {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            return parseJSONText(trimmed)
        }
        if let embedded = extractJSONObject(after: "window._ROUTER_DATA", in: text) ?? extractJSONObject(after: "_ROUTER_DATA", in: text) {
            let parsed = parseJSONText(embedded)
            if case .needWeb = parsed {
                return .needWeb(awemeHint(in: embedded) ?? awemeHint(in: text))
            }
            return parsed
        }
        if let render = renderDataJSON(in: text) {
            return parseJSONText(render)
        }
        return .needWeb(awemeHint(in: text))
    }

    static func item(in text: String, expectedID: String) -> DouyinParsedItem? {
        switch parse(text) {
        case .media(let item):
            if item.awemeID.isEmpty || item.awemeID == expectedID { return item }
            return nil
        case .imagePost, .needWeb:
            return nil
        }
    }

    static func extractJSONObject(after marker: String, in text: String) -> String? {
        guard let range = text.range(of: marker) else { return nil }
        let tail = text[range.upperBound...]
        guard let start = tail.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        for index in tail[start...].indices {
            let character = tail[index]
            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
                continue
            }
            if character == "\"" {
                inString = true
                continue
            }
            if character == "{" { depth += 1 }
            if character == "}" {
                depth -= 1
                if depth == 0 { return String(tail[start...index]) }
            }
        }
        return nil
    }

    private static func renderDataJSON(in html: String) -> String? {
        guard let marker = html.range(of: "RENDER_DATA") else { return nil }
        let tail = html[marker.upperBound...]
        guard let start = tail.firstIndex(of: ">") else { return nil }
        let body = tail[tail.index(after: start)...]
        guard let end = body.range(of: "</script>") else { return nil }
        let raw = String(body[..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let decoded = raw.removingPercentEncoding ?? raw
        if decoded.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") { return decoded }
        return nil
    }

    private static func parseJSONText(_ text: String) -> Result {
        guard let any = JSON.any(from: text) else { return .needWeb(awemeHint(in: text)) }
        var items: [[String: Any]] = []
        collectItems(any, into: &items)
        let parsed = items.compactMap(parseItem)
        if let media = parsed.first(where: { !$0.playURLs.isEmpty && !$0.isImagePost }) {
            return .media(media)
        }
        if parsed.contains(where: \.isImagePost) {
            return .imagePost
        }
        return .needWeb(awemeHint(in: text))
    }

    private static func collectItems(_ any: Any, into items: inout [[String: Any]]) {
        if let dict = any as? [String: Any] {
            let hasID = JSON.string(dict, "aweme_id") != nil || JSON.string(dict, "awemeId") != nil
            let hasBody = dict["video"] != nil || dict["images"] != nil || dict["desc"] != nil
            if hasID && hasBody { items.append(dict) }
            for (key, value) in dict where key != "music" {
                collectItems(value, into: &items)
            }
        } else if let array = any as? [Any] {
            for value in array { collectItems(value, into: &items) }
        }
    }

    private static func parseItem(_ dict: [String: Any]) -> DouyinParsedItem? {
        let awemeID = JSON.string(dict, "aweme_id") ?? JSON.string(dict, "awemeId") ?? ""
        let title = (JSON.string(dict, "desc") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let author = JSON.dictionary(dict, "author").flatMap { JSON.string($0, "nickname") } ?? ""
        let images = JSON.array(dict, "images") ?? []
        var urls: [URL] = []
        var cover: URL?
        var duration: TimeInterval?
        if let video = JSON.dictionary(dict, "video") {
            appendPlayURLs(from: video, into: &urls)
            cover = coverURL(in: video)
            if let raw = JSON.double(video, "duration"), raw > 0 {
                duration = raw >= 1000 ? raw / 1000 : raw
            }
        }
        let unique = uniqueURLs(urls)
        let imagePost = !images.isEmpty && unique.isEmpty
        if unique.isEmpty && !imagePost && awemeID.isEmpty && title.isEmpty { return nil }
        return DouyinParsedItem(
            awemeID: awemeID,
            title: title,
            author: author,
            coverURL: cover,
            duration: duration,
            playURLs: unique,
            isImagePost: imagePost
        )
    }

    private static func appendPlayURLs(from video: [String: Any], into urls: inout [URL]) {
        appendList(video["play_addr"] ?? video["playAddr"], into: &urls)
        appendList(video["download_addr"] ?? video["downloadAddr"], into: &urls)
        for key in ["bit_rate", "bitRate"] {
            for item in JSON.array(video, key) ?? [] {
                guard let bit = item as? [String: Any] else { continue }
                appendList(bit["play_addr"] ?? bit["playAddr"], into: &urls)
            }
        }
    }

    private static func appendList(_ any: Any?, into urls: inout [URL]) {
        guard let dict = any as? [String: Any] else { return }
        let list = (dict["url_list"] as? [Any]) ?? (dict["urlList"] as? [Any]) ?? []
        for item in list {
            guard let text = item as? String else { continue }
            var cleaned = text.replacingOccurrences(of: "\\u002F", with: "/")
            cleaned = cleaned.replacingOccurrences(of: "\\/", with: "/")
            cleaned = cleaned.replacingOccurrences(of: "/playwm", with: "/play")
            if let url = URLText.httpsURL(cleaned) { urls.append(url) }
        }
    }

    private static func coverURL(in video: [String: Any]) -> URL? {
        for key in ["cover", "origin_cover", "originCover", "dynamic_cover"] {
            guard let cover = JSON.dictionary(video, key) else { continue }
            let list = (cover["url_list"] as? [Any]) ?? (cover["urlList"] as? [Any]) ?? []
            if let first = list.first as? String, let url = URLText.httpsURL(first) { return url }
        }
        return nil
    }

    private static func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.absoluteString).inserted }
    }

    private static func awemeHint(in text: String) -> String? {
        let patterns = [
            #""itemId"\s*:\s*"(\d{15,20})""#,
            #""aweme_id"\s*:\s*"(\d{15,20})""#,
            #""lastPath"\s*:\s*"(\d{15,20})""#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: text) else { continue }
            return String(text[range])
        }
        return nil
    }
}
