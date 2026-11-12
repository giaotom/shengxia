import Foundation

public struct DouyinSource: MediaSource {
    public let id = "douyin"
    public let displayName = "抖音"

    public init() {}

    public func canHandle(_ input: String) -> Bool {
        LinkParser.extractURLs(from: input).contains(where: LinkParser.isDouyinHost)
    }

    public func resolve(_ input: String, client: any HTTPClient) async throws -> ResolveStep {
        guard let url = LinkParser.extractURLs(from: input).first(where: LinkParser.isDouyinHost) else {
            throw ResolveError.douyinNoVideoID
        }
        try preflight(url)
        let (awemeID, firstDocument) = try await resolveID(from: url, client: client)
        if let document = firstDocument {
            if let ready = try readyMedia(in: document, awemeID: awemeID) {
                return .ready(ready)
            }
        }
        let shareURL = URL(string: "https://www.iesdouyin.com/share/video/\(awemeID)/")!
        if firstDocument == nil {
            let share = try await HTTP.get(shareURL, headers: mobileHeaders(referer: shareURL.absoluteString), client: client)
            if let ready = try readyMedia(in: share.text, awemeID: awemeID) {
                return .ready(ready)
            }
        }
        for endpoint in fallbackEndpoints(awemeID) {
            let response = try await HTTP.get(endpoint, headers: mobileHeaders(referer: shareURL.absoluteString), client: client)
            if response.data.isEmpty { continue }
            if let ready = try readyMedia(in: response.text, awemeID: awemeID) {
                return .ready(ready)
            }
        }
        guard let pageURL = URL(string: "https://www.douyin.com/video/\(awemeID)") else {
            throw ResolveError.douyinResolveFailed
        }
        return .webCapture(WebCaptureRequest(
            sourceName: displayName,
            awemeID: awemeID,
            pageURL: pageURL,
            userAgent: BrowserIdentity.desktop,
            referer: "https://www.douyin.com/"
        ))
    }

    private func resolveID(from url: URL, client: any HTTPClient) async throws -> (String, String?) {
        if isLive(url) { throw ResolveError.douyinLiveUnsupported }
        if let existing = LinkParser.douyinID(in: url) {
            return (existing, nil)
        }
        let response = try await HTTP.get(url, headers: mobileHeaders(referer: "https://www.douyin.com/"), client: client)
        let final = response.finalURL ?? url
        if isLive(final) { throw ResolveError.douyinLiveUnsupported }
        if let id = LinkParser.douyinID(in: final) ?? douyinID(in: response.text) {
            let document = final.path.contains("/share/video/") ? response.text : nil
            return (id, document)
        }
        if final.path.lowercased().contains("/user/") { throw ResolveError.douyinNotAVideo }
        throw ResolveError.douyinNoVideoID
    }

    private func readyMedia(in document: String, awemeID: String) throws -> ResolvedMedia? {
        switch DouyinDocumentParser.parse(document) {
        case .imagePost:
            throw ResolveError.douyinImagePost
        case .media(let item):
            guard item.awemeID.isEmpty || item.awemeID == awemeID else { return nil }
            let page = "https://www.douyin.com/video/\(awemeID)"
            return DouyinCaptureAssembler.make(item: item, pageURL: page, fallbackTitle: true)
        case .needWeb:
            return nil
        }
    }

    private func fallbackEndpoints(_ id: String) -> [URL] {
        [
            URL(string: "https://www.iesdouyin.com/web/api/v2/aweme/iteminfo/?item_ids=\(id)&use_new_select_scope=0&reflow_source=reflow_page&aid=1128&device_platform=webapp")!,
            URL(string: "https://www.iesdouyin.com/web/api/v2/aweme/slidesinfo/?aweme_ids=\(id)&aid=1128")!
        ]
    }

    private func preflight(_ url: URL) throws {
        if isLive(url) { throw ResolveError.douyinLiveUnsupported }
    }

    private func isLive(_ url: URL) -> Bool {
        let host = (url.host ?? "").lowercased()
        return host.contains("live.douyin.com") || url.path.lowercased().contains("/live")
    }

    private func douyinID(in text: String) -> String? {
        let patterns = [
            #"video/(\d{15,20})"#,
            #""aweme_id"\s*:\s*"(\d{15,20})""#,
            #""itemId"\s*:\s*"(\d{15,20})""#
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

    private func mobileHeaders(referer: String) -> [String: String] {
        [
            "User-Agent": BrowserIdentity.iphone,
            "Referer": referer,
            "Accept": "text/html,application/json;q=0.9,*/*;q=0.8",
            "Agw-Js-Conv": "str"
        ]
    }
}
