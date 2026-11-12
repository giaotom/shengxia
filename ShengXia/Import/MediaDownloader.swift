import Foundation
import ShengXiaCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class MediaDownloader: NSObject, URLSessionDownloadDelegate, URLSessionTaskDelegate {
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60 * 20
        config.waitsForConnectivity = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private var continuation: CheckedContinuation<URL, Error>?
    private var destination: URL?
    private var headers: [String: String] = [:]
    private var progressHandler: ((Double?) -> Void)?
    private var finishedURL: URL?
    private var failure: Error?
    private var resumed = false

    func download(
        urls: [URL],
        headers: [String: String],
        fileExtension: String,
        cookies: [HTTPCookie] = [],
        onProgress: @escaping (Double?) -> Void
    ) async throws -> URL {
        var lastError: Error = AppError.downloadFailed("没有可下载的地址")
        for url in urls {
            do {
                let file = try await downloadOne(
                    url,
                    headers: headers,
                    fileExtension: fileExtension,
                    cookies: cookies,
                    onProgress: onProgress
                )
                let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                if MediaSniffer.looksLikeMedia(file: file), size > 1024 {
                    return file
                }
                try? FileManager.default.removeItem(at: file)
                lastError = AppError.notMedia
            } catch let error as AppError where error.localizedDescription == AppError.cancelled.localizedDescription {
                throw AppError.cancelled
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    func cancel() {
        session.getAllTasks { tasks in
            tasks.forEach { $0.cancel() }
        }
    }

    private func downloadOne(
        _ url: URL,
        headers: [String: String],
        fileExtension: String,
        cookies: [HTTPCookie],
        onProgress: @escaping (Double?) -> Void
    ) async throws -> URL {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)
        self.destination = destination
        self.headers = headers
        self.progressHandler = onProgress
        self.finishedURL = nil
        self.failure = nil
        self.resumed = false
        if let storage = session.configuration.httpCookieStorage {
            storage.setCookies(cookies, for: url, mainDocumentURL: URL(string: "https://www.douyin.com/"))
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let cookieHeader = cookies
            .filter { cookieMatches($0, host: url.host ?? "") }
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
        if !cookieHeader.isEmpty {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.session.downloadTask(with: request).resume()
        }
    }

    private func cookieMatches(_ cookie: HTTPCookie, host: String) -> Bool {
        let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return host == domain || host.hasSuffix("." + domain)
    }

    private func resume(with result: Result<URL, Error>) {
        guard !resumed, let continuation else { return }
        resumed = true
        self.continuation = nil
        continuation.resume(with: result)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let value: Double? = totalBytesExpectedToWrite > 0
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            : nil
        let handler = progressHandler
        DispatchQueue.main.async { handler?(value) }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let code = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(code), let destination else {
            failure = AppError.downloadFailed("下载失败（HTTP \(code)）")
            return
        }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            finishedURL = destination
        } catch {
            failure = AppError.saveFailed(error.localizedDescription)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        var request = request
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            if (error as? URLError)?.code == .cancelled {
                resume(with: .failure(AppError.cancelled))
            } else {
                resume(with: .failure(AppError.downloadFailed("网络出错：\(error.localizedDescription)")))
            }
            return
        }
        if let failure {
            resume(with: .failure(failure))
        } else if let finishedURL {
            resume(with: .success(finishedURL))
        } else {
            resume(with: .failure(AppError.downloadFailed("下载没有完成")))
        }
    }
}
