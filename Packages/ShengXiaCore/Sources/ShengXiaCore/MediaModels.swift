import Foundation

public enum StreamKind: String, Equatable, Sendable {
    case audio
    case video
}

public struct RemoteStream: Equatable, Sendable {
    public var urls: [URL]
    public var headers: [String: String]
    public var kind: StreamKind
    public var fileExtension: String
    public var formatLabel: String

    public init(
        urls: [URL],
        headers: [String: String],
        kind: StreamKind,
        fileExtension: String,
        formatLabel: String
    ) {
        self.urls = urls
        self.headers = headers
        self.kind = kind
        self.fileExtension = fileExtension
        self.formatLabel = formatLabel
    }
}

public struct ResolvedMedia: Equatable, Sendable {
    public var title: String
    public var author: String
    public var coverURL: URL?
    public var duration: TimeInterval?
    public var sourceName: String
    public var pageURL: String
    public var stream: RemoteStream

    public init(
        title: String,
        author: String,
        coverURL: URL?,
        duration: TimeInterval?,
        sourceName: String,
        pageURL: String,
        stream: RemoteStream
    ) {
        self.title = title
        self.author = author
        self.coverURL = coverURL
        self.duration = duration
        self.sourceName = sourceName
        self.pageURL = pageURL
        self.stream = stream
    }
}

public struct WebCaptureRequest: Equatable, Sendable {
    public var sourceName: String
    public var awemeID: String
    public var pageURL: URL
    public var userAgent: String
    public var referer: String

    public init(sourceName: String, awemeID: String, pageURL: URL, userAgent: String, referer: String) {
        self.sourceName = sourceName
        self.awemeID = awemeID
        self.pageURL = pageURL
        self.userAgent = userAgent
        self.referer = referer
    }
}

public enum ResolveStep: Equatable, Sendable {
    case ready(ResolvedMedia)
    case webCapture(WebCaptureRequest)
}

public protocol MediaSource {
    var id: String { get }
    var displayName: String { get }
    func canHandle(_ input: String) -> Bool
    func resolve(_ input: String, client: any HTTPClient) async throws -> ResolveStep
}
