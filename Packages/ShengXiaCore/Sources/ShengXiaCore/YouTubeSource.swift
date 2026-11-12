import Foundation

public struct YouTubeSource: MediaSource {
    public let id = "youtube"
    public let displayName = "YouTube"

    public init() {}

    public func canHandle(_ input: String) -> Bool {
        LinkParser.extractURLs(from: input).contains(where: LinkParser.isYouTubeHost)
    }

    public func resolve(_ input: String, client: any HTTPClient) async throws -> ResolveStep {
        guard let url = LinkParser.extractURLs(from: input).first(where: LinkParser.isYouTubeHost),
              let videoID = LinkParser.youtubeID(in: url) else {
            throw ResolveError.youtubeNotAVideo
        }
        var sawRetry = false
        var sawNoAudio = false
        for preset in YouTubeClients.all {
            do {
                let response = try await requestPlayer(preset, videoID: videoID, client: client)
                if response.data.isEmpty {
                    sawRetry = true
                    continue
                }
                switch try YouTubeParser.parse(response.data, videoID: videoID, headers: preset.downloadHeaders) {
                case .ready(let media):
                    return .ready(media)
                case .retry:
                    sawRetry = true
                case .noAudio:
                    sawNoAudio = true
                }
            } catch let error as ResolveError {
                switch error {
                case .network:
                    continue
                case .badResponse:
                    sawRetry = true
                default:
                    throw error
                }
            }
        }
        if sawNoAudio { throw ResolveError.youtubeNoAudio }
        if sawRetry { throw ResolveError.youtubeResolveFailed }
        throw ResolveError.youtubeConnectionFailed
    }

    private func requestPlayer(
        _ preset: YouTubeClientPreset,
        videoID: String,
        client: any HTTPClient
    ) async throws -> HTTPResponse {
        let body: [String: Any] = [
            "context": ["client": preset.context],
            "videoId": videoID,
            "contentCheckOk": true,
            "racyCheckOk": true
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        return try await HTTP.post(
            YouTubeClients.playerURL,
            body: data,
            headers: preset.requestHeaders,
            client: client
        )
    }
}

struct YouTubeClientPreset {
    var context: [String: Any]
    var userAgent: String

    var requestHeaders: [String: String] {
        [
            "Content-Type": "application/json",
            "User-Agent": userAgent,
            "Origin": "https://www.youtube.com",
            "Referer": "https://www.youtube.com/"
        ]
    }

    var downloadHeaders: [String: String] {
        [
            "User-Agent": userAgent,
            "Origin": "https://www.youtube.com",
            "Referer": "https://www.youtube.com/",
            "Accept": "*/*"
        ]
    }
}

/// InnerTube clients that return a direct `url` on audio/mp4 formats (no signature cipher).
/// VISIONOS is first: as of November 2026 its itag 140 URL can be downloaded in full.
/// ANDROID_VR stays on 1.65.10 because newer builds often return SABR streams with no URL.
enum YouTubeClients {
    static let playerURL = URL(string: "https://www.youtube.com/youtubei/v1/player?prettyPrint=false")!

    static let visionOSUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
    static let androidVRUserAgent =
        "com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip"
    static let iosUserAgent =
        "com.google.ios.youtube/21.26.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)"

    static let all: [YouTubeClientPreset] = [
        YouTubeClientPreset(
            context: [
                "clientName": "VISIONOS",
                "clientVersion": "1.02",
                "deviceMake": "Apple",
                "deviceModel": "RealityDevice17,1",
                "osName": "visionOS",
                "osVersion": "26.5.23O471",
                "userAgent": visionOSUserAgent,
                "hl": "en"
            ],
            userAgent: visionOSUserAgent
        ),
        YouTubeClientPreset(
            context: [
                "clientName": "ANDROID_VR",
                "clientVersion": "1.65.10",
                "deviceMake": "Oculus",
                "deviceModel": "Quest 3",
                "androidSdkVersion": 32,
                "osName": "Android",
                "osVersion": "12L",
                "userAgent": androidVRUserAgent,
                "hl": "en"
            ],
            userAgent: androidVRUserAgent
        ),
        YouTubeClientPreset(
            context: [
                "clientName": "IOS",
                "clientVersion": "21.26.4",
                "deviceMake": "Apple",
                "deviceModel": "iPhone16,2",
                "osName": "iPhone",
                "osVersion": "18.3.2.22D82",
                "userAgent": iosUserAgent,
                "hl": "en"
            ],
            userAgent: iosUserAgent
        )
    ]
}
