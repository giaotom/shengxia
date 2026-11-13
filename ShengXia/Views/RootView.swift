import ShengXiaCore
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerModel
    @EnvironmentObject private var importer: ImportController
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var shell: ShellState
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if #available(iOS 26, *) {
                GlassTabs()
            } else {
                FallbackTabs()
            }
        }
        .tint(SX.cinnabar)
        .preferredColorScheme(settings.appearance.scheme)
        .fullScreenCover(isPresented: $shell.showPlayer) {
            PlayerScreen()
                .environmentObject(library)
                .environmentObject(player)
                .environmentObject(settings)
                .environmentObject(shell)
                .environmentObject(importer)
        }
        .sheet(isPresented: $shell.showSettings) {
            SettingsView()
                .environmentObject(library)
                .environmentObject(settings)
                .environmentObject(shell)
        }
        .overlay(alignment: .top) { clipboardBanner }
        .alert(
            "有一点问题",
            isPresented: Binding(get: { library.lastError != nil }, set: { if !$0 { library.lastError = nil } })
        ) {
            Button("好") { library.lastError = nil }
        } message: {
            Text(library.lastError ?? "")
        }
        .task {
            player.activateSession()
            await library.bootstrap()
            player.noteLibrary(library.tracks)
            await importer.considerClipboard()
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            Task {
                await library.refreshFromDisk()
                player.noteLibrary(library.tracks)
                await importer.considerClipboard()
            }
        }
        .onChange(of: library.tracks) { tracks in
            player.noteLibrary(tracks)
        }
        .onOpenURL { url in
            guard let text = AppLink.extractText(from: url) else { return }
            shell.tab = .extract
            importer.enqueue(text)
        }
    }

    @ViewBuilder
    private var clipboardBanner: some View {
        if let prompt = importer.clipboardPrompt {
            VStack(alignment: .leading, spacing: 10) {
                Text("要提取这条吗？")
                    .font(.headline)
                    .foregroundStyle(SX.ink)
                Text(prompt)
                    .font(.subheadline)
                    .foregroundStyle(SX.ink.opacity(0.75))
                    .lineLimit(2)
                HStack(spacing: 10) {
                    Button("先不了") { importer.dismissClipboard() }
                        .sxGlassButton()
                    Button("提取") {
                        importer.acceptClipboard()
                        shell.tab = .extract
                    }
                    .sxGlassButton(prominent: true)
                }
                .controlSize(.regular)
            }
            .padding(16)
            .sxGlass(cornerRadius: 24)
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }
}

@available(iOS 26, *)
private struct GlassTabs: View {
    @EnvironmentObject private var shell: ShellState
    @EnvironmentObject private var player: PlayerModel

    var body: some View {
        TabView(selection: $shell.tab) {
            Tab("提取", systemImage: AppTab.extract.symbol, value: AppTab.extract) {
                ExtractView()
            }
            Tab("资料库", systemImage: AppTab.library.symbol, value: AppTab.library) {
                LibraryView()
            }
            Tab("歌单", systemImage: AppTab.playlists.symbol, value: AppTab.playlists) {
                PlaylistsView()
            }
        }
        .tabViewBottomAccessory {
            if player.current != nil {
                MiniPlayerBar(showsGlass: false)
            }
        }
    }
}

private struct FallbackTabs: View {
    @EnvironmentObject private var shell: ShellState
    @EnvironmentObject private var player: PlayerModel

    var body: some View {
        ZStack {
            SXBackground()
            switch shell.tab {
            case .extract: ExtractView()
            case .library: LibraryView()
            case .playlists: PlaylistsView()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 8) {
            VStack(spacing: 8) {
                if player.current != nil {
                    MiniPlayerBar(showsGlass: true)
                }
                FallbackTabBar()
            }
            .padding(.horizontal, 12)
        }
    }
}

private struct FallbackTabBar: View {
    @EnvironmentObject private var shell: ShellState

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                Button { shell.tab = tab } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.symbol)
                            .font(.body.weight(.semibold))
                        Text(tab.title)
                            .font(.caption2.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundStyle(shell.tab == tab ? SX.cinnabar : SX.ink.opacity(0.62))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
            }
        }
        .padding(.horizontal, 6)
        .sxGlass(cornerRadius: 28)
    }
}
