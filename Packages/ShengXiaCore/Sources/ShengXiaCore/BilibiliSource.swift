import Foundation

public struct BilibiliSource: MediaSource {
    public let id = "bilibili"
    public let displayName = "哔哩哔哩"

    public var quality: AudioQuality

    public init(quality: AudioQuality = .best) {
        self.quality = quality
    }

    public func canHandle(_ input: String) -> Bool {
        if LinkParser.extractURLs(from: input).contains(where: LinkParser.isBilibiliHost) { return true }
        if LinkParser.firstBVID(in: input) != nil { return true }
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard LinkParser.extractURLs(from: trimmed).isEmpty else { return false }
        return trimmed.range(of: #"(?i)(?:^|[/._-])av\d+"#, options: .regularExpression) != nil
    }

    public func resolve(_ input: String, client: any HTTPClient) async throws -> ResolveStep {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let identity = try await resolveIdentity(from: text, client: client)
        try preflight(text)
        let cookie = try await bootstrapCookie(client: client)
        let video = try await fetchView(identity: identity, cookie: cookie, client: client)
        let page = try BilibiliParser.selectPage(video, requested: identity.page)
        let pick = try await fetchPlay(video: video, page: page, cookie: cookie, client: client)
        let referer = refererURL(video: video)
        let headers = [
            "User-Agent": BrowserIdentity.desktop,
            "Referer": referer,
            "Origin": "https://www.bilibili.com"
        ]
        let stream = RemoteStream(
            urls: pick.urls,
            headers: headers,
            kind: pick.kind,
            fileExtension: pick.fileExtension,
            formatLabel: pick.formatLabel
        )
        var pageURL: String
        if !video.bvid.isEmpty {
            pageURL = "https://www.bilibili.com/video/\(video.bvid)"
        } else {
            pageURL = "https://www.bilibili.com/video/av\(video.aid)"
        }
        if page.page > 1 { pageURL += "?p=\(page.page)" }
        return .ready(ResolvedMedia(
            title: BilibiliParser.displayTitle(video, page: page),
            author: video.owner,
            coverURL: video.cover,
            duration: video.duration > 0 ? video.duration : nil,
            sourceName: displayName,
            pageURL: pageURL,
            stream: stream
        ))
    }

    private func resolveIdentity(from text: String, client: any HTTPClient) async throws -> BilibiliIdentity {
        if let url = LinkParser.extractURLs(from: text).first(where: LinkParser.isBilibiliHost) {
            try preflight(url.absoluteString)
            if let direct = LinkParser.identity(from: url), direct.bvid != nil || direct.aid != nil {
                return direct
            }
            let response = try await HTTP.get(url, headers: pageHeaders, client: client)
            let final = response.finalURL ?? url
            try preflight(final.absoluteString)
            if var identity = LinkParser.identity(from: final), identity.bvid != nil || identity.aid != nil {
                if identity.page == nil { identity.page = LinkParser.pageNumber(from: url) }
                return identity
            }
            if let bvid = LinkParser.firstBVID(in: response.text) {
                return BilibiliIdentity(bvid: bvid, page: LinkParser.pageNumber(from: final) ?? LinkParser.pageNumber(from: url))
            }
            throw ResolveError.bilibiliMessage("短链接没有转到视频")
        }
        if let identity = LinkParser.bilibiliIdentity(in: text), identity.bvid != nil || identity.aid != nil {
            return identity
        }
        throw ResolveError.unsupportedLink
    }

    private func preflight(_ text: String) throws {
        let lower = text.lowercased()
        if lower.contains("live.bilibili.com") {
            throw ResolveError.bilibiliLiveUnsupported
        }
        if lower.contains("/bangumi/") {
            throw ResolveError.bilibiliBangumiUnsupported
        }
        if lower.contains("/cheese/") {
            throw ResolveError.bilibiliCheeseUnsupported
        }
    }

    private func bootstrapCookie(client: any HTTPClient) async throws -> String {
        let url = URL(string: "https://api.bilibili.com/x/frontend/finger/spi")!
        let response = try await HTTP.get(url, headers: apiHeaders(referer: "https://www.bilibili.com/", cookie: nil), client: client)
        guard response.statusCode == 200, let root = try? JSON.object(from: response.data),
              JSON.int(root, "code") == 0,
              let data = JSON.dictionary(root, "data"),
              let b3 = JSON.string(data, "b_3"), !b3.isEmpty else {
            return ""
        }
        let b4 = JSON.string(data, "b_4") ?? ""
        if b4.isEmpty { return "buvid3=\(b3)" }
        return "buvid3=\(b3); buvid4=\(b4)"
    }

    private func fetchView(identity: BilibiliIdentity, cookie: String, client: any HTTPClient) async throws -> BilibiliVideo {
        var items: [URLQueryItem] = []
        if let bvid = identity.bvid { items.append(URLQueryItem(name: "bvid", value: bvid)) }
        if let aid = identity.aid { items.append(URLQueryItem(name: "aid", value: String(aid))) }
        guard var components = URLComponents(string: "https://api.bilibili.com/x/web-interface/view") else {
            throw ResolveError.badResponse("无法构造哔哩哔哩地址")
        }
        components.queryItems = items
        guard let url = components.url else { throw ResolveError.badResponse("无法构造哔哩哔哩地址") }
        let referer = identity.bvid.map { "https://www.bilibili.com/video/\($0)/" } ?? "https://www.bilibili.com/"
        let response = try await HTTP.get(url, headers: apiHeaders(referer: referer, cookie: cookie), client: client)
        if response.statusCode == 412 { throw ResolveError.bilibiliBanned }
        guard response.statusCode == 200 else {
            throw ResolveError.bilibiliMessage("读取稿件失败（HTTP \(response.statusCode)）")
        }
        return try BilibiliParser.parseView(response.data)
    }

    private func fetchPlay(
        video: BilibiliVideo,
        page: BilibiliPage,
        cookie: String,
        client: any HTTPClient
    ) async throws -> BilibiliAudioPick {
        var items = [
            URLQueryItem(name: "cid", value: String(page.cid)),
            URLQueryItem(name: "fnval", value: "16"),
            URLQueryItem(name: "qn", value: "80"),
            URLQueryItem(name: "fourk", value: "1")
        ]
        if !video.bvid.isEmpty { items.insert(URLQueryItem(name: "bvid", value: video.bvid), at: 0) }
        else if video.aid > 0 { items.insert(URLQueryItem(name: "aid", value: String(video.aid)), at: 0) }
        guard var components = URLComponents(string: "https://api.bilibili.com/x/player/playurl") else {
            throw ResolveError.badResponse("无法构造音频地址")
        }
        components.queryItems = items
        guard let url = components.url else { throw ResolveError.badResponse("无法构造音频地址") }
        let response = try await HTTP.get(url, headers: apiHeaders(referer: refererURL(video: video), cookie: cookie), client: client)
        if response.statusCode == 412 { throw ResolveError.bilibiliBanned }
        guard response.statusCode == 200 else {
            throw ResolveError.bilibiliMessage("读取音频失败（HTTP \(response.statusCode)）")
        }
        return try BilibiliParser.parsePlay(response.data, quality: quality)
    }

    private func refererURL(video: BilibiliVideo) -> String {
        if !video.bvid.isEmpty { return "https://www.bilibili.com/video/\(video.bvid)/" }
        return "https://www.bilibili.com/video/av\(video.aid)/"
    }

    private var pageHeaders: [String: String] {
        [
            "User-Agent": BrowserIdentity.desktop,
            "Accept": "text/html,application/xhtml+xml"
        ]
    }

    private func apiHeaders(referer: String, cookie: String?) -> [String: String] {
        var headers = [
            "User-Agent": BrowserIdentity.desktop,
            "Referer": referer,
            "Origin": "https://www.bilibili.com",
            "Accept": "application/json, text/plain, */*"
        ]
        if let cookie, !cookie.isEmpty { headers["Cookie"] = cookie }
        return headers
    }
}
