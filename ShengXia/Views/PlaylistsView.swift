import ShengXiaCore
import SwiftUI

struct PlaylistsView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerModel
    @State private var creating = false
    @State private var name = ""
    @State private var pendingDelete: [UUID] = []

    var body: some View {
        NavigationStack {
            List {
                if library.playlists.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("还没有歌单")
                                .font(.title3.weight(.semibold))
                            Text("把资料库里的音轨收成一张单。点右上角的加号。")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(library.playlists) { playlist in
                        NavigationLink {
                            PlaylistDetail(playlistID: playlist.id)
                        } label: {
                            HStack(spacing: 12) {
                                CoverThumb(track: library.tracks(in: playlist).first, side: 52, radius: 10)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(playlist.name).font(.body.weight(.semibold)).foregroundStyle(SX.ink)
                                    Text("\(library.tracks(in: playlist).count) 首")
                                        .font(.caption)
                                        .foregroundStyle(SX.brass)
                                }
                            }
                        }
                    }
                    .onDelete { offsets in
                        pendingDelete = offsets.map { library.playlists[$0].id }
                    }
                    .onMove { library.movePlaylists(from: $0, to: $1) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(SXBackground())
            .navigationTitle("歌单")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 10) {
                        Button { creating = true } label: { Image(systemName: "plus") }
                            .accessibilityLabel("新建歌单")
                        SettingsButton()
                    }
                }
            }
            .alert("新歌单", isPresented: $creating) {
                TextField("名称", text: $name)
                Button("创建") {
                    _ = library.createPlaylist(name: name)
                    name = ""
                }
                Button("取消", role: .cancel) { name = "" }
            }
            .confirmationDialog("删除这个歌单？", isPresented: Binding(get: { !pendingDelete.isEmpty }, set: { if !$0 { pendingDelete = [] } }), titleVisibility: .visible) {
                Button("删除歌单", role: .destructive) {
                    for id in pendingDelete { library.deletePlaylist(id) }
                    pendingDelete = []
                }
                Button("取消", role: .cancel) { pendingDelete = [] }
            } message: {
                Text("歌单会去掉，里面的音轨还在资料库里。")
            }
        }
    }
}

struct PlaylistDetail: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerModel
    let playlistID: UUID
    @State private var renaming = false
    @State private var name = ""
    @State private var adding = false
    @State private var editing: Track?
    @State private var trimming: Track?

    private var playlist: Playlist? { library.playlists.first { $0.id == playlistID } }
    private var tracks: [Track] { playlist.map { library.tracks(in: $0) } ?? [] }

    var body: some View {
        List {
            if tracks.isEmpty {
                Text("这张歌单还是空的。点右上角加进去。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(tracks) { track in
                    Button { player.play(track, in: tracks) } label: { TrackRow(track: track) }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button { player.queueNext(track) } label: { Label("下一首播放", systemImage: "text.insert") }
                            Button { editing = track } label: { Label("编辑信息", systemImage: "pencil") }
                            Button { trimming = track } label: { Label("剪一段", systemImage: "scissors") }
                            if track.sourceURL != nil {
                                Button { LinkOpener.open(track) } label: { Label("打开原视频", systemImage: "arrow.up.right.square") }
                            }
                        }
                }
                .onDelete { library.removeTracks(at: $0, playlistID: playlistID) }
                .onMove { library.moveTracks(in: playlistID, from: $0, to: $1) }
            }
        }
        .navigationTitle(playlist?.name ?? "歌单")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { EditButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("添加音轨") { adding = true }
                    Button("重命名") {
                        name = playlist?.name ?? ""
                        renaming = true
                    }
                    Button("播放全部") {
                        if let first = tracks.first { player.play(first, in: tracks) }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("重命名", isPresented: $renaming) {
            TextField("名称", text: $name)
            Button("保存") { library.renamePlaylist(playlistID, to: name) }
            Button("取消", role: .cancel) {}
        }
        .sheet(isPresented: $adding) { AddTracksSheet(playlistID: playlistID) }
        .sheet(item: $editing) { MetadataEditor(track: $0) }
        .sheet(item: $trimming) { TrimEditor(track: $0) }
    }
}

struct AddTracksSheet: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let playlistID: UUID
    @State private var picked: Set<UUID> = []
    @State private var search = ""

    private var candidates: [Track] {
        LibraryQuery.apply(library.tracks, search: search, sort: .title)
    }

    var body: some View {
        NavigationStack {
            List(candidates) { track in
                Button {
                    if picked.contains(track.id) { picked.remove(track.id) } else { picked.insert(track.id) }
                } label: {
                    HStack {
                        TrackRow(track: track)
                        Image(systemName: picked.contains(track.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(picked.contains(track.id) ? SX.cinnabar : .secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $search, prompt: "搜索")
            .navigationTitle("添加音轨")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("加入 \(picked.count)") {
                        library.add(Array(picked), to: playlistID)
                        dismiss()
                    }
                    .disabled(picked.isEmpty)
                }
            }
        }
    }
}
