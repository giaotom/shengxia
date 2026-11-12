import Foundation

public struct SourceRouter {
    public var sources: [any MediaSource]

    public init(sources: [any MediaSource] = [BilibiliSource(), DouyinSource(), YouTubeSource()]) {
        self.sources = sources
    }

    public func resolve(_ input: String, client: any HTTPClient) async throws -> ResolveStep {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { throw ResolveError.emptyInput }
        guard let source = pick(text) else { throw ResolveError.unsupportedLink }
        return try await source.resolve(text, client: client)
    }

    func pick(_ text: String) -> (any MediaSource)? {
        if let url = LinkParser.extractURLs(from: text).first,
           let match = sources.first(where: { $0.canHandle(url.absoluteString) }) {
            return match
        }
        return sources.first(where: { $0.canHandle(text) })
    }
}
