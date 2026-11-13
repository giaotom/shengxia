import ShengXiaCore
import SwiftUI
import UIKit
import WebKit

struct DouyinWebRepresentable: UIViewRepresentable {
    @EnvironmentObject var importer: ImportController
    let request: WebCaptureRequest
    var verificationVisible: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(importer: importer)
    }

    func makeUIView(context: Context) -> DouyinWebContainer {
        let container = DouyinWebContainer()
        let webView = context.coordinator.makeWebView(request: request)
        container.attach(webView)
        context.coordinator.container = container
        context.coordinator.load(request.pageURL, in: webView)
        return container
    }

    func updateUIView(_ container: DouyinWebContainer, context: Context) {
        context.coordinator.importer = importer
        context.coordinator.container = container
        if let webView = context.coordinator.webView {
            webView.customUserAgent = request.userAgent
            context.coordinator.load(request.pageURL, in: webView)
            context.coordinator.enableZoom(webView)
        }
        context.coordinator.setSheet(visible: verificationVisible)
    }

    static func dismantleUIView(_ container: DouyinWebContainer, coordinator: Coordinator) {
        coordinator.teardown()
        container.webView?.stopLoading()
    }
}

final class DouyinWebContainer: UIView {
    weak var webView: WKWebView?

    func attach(_ webView: WKWebView) {
        self.webView = webView
        webView.translatesAutoresizingMaskIntoConstraints = true
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        if webView.superview !== self {
            webView.removeFromSuperview()
            addSubview(webView)
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let webView, webView.superview === self else { return }
        webView.frame = bounds
    }
}

extension DouyinWebRepresentable {
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, UISheetPresentationControllerDelegate {
        var importer: ImportController
        weak var container: DouyinWebContainer?
        private(set) var webView: WKWebView?
        private var sheet: DouyinVerifySheetController?
        private var loadedURL: URL?
        private var tornDown = false
        private var revealTicket = 0

        init(importer: ImportController) {
            self.importer = importer
        }

        func makeWebView(request: WebCaptureRequest) -> WKWebView {
            let config = WKWebViewConfiguration()
            config.allowsInlineMediaPlayback = true
            config.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypes(rawValue: 0)
            let script = WKUserScript(
                source: DouyinPageScript.source,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
            config.userContentController.addUserScript(script)
            config.userContentController.add(self, name: "shengxia")
            let webView = WKWebView(frame: .zero, configuration: config)
            webView.navigationDelegate = self
            webView.customUserAgent = request.userAgent
            webView.isOpaque = true
            webView.backgroundColor = .systemBackground
            webView.scrollView.backgroundColor = .systemBackground
            enableZoom(webView)
            self.webView = webView
            return webView
        }

        func enableZoom(_ webView: WKWebView) {
            let scroll = webView.scrollView
            scroll.isScrollEnabled = true
            scroll.bouncesZoom = true
            scroll.minimumZoomScale = 0.5
            scroll.maximumZoomScale = 5
            scroll.pinchGestureRecognizer?.isEnabled = true
        }

        func load(_ url: URL, in webView: WKWebView) {
            guard loadedURL != url else { return }
            loadedURL = url
            webView.load(URLRequest(url: url))
        }

        func setSheet(visible: Bool) {
            if visible {
                guard sheet == nil, !tornDown else { return }
                DispatchQueue.main.async { [weak self] in
                    self?.presentSheetIfNeeded()
                }
            } else {
                dismissSheet(animated: true)
            }
        }

        func teardown() {
            tornDown = true
            revealTicket += 1
            dismissSheet(animated: false)
            webView?.stopLoading()
            webView?.configuration.userContentController.removeScriptMessageHandler(forName: "shengxia")
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            let body = message.body
            Task { @MainActor in
                importer.receiveWebMessage(body)
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            let scheme = navigationAction.request.url?.scheme?.lowercased() ?? ""
            if scheme.isEmpty || scheme == "http" || scheme == "https" || scheme == "about" {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            enableZoom(webView)
            guard importer.verificationVisible else { return }
            revealCaptcha(in: webView)
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            guard let sheet else { return }
            self.sheet = nil
            sheet.releaseWebView()
            if let webView {
                container?.attach(webView)
            }
            importer.hideVerification()
        }

        private func presentSheetIfNeeded() {
            guard !tornDown, sheet == nil, importer.verificationVisible, let webView else { return }
            guard let presenter = topPresenter() else { return }
            let sheet = DouyinVerifySheetController(webView: webView) { [weak self] in
                self?.importer.hideVerification()
            }
            sheet.modalPresentationStyle = .pageSheet
            sheet.isModalInPresentation = true
            if let presentation = sheet.sheetPresentationController {
                presentation.detents = [.large()]
                presentation.prefersGrabberVisible = true
                presentation.prefersScrollingExpandsWhenScrolledToEdge = false
                presentation.preferredCornerRadius = 28
                presentation.delegate = self
            }
            self.sheet = sheet
            presenter.present(sheet, animated: true)
            revealCaptcha(in: webView)
        }

        private func dismissSheet(animated: Bool) {
            guard let sheet else { return }
            self.sheet = nil
            sheet.releaseWebView()
            if let webView {
                container?.attach(webView)
            }
            sheet.dismiss(animated: animated)
        }

        private func revealCaptcha(in webView: WKWebView) {
            revealTicket += 1
            let ticket = revealTicket
            enableZoom(webView)
            webView.evaluateJavaScript(DouyinPageScript.revealInvocation, completionHandler: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self, weak webView] in
                guard let self, let webView, ticket == self.revealTicket, self.sheet != nil else { return }
                webView.evaluateJavaScript(DouyinPageScript.revealInvocation, completionHandler: nil)
            }
        }

        private func topPresenter() -> UIViewController? {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let key = scenes.flatMap(\.windows).first { $0.isKeyWindow }?.rootViewController
            var top = key
            while let presented = top?.presentedViewController, !presented.isBeingDismissed {
                top = presented
            }
            return top
        }
    }
}

final class DouyinVerifySheetController: UIViewController {
    private let webView: WKWebView
    private let onClose: () -> Void
    private let header: UIHostingController<DouyinVerifyHeader>
    private var webConstraints: [NSLayoutConstraint] = []

    init(webView: WKWebView, onClose: @escaping () -> Void) {
        self.webView = webView
        self.onClose = onClose
        let host = UIHostingController(rootView: DouyinVerifyHeader(onClose: onClose))
        host.sizingOptions = .intrinsicContentSize
        if #available(iOS 16.4, *) {
            host.safeAreaRegions = []
        }
        header = host
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        header.view.backgroundColor = .clear
        addChild(header)
        view.addSubview(header.view)
        header.didMove(toParent: self)
        header.view.translatesAutoresizingMaskIntoConstraints = false
        header.view.setContentHuggingPriority(.required, for: .vertical)
        header.view.setContentCompressionResistancePriority(.required, for: .vertical)

        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(webView, at: 0)
        webConstraints = [
            header.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            header.view.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            header.view.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            header.view.heightAnchor.constraint(greaterThanOrEqualToConstant: 64),
            webView.topAnchor.constraint(equalTo: header.view.bottomAnchor, constant: 8),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ]
        NSLayoutConstraint.activate(webConstraints)
    }

    func releaseWebView() {
        NSLayoutConstraint.deactivate(webConstraints)
        webConstraints = []
        guard webView.superview === view else { return }
        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = true
    }
}

struct DouyinVerifyHeader: View {
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("完成验证")
                    .font(.headline)
                    .foregroundStyle(SX.ink)
                Text("滑块已放大。可以双指再放大，然后拖到缺口。")
                    .font(.caption)
                    .foregroundStyle(SX.ink.opacity(0.68))
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .modifier(CircleGlass())
            .accessibilityLabel("关闭验证")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .sxGlass(cornerRadius: 22)
    }
}
