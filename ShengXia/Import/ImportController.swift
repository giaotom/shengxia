import Foundation
import ShengXiaCore
import UIKit
import WebKit

struct ImportJob: Identifiable, Equatable {
    enum State: Equatable {
        case queued
        case working(String)
        case succeeded(String)
        case failed(String)
        case skipped(String)
    }

    var id = UUID()
    var input: String
    var state: State = .queued
    var progress: Double?

    var title: String {
        switch state {
        case .queued: return "等待"
        case .working(let text): return text
        case .succeeded(let text): return "已存入「\(text)」"
        case .failed(let text): return text
        case .skipped(let text): return text
        }
    }
}

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
            case .resolving, .openingDouyin, .downloading, .extracting, .saving: return true
            default: return false
            }
        }
    }

    @Published var linkText = ""
    @Published var phase: Phase = .idle
    @Published var jobs: [ImportJob] = []
    @Published var webRequest: WebCaptureRequest?
    @Published var webHint = "正在打开抖音页面，等待视频地址…"
    @Published var verificationVisible = false
    @Published var clipboardPrompt: String?

    private let library: LibraryStore
    private let player: PlayerModel
    private let settings: SettingsStore
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
    private var verifyHideTask: Task<Void, Never>?
    private var timeoutExtensions = 0
    private var userHidVerification = false
    private var drainTask: Task<Void, Never>?
    private var currentJobID: UUID?
    private var forced: Set<UUID> = []
    private var clipboardFull = ""

    init(library: LibraryStore, player: PlayerModel, settings: SettingsStore) {
        self.library = library
        self.player = player
        self.settings = settings
    }

    func pasteFromClipboard() {
        if let text = UIPasteboard.general.string {
            linkText = text
        } else {
            phase = .failed("剪贴板里没有文字")
        }
    }

    func considerClipboard() async {
        let board = UIPasteboard.general
        let patterns: Set<UIPasteboard.DetectionPattern> = await withCheckedContinuation { continuation in
            board.detectPatterns(for: [.probableWebURL]) { (result: Result<Set<UIPasteboard.DetectionPattern>, Error>) in
                continuation.resume(returning: (try? result.get()) ?? [])
            }
        }
        guard patterns.contains(.probableWebURL), let text = board.string else { return }
        guard BatchInput.containsSupportedLink(text) else { return }
        let token = String(board.changeCount)
        if token == UserDefaults.standard.string(forKey: "sx.clipboard.dismissed") { return }
        clipboardFull = text
        let line = text.replacingOccurrences(of: "\n", with: " ")
        clipboardPrompt = line.count > 80 ? String(line.prefix(80)) + "…" : line
    }

    func acceptClipboard() {
        let text = clipboardFull
        dismissClipboard()
        guard !text.isEmpty else { return }
        linkText = text
        enqueue(text)
    }

    func dismissClipboard() {
        UserDefaults.standard.set(String(UIPasteboard.general.changeCount), forKey: "sx.clipboard.dismissed")
        clipboardPrompt = nil
        clipboardFull = ""
    }

    func showVerification() {
        userHidVerification = false
        verificationVisible = true
        webHint = "请拖动滑块完成验证"
        report(webHint, progress: nil)
    }

    func hideVerification() {
        userHidVerification = true
        verificationVisible = false
    }

    func enqueue(_ text: String) {
        let parts = BatchInput.jobs(from: text)
        guard !parts.isEmpty else {
            phase = .failed(ResolveError.emptyInput.localizedDescription)
            return
        }
        for part in parts { jobs.append(ImportJob(input: part)) }
        kick()
    }

    func retry(_ id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].state = .queued
        jobs[index].progress = nil
        kick()
    }

    func force(_ id: UUID) {
        forced.insert(id)
        retry(id)
    }

    func remove(_ id: UUID) {
        if currentJobID == id { cancelCurrent() }
        jobs.removeAll { $0.id == id }
    }

    func clearFinished() {
        jobs.removeAll {
            switch $0.state {
            case .succeeded, .failed, .skipped: return true
            default: return false
            }
        }
    }

    func cancelCurrent() {
        downloader.cancel()
        debounce?.cancel()
        timeoutTask?.cancel()
        finishCapture(.failure(AppError.cancelled))
    }

    func cancelAll() {
        cancelCurrent()
        jobs.removeAll { if case .queued = $0.state { return true }; return false }
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
                report(webHint, progress: nil)
            }
        case "media":
            guard pageAccepts(href), let raw = dict["url"] as? String, let url = URL(string: raw) else {
                if !pageAccepts(href) { sawForeignVideo = true }
                return
            }
            mediaURLs.append(url)
            webHint = "已看到视频地址，正在确认…"
            report(webHint, progress: nil)
            scheduleFinish()
        case "detail":
            guard let text = dict["body"] as? String, !text.isEmpty else { return }
            if detailBodies.count < 4 { detailBodies.append(text) }
            webHint = "正在读取抖音返回的视频信息…"
            report(webHint, progress: nil)
            if let media = try? assembled() {
                finishCapture(.success(media))
            } else if (try? assembledImagePost()) == true {
                finishCapture(.failure(ResolveError.douyinImagePost))
            }
        case "verify":
            let active = (dict["active"] as? Bool) ?? ((dict["active"] as? NSNumber)?.boolValue ?? false)
            if active {
                verifyHideTask?.cancel()
                guard !userHidVerification else { return }
                verificationVisible = true
                webHint = "请拖动滑块完成验证"
                report(webHint, progress: nil)
            } else {
                verifyHideTask?.cancel()
                verifyHideTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    guard !Task.isCancelled else { return }
                    self.userHidVerification = false
                    self.verificationVisible = false
                    self.webHint = "验证已通过，继续提取…"
                    self.report(self.webHint, progress: nil)
                }
            }
        default:
            break
        }
    }

    private func kick() {
        if drainTask != nil { return }
        drainTask = Task { @MainActor in
            await self.drain()
            self.drainTask = nil
            if self.jobs.contains(where: { if case .queued = $0.state { return true }; return false }) {
                self.kick()
            }
        }
    }

    private func drain() async {
        while let index = jobs.firstIndex(where: { if case .queued = $0.state { return true }; return false }) {
            if Task.isCancelled { return }
            await run(jobs[index].id)
        }
    }

    private func run(_ id: UUID) async {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        let input = jobs[index].input
        currentJobID = id
        defer { currentJobID = nil }
        if !forced.contains(id), let key = MediaKey.key(forInput: input), let existing = library.track(sourceKey: key) {
            update(id) { $0.state = .skipped("已在资料库：「\(existing.title)」") }
            return
        }
        phase = .resolving
        report("正在解析", progress: nil)
        do {
            let step = try await SourceRouter(quality: settings.quality).resolve(input, client: client)
            let media: ResolvedMedia
            switch step {
            case .ready(let ready):
                media = ready
            case .webCapture(let request):
                media = try await capture(request)
            }
            let resolvedKey = MediaKey.key(forInput: media.pageURL)
            if !forced.contains(id), let resolvedKey, let existing = library.track(sourceKey: resolvedKey) {
                update(id) { $0.state = .skipped("已在资料库：「\(existing.title)」") }
                phase = .idle
                return
            }
            let saved = try await store(media)
            update(id) { $0.state = .succeeded(saved.title); $0.progress = 1 }
            phase = .success("已存入「\(saved.title)」")
            if player.current == nil {
                player.play(saved, in: [saved])
            } else {
                player.queueAppend(saved)
            }
        } catch AppError.cancelled {
            update(id) { $0.state = .failed("已取消"); $0.progress = nil }
            phase = .idle
        } catch {
            update(id) { $0.state = .failed(error.localizedDescription); $0.progress = nil }
            phase = .failed(error.localizedDescription)
        }
    }

    private func report(_ text: String, progress: Double?) {
        guard let currentJobID else { return }
        update(currentJobID) {
            $0.state = .working(text)
            $0.progress = progress
        }
    }

    private func update(_ id: UUID, _ body: (inout ImportJob) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        body(&jobs[index])
    }

    private func capture(_ request: WebCaptureRequest) async throws -> ResolvedMedia {
        captureDone = false
        detailBodies = []
        mediaURLs = []
        sawForeignVideo = false
        expectedID = request.awemeID
        webHint = "正在打开抖音页面，等待视频地址…"
        phase = .openingDouyin
        report(webHint, progress: nil)
        webRequest = request
        timeoutExtensions = 0
        userHidVerification = false
        verificationVisible = false
        return try await withCheckedThrowingContinuation { continuation in
            captureContinuation = continuation
            armTimeout()
        }
    }

    private func armTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 28_000_000_000)
            guard !Task.isCancelled else { return }
            if self.verificationVisible, self.timeoutExtensions < 6 {
                self.timeoutExtensions += 1
                self.armTimeout()
                return
            }
            self.finishWithWhatWeHave()
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
        verifyHideTask?.cancel()
        userHidVerification = false
        verificationVisible = false
        webRequest = nil
        captureContinuation?.resume(with: result)
        captureContinuation = nil
    }

    private func pageAccepts(_ href: String) -> Bool {
        guard let url = URL(string: href), let id = LinkParser.douyinID(in: url) else { return true }
        return id == expectedID
    }

    private func store(_ media: ResolvedMedia) async throws -> Track {
        phase = .downloading(nil)
        report("正在下载", progress: nil)
        let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        let temp = try await downloader.download(
            urls: media.stream.urls,
            headers: media.stream.headers,
            fileExtension: media.stream.fileExtension,
            cookies: cookies
        ) { [weak self] value in
            Task { @MainActor in
                self?.phase = .downloading(value)
                let title = value.map { "正在下载 \(Int(($0 * 100).rounded()))%" } ?? "正在下载"
                self?.report(title, progress: value)
            }
        }
        defer { try? FileManager.default.removeItem(at: temp) }

        var produced: URL?
        var destination: URL
        var label: String
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
                report("正在封装音轨", progress: 0)
                do {
                    try await AudioExporter.remuxToM4A(from: temp, to: destination) { [weak self] progress in
                        Task { @MainActor in
                            self?.phase = .extracting(progress)
                            self?.report("正在封装音轨 \(Int((progress * 100).rounded()))%", progress: progress)
                        }
                    }
                    if !(await AudioExporter.hasAudioTrack(destination)) { throw AppError.exportFailed }
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
                report("正在提取音轨", progress: 0)
                try await AudioExporter.extractM4A(from: temp, to: destination) { [weak self] progress in
                    Task { @MainActor in
                        self?.phase = .extracting(progress)
                        self?.report("正在提取音轨 \(Int((progress * 100).rounded()))%", progress: progress)
                    }
                }
                label = "M4A（AAC）"
            }
        } catch {
            if let produced { try? FileManager.default.removeItem(at: produced) }
            throw error
        }

        let polished = await polish(destination, label: &label)
        destination = polished.url
        phase = .saving
        report("正在写入资料库", progress: nil)
        let coverDestination = destination.deletingPathExtension().appendingPathExtension("jpg")
        var savedCover: URL?
        if let coverURL = media.coverURL, await downloadCover(coverURL, headers: media.stream.headers, to: coverDestination) {
            savedCover = coverDestination
        }
        let duration = await AudioExporter.duration(of: destination)
        return try await library.commit(
            audioURL: destination,
            coverURL: savedCover,
            title: DisplayTitle.shortened(media.title),
            artist: media.author,
            sourceName: media.sourceName,
            sourceURL: media.pageURL,
            formatLabel: label,
            duration: duration > 0 ? duration : (media.duration ?? 0),
            sourceKey: MediaKey.key(forInput: media.pageURL),
            processingNote: polished.note
        )
    }

    private func polish(_ url: URL, label: inout String) async -> (url: URL, note: String?) {
        guard settings.autoTrimSilence || settings.normalizeLoudness else { return (url, nil) }
        guard let analysis = await AudioWorkbench.analyze(url) else { return (url, nil) }
        let range = settings.autoTrimSilence
            ? AudioMath.silenceTrimRange(levelsDB: analysis.levelsDB, windowSeconds: analysis.windowSeconds)
            : nil
        let gain = settings.normalizeLoudness
            ? AudioMath.normalizationGain(loudnessDB: analysis.loudnessDB, peakDB: analysis.peakDB)
            : 0
        guard range != nil || gain != 0 else { return (url, nil) }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("m4a")
        do {
            phase = .extracting(0)
            report("正在整理音轨", progress: 0)
            try await AudioWorkbench.render(from: url, to: temp, range: range, gainDB: gain) { [weak self] value in
                Task { @MainActor in
                    self?.phase = .extracting(value)
                    self?.report("正在整理音轨 \(Int((value * 100).rounded()))%", progress: value)
                }
            }
        } catch {
            try? FileManager.default.removeItem(at: temp)
            return (url, nil)
        }
        let finalURL: URL
        if url.pathExtension.lowercased() == "m4a" {
            try? FileManager.default.removeItem(at: url)
            do {
                try FileManager.default.moveItem(at: temp, to: url)
            } catch {
                try? FileManager.default.removeItem(at: temp)
                return (url, nil)
            }
            finalURL = url
        } else {
            let m4a = url.deletingPathExtension().appendingPathExtension("m4a")
            try? FileManager.default.removeItem(at: m4a)
            do {
                try FileManager.default.moveItem(at: temp, to: m4a)
            } catch {
                return (url, nil)
            }
            try? FileManager.default.removeItem(at: url)
            finalURL = m4a
            label = "M4A（AAC）"
        }
        let trimmed = range.map { max(0, analysis.duration - ($0.upperBound - $0.lowerBound)) } ?? 0
        return (finalURL, AudioMath.processingNote(trimmed: trimmed, gainDB: gain))
    }

    private func downloadCover(_ url: URL, headers: [String: String], to destination: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        if request.value(forHTTPHeaderField: "User-Agent") == nil {
            request.setValue(BrowserIdentity.desktop, forHTTPHeaderField: "User-Agent")
        }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let image = UIImage(data: data),
              let jpeg = scale(image, maxSide: 800).jpegData(compressionQuality: 0.86) else { return false }
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
        return UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
