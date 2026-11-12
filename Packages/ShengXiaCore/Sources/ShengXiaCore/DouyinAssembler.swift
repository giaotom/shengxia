import Foundation

public enum DouyinCaptureAssembler {
    public static func assemble(
        detailBodies: [String],
        mediaURLs: [URL],
        expectedID: String,
        pageURL: String
    ) throws -> ResolvedMedia {
        for body in detailBodies {
            switch DouyinDocumentParser.parse(body) {
            case .imagePost:
                let mentionsThisVideo = body.contains("\"aweme_id\":\"\(expectedID)\"") || body.contains("\"awemeId\":\"\(expectedID)\"")
                if mentionsThisVideo && !body.contains("play_addr") && !body.contains("playAddr") {
                    throw ResolveError.douyinImagePost
                }
            case .media(let item):
                guard item.awemeID.isEmpty || item.awemeID == expectedID else { continue }
                if let media = make(item: item, pageURL: pageURL, fallbackTitle: false) {
                    return media
                }
            case .needWeb:
                continue
            }
        }
        let ranked = DouyinURLPicker.rank(mediaURLs)
        guard let best = ranked.first else { throw ResolveError.douyinResolveFailed }
        let audio = best.kind == .audio
        return ResolvedMedia(
            title: "抖音视频",
            author: "抖音",
            coverURL: nil,
            duration: nil,
            sourceName: "抖音",
            pageURL: pageURL,
            stream: RemoteStream(
                urls: ranked.map(\.url),
                headers: downloadHeaders,
                kind: audio ? .audio : .video,
                fileExtension: audio ? "m4a" : "mp4",
                formatLabel: audio ? "M4A" : "MP4"
            )
        )
    }

    static func make(item: DouyinParsedItem, pageURL: String, fallbackTitle: Bool) -> ResolvedMedia? {
        if item.isImagePost || item.playURLs.isEmpty { return nil }
        let ranked = DouyinURLPicker.rank(item.playURLs)
        guard let best = ranked.first else { return nil }
        let audio = best.kind == .audio
        let title = item.title.isEmpty ? (fallbackTitle ? "抖音视频" : "抖音视频") : item.title
        let author = item.author.isEmpty ? "抖音" : item.author
        return ResolvedMedia(
            title: title,
            author: author,
            coverURL: item.coverURL,
            duration: item.duration,
            sourceName: "抖音",
            pageURL: pageURL,
            stream: RemoteStream(
                urls: ranked.map(\.url),
                headers: downloadHeaders,
                kind: audio ? .audio : .video,
                fileExtension: audio ? "m4a" : "mp4",
                formatLabel: audio ? "M4A" : "MP4"
            )
        )
    }

    static var downloadHeaders: [String: String] {
        [
            "User-Agent": BrowserIdentity.desktop,
            "Referer": "https://www.douyin.com/",
            "Origin": "https://www.douyin.com"
        ]
    }
}
