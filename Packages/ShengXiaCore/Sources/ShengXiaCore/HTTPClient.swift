import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct HTTPResponse: Equatable, Sendable {
    public var statusCode: Int
    public var finalURL: URL?
    public var headers: [String: String]
    public var data: Data

    public init(statusCode: Int, finalURL: URL?, headers: [String: String] = [:], data: Data) {
        self.statusCode = statusCode
        self.finalURL = finalURL
        self.headers = headers
        self.data = data
    }

    public var text: String {
        String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }
}

public protocol HTTPClient {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}

public struct URLSessionHTTPClient: HTTPClient {
    public init() {}

    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ResolveError.badResponse("响应不是 HTTP")
        }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            headers["\(key)"] = "\(value)"
        }
        return HTTPResponse(statusCode: http.statusCode, finalURL: http.url, headers: headers, data: data)
    }
}

enum HTTP {
    static func get(
        _ url: URL,
        headers: [String: String],
        timeout: TimeInterval = 25,
        client: any HTTPClient
    ) async throws -> HTTPResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        do {
            return try await client.send(request)
        } catch let error as ResolveError {
            throw error
        } catch {
            throw ResolveError.network(error.localizedDescription)
        }
    }

    static func post(
        _ url: URL,
        body: Data,
        headers: [String: String],
        timeout: TimeInterval = 25,
        client: any HTTPClient
    ) async throws -> HTTPResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = timeout
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        do {
            return try await client.send(request)
        } catch let error as ResolveError {
            throw error
        } catch {
            throw ResolveError.network(error.localizedDescription)
        }
    }
}
