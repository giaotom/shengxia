import ShengXiaCore
import SwiftUI
import WebKit

struct PluginsView: View {
    @EnvironmentObject private var plugins: PluginCenter
    @EnvironmentObject private var shell: ShellState
    @State private var address = ""
    @State private var query = ""
    @State private var selected = ""
    @State private var playlistID = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("插件由原作者发布，声匣只负责下载和运行。不会把插件打进安装包，也不绕过会员、付费墙或 DRM。")
                    .font(.footnote)
                    .foregroundStyle(SX.ink.opacity(0.7))
                installCard
                if !plugins.records.isEmpty {
                    searchCard
                    ForEach(plugins.records) { record in
                        installedCard(record)
                    }
                }
                Text("核对过能用的来源")
                    .font(.headline)
                    .foregroundStyle(SX.ink)
                ForEach(PluginCatalog.verified) { item in
                    catalogCard(item)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .background(SXBackground())
        .navigationTitle("插件")
        .navigationBarTitleDisplayMode(.inline)
        .alert("登录提示", isPresented: Binding(
            get: { plugins.prompt != nil },
            set: { if !$0 { plugins.prompt = nil } }
        )) {
            Button("好") { plugins.prompt = nil }
        } message: {
            Text(plugins.prompt ?? "")
        }
        .sheet(item: $plugins.webJob) { job in
            PluginWebSignInSheet(job: job) { result in
                plugins.finishWeb(result)
            }
        }
    }

    private var installCard: some View {
        card {
            Text("安装")
                .font(.headline)
                .foregroundStyle(SX.ink)
            TextField("GitHub 仓库、zip 或 .js 链接", text: $address)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(SX.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Button(plugins.busy == nil ? "安装" : (plugins.busy ?? "安装")) {
                let text = address
                Task { await plugins.install(from: text) }
            }
            .sxGlassButton(prominent: true)
            .disabled(plugins.busy != nil)
            if let notice = plugins.notice {
                Text(notice)
                    .font(.footnote)
                    .foregroundStyle(SX.ink.opacity(0.75))
            }
        }
    }

    private var searchCard: some View {
        card {
            Text("搜索已启用的插件")
                .font(.headline)
                .foregroundStyle(SX.ink)
            TextField("歌名、歌手或电台", text: $query)
                .textInputAutocapitalization(.never)
                .padding(12)
                .background(SX.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Button("搜索") {
                let text = query
                Task { await plugins.search(query: text) }
            }
            .sxGlassButton()
            .disabled(plugins.busy != nil)
            if !plugins.pages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(plugins.records.filter(\.enabled)) { record in
                            Button(record.name) { selected = record.id }
                                .font(.footnote.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(currentID == record.id ? SX.ink : Color.white, in: Capsule())
                                .foregroundStyle(currentID == record.id ? Color.white : SX.ink)
                                .overlay(Capsule().strokeBorder(SX.ink.opacity(0.2), lineWidth: 1))
                        }
                    }
                }
                resultList
            }
        }
    }

    @ViewBuilder
    private var resultList: some View {
        let id = currentID
        if let page = plugins.pages[id] {
            if let message = page.message {
                Text(message).font(.footnote).foregroundStyle(SX.ink.opacity(0.7))
            }
            ForEach(page.tracks) { song in
                VStack(alignment: .leading, spacing: 6) {
                    Text(song.name).font(.subheadline.weight(.semibold)).foregroundStyle(SX.ink).lineLimit(2)
                    if !song.artist.isEmpty {
                        Text(song.artist).font(.caption).foregroundStyle(SX.brass).lineLimit(1)
                    }
                    HStack(spacing: 16) {
                        Button("播放") { play(song, id: id) }
                        Button("保存") { save(song, id: id) }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SX.cinnabar)
                }
                .padding(.vertical, 6)
            }
            if let record = plugins.records.first(where: { $0.id == id }), !page.playlists.isEmpty {
                ForEach(page.playlists) { playlist in
                    Button("导入歌单 \(playlist.name)") {
                        Task { await plugins.importPlaylist(id: playlist.id, on: record) }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SX.ink)
                }
            }
        }
    }

    private var currentID: String {
        if plugins.records.contains(where: { $0.id == selected && $0.enabled }) { return selected }
        return plugins.records.first(where: \.enabled)?.id ?? ""
    }

    private func installedCard(_ record: PluginRecord) -> some View {
        card {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.name).font(.headline).foregroundStyle(SX.ink)
                    Text("\(record.author) · \(record.version)")
                        .font(.caption)
                        .foregroundStyle(SX.brass)
                }
                Spacer()
                Toggle("启用", isOn: Binding(
                    get: { record.enabled },
                    set: { plugins.setEnabled(record.id, $0) }
                ))
                .labelsHidden()
            }
            if !record.summary.isEmpty {
                Text(record.summary).font(.footnote).foregroundStyle(SX.ink.opacity(0.72))
            }
            Text(record.license).font(.caption2).foregroundStyle(SX.ink.opacity(0.55))
            if let url = URL(string: record.repository.contains("/") ? "https://github.com/\(record.repository)" : record.source) {
                Link("原仓库", destination: url).font(.footnote.weight(.semibold))
            }
            ForEach(record.settings) { field in
                TextField(field.label, text: Binding(
                    get: { record.values[field.key] ?? "" },
                    set: { plugins.setValue(record.id, key: field.key, value: $0) }
                ))
                .textInputAutocapitalization(.never)
                .padding(10)
                .background(SX.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                if !field.help.isEmpty {
                    Text(field.help).font(.caption2).foregroundStyle(SX.ink.opacity(0.6))
                }
            }
            HStack(spacing: 16) {
                Button("首页") { Task { await plugins.playHome(record) } }
                Button("检查更新") { Task { await plugins.update(record) } }
                Button("卸掉") { plugins.uninstall(record.id) }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(SX.ink)
            TextField("歌单编号，导入到声匣歌单", text: $playlistID)
                .textInputAutocapitalization(.never)
                .font(.footnote)
            Button("导入这个歌单") {
                Task { await plugins.importPlaylist(id: playlistID, on: record) }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(SX.cinnabar)
        }
    }

    private func catalogCard(_ item: PluginCatalogItem) -> some View {
        card {
            Text(item.name).font(.headline).foregroundStyle(SX.ink)
            Text(item.note).font(.footnote).foregroundStyle(SX.ink.opacity(0.72))
            HStack {
                Link(item.repo, destination: URL(string: item.source)!).font(.caption)
                Spacer()
                Button("安装") {
                    Task { await plugins.install(from: item.source) }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SX.cinnabar)
                .disabled(plugins.busy != nil)
            }
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .environment(\.colorScheme, .light)
    }

    private func play(_ song: PluginSong, id: String) {
        guard let record = plugins.records.first(where: { $0.id == id }) else { return }
        Task {
            do {
                try await plugins.play(song, on: record)
                shell.showSettings = false
                shell.showPlayer = true
            } catch {
                plugins.notice = error.localizedDescription
            }
        }
    }

    private func save(_ song: PluginSong, id: String) {
        guard let record = plugins.records.first(where: { $0.id == id }) else { return }
        Task { await plugins.save(song, on: record) }
    }
}

private struct PluginWebSignInSheet: View {
    let job: WebJob
    var finish: (Result<String, Error>) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PluginWebView(request: job.request) { cookie in
                finish(.success(cookie))
                dismiss()
            }
            .ignoresSafeArea(edges: .bottom)
            .onDisappear { job.finish(.failure(PluginWebError.cancelled)) }
            .navigationTitle("网页登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        finish(.failure(PluginWebError.cancelled))
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct PluginWebView: UIViewRepresentable {
    var request: PluginWebSignIn
    var onCookie: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(request: request, onCookie: onCookie) }

    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        web.navigationDelegate = context.coordinator
        if let agent = request.userAgent, !agent.isEmpty { web.customUserAgent = agent }
        if let url = URL(string: request.url) { web.load(URLRequest(url: url)) }
        context.coordinator.watch(web)
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let request: PluginWebSignIn
        let onCookie: (String) -> Void
        private var sent = false
        private var timer: Timer?

        init(request: PluginWebSignIn, onCookie: @escaping (String) -> Void) {
            self.request = request
            self.onCookie = onCookie
        }

        func watch(_ web: WKWebView) {
            timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self, weak web] _ in
                guard let self, let web else { return }
                self.look(web)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { look(webView) }

        private func look(_ web: WKWebView) {
            guard !sent else { return }
            let host = URL(string: request.cookiesOf)?.host ?? URL(string: request.url)?.host ?? ""
            web.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self, !self.sent else { return }
                let matched = cookies.filter { cookie in
                    let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
                    return host == domain || host.hasSuffix("." + domain) || domain.hasSuffix(host)
                }
                let names = Set(matched.map(\.name))
                guard !self.request.until.isEmpty, self.request.until.allSatisfy(names.contains) else { return }
                self.sent = true
                let header = matched.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
                DispatchQueue.main.async { self.onCookie(header) }
            }
        }
    }
}

private enum PluginWebError: LocalizedError {
    case cancelled
    var errorDescription: String? { "登录取消了" }
}
