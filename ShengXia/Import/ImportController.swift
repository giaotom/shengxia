import Foundation
import ShengXiaCore
import UIKit
import WebKit

@MainActor
final class ImportController: ObservableObject {
    enum Phase: Equatable {
        case idle
        case resolving
        case openingDouyin
        case downloading(Double?)
        case extracting(Double)
        case saving
        case success(String)
        case failed(String)

        var isBusy: Bool {
            switch self {
            case .resolving, .openingDouyin, .downloading, .extracting, .saving:
                return true
            default:
                return false
            }
        }
    }

    @Published var linkText = ""
    @Published var phase: Phase = .idle
    @Published var webRequest: WebCaptureRequest?
    @Published var webHint = "正在打开抖音页面，等待视频地址…"

    private let router = SourceRouter()
    private let client = URLSessionHTTPClient()
    private let downloader = MediaDownloader()
    private var captureContinuation: CheckedContinuation<ResolvedMedia, Error>?
    private var captureDone = false
    private var detailBodies: [String] = []
    private var mediaURLs: [URL] = []
    private var sawForeignVideo = false
    private var expectedID = ""
    private var debounce: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    func pasteFromClipboard() {
        if let text = UIPasteboard.general.string {
            linkText = text
        } else {
            phase = .failed("剪贴板里没有文字")
        }
    }

    func cancel() {
        downloader.cancel()
        debounce?.cancel()
        timeoutTask?.cancel()
        finishCapture(.failure(AppError.cancelled))
        phase = .idle
        webHint = ""
    }

    @discardableResult
    func start(library: LibraryStore, player: PlayerModel) async -> Track? {
        guard !phase.isBusy else { return nil }
        let text = linkText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            phase = .failed(ResolveError.emptyInput.localizedDescription)
            return nil
        }
        phase = .resolving
        do {
            let step = try await router.resolve(text, client: client)
            let media: ResolvedMedia
            switch step {
            case .ready(let ready):
                media = ready
            case .webCapture(let request):
                media = try await capture(request)
            }
            let saved = try await store(media, library: library)
            phase = .success("已存入「\(saved.title)」· \(saved.formatLabel)")
            player.play(saved)
            return saved
        } catch AppError.cancelled {
            phase = .idle
            return nil
        } catch {
            phase = .failed(error.localizedDescription)
            return nil
        }
    }

    func receiveWebMessage(_ body: Any) {
        guard !captureDone, let dict = body as? [String: Any] else { return }
        let kind = dict["kind"] as? String ?? ""
        let href = dict["href"] as? String ?? ""
        switch kind {
        case "page":
            if !pageAccepts(href) { sawForeignVideo = true }
            if let title = dict["title"] as? String, !title.isEmpty {
                webHint = "页面：\(title)"
            }
        case "media":
            guard pageAccepts(href),
                  let raw = dict["url"] as? String,
                  let url = URL(string: raw) else {
                if !pageAccepts(href) { sawForeignVideo = true }
                return
            }
            mediaURLs.append(url)
            webHint = "已看到视频地址，正在确认…"
            scheduleFinish()
        case "detail":
            guard let text = dict["body"] as? String, !text.isEmpty else { return }
            if detailBodies.count < 4 { detailBodies.append(text) }
            webHint = "正在读取抖音返回的视频信息…"
            if let media = try? assembled() {
                finishCapture(.success(media))
            } else if (try? assembledImagePost()) == true {
                finishCapture(.failure(ResolveError.douyinImagePost))
            }
        default:
            break
        }
    }

    private func capture(_ request: WebCaptureRequest) async throws -> ResolvedMedia {
        captureDone = false
        detailBodies = []
        mediaURLs = []
        sawForeignVideo = false
        expectedID = request.awemeID
        webHint = "正在打开抖音页面，等待视频地址…"
        phase = .openingDouyin
        webRequest = request
        return try await withCheckedThrowingContinuation { continuation in
            captureContinuation = continuation
            timeoutTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 28_000_000_000)
                guard !Task.isCancelled else { return }
                self.finishWithWhatWeHave()
            }
        }
    }

    private func scheduleFinish() {
        debounce?.cancel()
        debounce = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            self.finishWithWhatWeHave()
        }
    }

    private func finishWithWhatWeHave() {
        guard !captureDone else { return }
        if let media = try? assembled() {
            finishCapture(.success(media))
            return
        }
        if (try? assembledImagePost()) == true {
            finishCapture(.failure(ResolveError.douyinImagePost))
            return
        }
        if sawForeignVideo && mediaURLs.isEmpty {
            finishCapture(.failure(ResolveError.douyinWrongVideo))
        } else {
            finishCapture(.failure(ResolveError.douyinResolveFailed))
        }
    }

    private func assembled() throws -> ResolvedMedia {
        guard let request = webRequest else { throw ResolveError.douyinResolveFailed }
        return try DouyinCaptureAssembler.assemble(
            detailBodies: detailBodies,
            mediaURLs: mediaURLs,
            expectedID: expectedID,
            pageURL: request.pageURL.absoluteString
        )
    }

    private func assembledImagePost() throws -> Bool {
        do {
            _ = try assembled()
            return false
        } catch let error as ResolveError where error == .douyinImagePost {
            return true
        } catch {
            return false
        }
    }

    private func finishCapture(_ result: Result<ResolvedMedia, Error>) {
        guard !captureDone else { return }
        captureDone = true
        debounce?.cancel()
        timeoutTask?.cancel()
        webRequest = nil
        captureContinuation?.resume(with: result)
        captureContinuation = nil
    }

    private func pageAccepts(_ href: String) -> Bool {
        guard let url = URL(string: href), let id = LinkParser.douyinID(in: url) else { return true }
        return id == expectedID
    }

    private func store(_ media: ResolvedMedia, library: LibraryStore) async throws -> Track {
        phase = .downloading(nil)
        let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        let temp = try await downloader.download(
            urls: media.stream.urls,
            headers: media.stream.headers,
            fileExtension: media.stream.fileExtension,
            cookies: cookies
        ) { [weak self] value in
            Task { @MainActor in self?.phase = .downloading(value) }
        }
        defer { try? FileManager.default.removeItem(at: temp) }

        var produced: URL?
        let destination: URL
        let label: String
        do {
            if media.stream.fileExtension.lowercased() == "flac" {
                guard await AudioExporter.hasAudioTrack(temp) else { throw AppError.noAudioTrack }
                destination = try library.reserveAudioFile(title: media.title, extension: "flac")
                produced = destination
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.copyItem(at: temp, to: destination)
                label = "FLAC"
            } else if media.stream.kind == .audio {
                destination = try library.reserveAudioFile(title: media.title, extension: "m4a")
                produced = destination
                phase = .extracting(0)
                do {
                    try await AudioExporter.remuxToM4A(from: temp, to: destination) { [weak self] progress in
                        Task { @MainActor in self?.phase = .extracting(progress) }
                    }
                    if !(await AudioExporter.hasAudioTrack(destination)) {
                        throw AppError.exportFailed
                    }
                } catch let error as AppError where error.localizedDescription == AppError.cancelled.localizedDescription {
                    throw AppError.cancelled
                } catch {
                    guard await AudioExporter.hasAudioTrack(temp) else { throw AppError.noAudioTrack }
                    try? FileManager.default.removeItem(at: destination)
                    try FileManager.default.copyItem(at: temp, to: destination)
                }
                label = media.stream.formatLabel
            } else {
                destination = try library.reserveAudioFile(title: media.title, extension: "m4a")
                produced = destination
                phase = .extracting(0)
                try await AudioExporter.extractM4A(from: temp, to: destination) { [weak self] progress in
                    Task { @MainActor in self?.phase = .extracting(progress) }
                }
                label = "M4A（AAC）"
            }
        } catch {
            if let produced {
                try? FileManager.default.removeItem(at: produced)
            }
            throw error
        }

        phase = .saving
        let coverDestination = destination.deletingPathExtension().appendingPathExtension("jpg")
        var savedCover: URL?
        if let coverURL = media.coverURL {
            if await downloadCover(coverURL, headers: media.stream.headers, to: coverDestination) {
                savedCover = coverDestination
            }
        }
        let duration = await AudioExporter.duration(of: destination)
        return try await library.commit(
            audioURL: destination,
            coverURL: savedCover,
            title: media.title,
            artist: media.author,
            sourceName: media.sourceName,
            sourceURL: media.pageURL,
            formatLabel: label,
            duration: duration > 0 ? duration : (media.duration ?? 0)
        )
    }

    private func downloadCover(_ url: URL, headers: [String: String], to destination: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if request.value(forHTTPHeaderField: "User-Agent") == nil {
            request.setValue(BrowserIdentity.desktop, forHTTPHeaderField: "User-Agent")
        }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let image = UIImage(data: data) else { return false }
        let scaled = scale(image, maxSide: 800)
        guard let jpeg = scaled.jpegData(compressionQuality: 0.86) else { return false }
        do {
            try jpeg.write(to: destination, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private func scale(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxSide, longest > 0 else { return image }
        let ratio = maxSide / longest
        let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
