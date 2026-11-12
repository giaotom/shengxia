import SwiftUI

struct RootView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerModel
    @EnvironmentObject private var importer: ImportController
    @Environment(\.scenePhase) private var scenePhase
    @State private var showPlayer = false
    @State private var pendingDelete: Track?

    var body: some View {
        NavigationStack {
            ZStack {
                SX.paper.ignoresSafeArea()
                List {
                    Section {
                        header
                        PasteCard()
                        if let request = importer.webRequest {
                            DouyinCapturePanel(request: request)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                    if library.tracks.isEmpty {
                        Section {
                            EmptyLibrary()
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    } else {
                        Section {
                            HStack {
                                Text("资料库")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(SX.ink)
                                Spacer()
                                Text("\(library.tracks.count) 首")
                                    .font(.caption)
                                    .foregroundStyle(SX.brass)
                            }
                            ForEach(library.tracks) { track in
                                TrackRow(track: track) {
                                    player.play(track)
                                }
                                .swipeActions {
                                    Button("删除", role: .destructive) {
                                        pendingDelete = track
                                    }
                                }
                                .contextMenu {
                                    Button("删除", role: .destructive) {
                                        pendingDelete = track
                                    }
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .refreshable {
                    await library.refreshFromDisk()
                }
            }
            .navigationBarHidden(true)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if player.current != nil {
                    MiniPlayer(onOpen: { showPlayer = true })
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }
            }
            .sheet(isPresented: $showPlayer) {
                PlayerScreen(onDelete: { track in
                    showPlayer = false
                    pendingDelete = track
                })
                .presentationDragIndicator(.visible)
            }
            .confirmationDialog(
                "删除这首？",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("删除", role: .destructive) {
                    if let track = pendingDelete {
                        if player.current?.id == track.id { player.stop() }
                        library.delete(track)
                    }
                    pendingDelete = nil
                }
                Button("取消", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("音轨和封面会从这台 iPhone 的「文件」App 里去掉。")
            }
            .task {
                player.activateSession()
                await library.bootstrap()
                player.syncQueue(library.tracks)
            }
            .onChange(of: scenePhase) { phase in
                guard phase == .active else { return }
                Task {
                    await library.refreshFromDisk()
                    player.syncQueue(library.tracks)
                }
            }
            .onChange(of: library.tracks) { tracks in
                player.syncQueue(tracks)
            }
        }
        .tint(SX.cinnabar)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("声匣")
                .font(.system(size: 40, weight: .semibold, design: .serif))
                .foregroundStyle(SX.ink)
            Text("把公开视频的整条音轨留在这台手机上。")
                .font(.subheadline)
                .foregroundStyle(SX.ink.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12)
    }

}

struct EmptyLibrary: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "archivebox")
                .font(.system(size: 28))
                .foregroundStyle(SX.cinnabar)
            Text("匣子还是空的")
                .font(.title3.weight(.semibold))
                .foregroundStyle(SX.ink)
            Text("粘贴哔哩哔哩或抖音的视频链接。声匣会把整条音轨存进本机，不会做人声分离，也不会去碰付费音乐库。")
                .font(.subheadline)
                .foregroundStyle(SX.ink.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            Text("也可以在「文件」App 里打开「声匣 / Music」，放进 mp3、m4a 或 flac。")
                .font(.footnote)
                .foregroundStyle(SX.brass)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SX.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
