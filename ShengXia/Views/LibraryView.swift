import ShengXiaCore
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerModel
    @State private var filter: LibraryFilter = .all
    @State private var search = ""
    @State private var sort: LibrarySort = .recent
    @State private var editing: Track?
    @State private var trimming: Track?
    @State private var adding: Track?
    @State private var pendingDelete: Track?
    @State private var importing = false

    private var shown: [Track] {
        LibraryQuery.apply(library.tracks, filter: filter, search: search, sort: sort)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(LibraryFilter.chips, id: \.self) { chip in
                                Button { filter = chip } label: {
                                    Text(chip.title)
                                        .font(.subheadline.weight(.medium))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .foregroundStyle(filter == chip ? Color.white : SX.ink)
                                        .background(filter == chip ? SX.cinnabar : Color.clear, in: Capsule())
                                        .overlay(Capsule().strokeBorder(filter == chip ? Color.clear : SX.mist, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                if shown.isEmpty {
                    Section { empty } 
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    Section {
                        ForEach(shown) { track in
                            Button { player.play(track, in: shown) } label: { TrackRow(track: track) }
                                .buttonStyle(.plain)
                                .swipeActions {
                                    Button { library.toggleFavorite(track.id) } label: {
                                        Label(track.isFavorite ? "取消喜欢" : "喜欢", systemImage: "heart")
                                    }
                                    .tint(SX.cinnabar)
                                    Button { player.queueNext(track) } label: {
                                        Label("下一首", systemImage: "text.line.first.and.arrowtriangle.forward")
                                    }
                                    .tint(SX.brass)
                                    Button(role: .destructive) { pendingDelete = track } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                                .contextMenu { actions(track) }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(SXBackground())
            .navigationTitle("资料库")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $search, prompt: "搜索标题或作者")
            .refreshable { await library.refreshFromDisk() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("排序", selection: $sort) {
                            ForEach(LibrarySort.allCases, id: \.self) { item in
                                Text(item.title).tag(item)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .accessibilityLabel("排序")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 10) {
                        Button { importing = true } label: { Image(systemName: "square.and.arrow.down") }
                            .accessibilityLabel("从文件导入")
                        SettingsButton()
                    }
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: importTypes, allowsMultipleSelection: true) { result in
                if case .success(let urls) = result {
                    Task { await library.importExternal(urls) }
                }
            }
            .sheet(item: $editing) { track in MetadataEditor(track: track) }
            .sheet(item: $trimming) { track in TrimEditor(track: track) }
            .sheet(item: $adding) { track in PlaylistPicker(track: track) }
            .confirmationDialog("删除这首？", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    if let track = pendingDelete { library.delete(track) }
                    pendingDelete = nil
                }
                Button("取消", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("音轨和封面会从这台 iPhone 的「文件」App 里去掉。")
            }
        }
    }

    private var importTypes: [UTType] {
        var types: [UTType] = [.audio, .movie, .mpeg4Movie, .mpeg4Audio, .mp3]
        if let flac = UTType(filenameExtension: "flac") { types.append(flac) }
        if let wav = UTType(filenameExtension: "wav") { types.append(wav) }
        return types
    }

    @ViewBuilder
    private func actions(_ track: Track) -> some View {
        Button { player.play(track, in: shown) } label: { Label("播放", systemImage: "play.fill") }
        Button { player.queueNext(track) } label: { Label("下一首播放", systemImage: "text.insert") }
        Button { player.queueAppend(track) } label: { Label("加入队列", systemImage: "text.badge.plus") }
        Button { adding = track } label: { Label("加入歌单", systemImage: "rectangle.stack.badge.plus") }
        Button { library.toggleFavorite(track.id) } label: {
            Label(track.isFavorite ? "取消喜欢" : "喜欢", systemImage: "heart")
        }
        Button { editing = track } label: { Label("编辑信息", systemImage: "pencil") }
        Button { trimming = track } label: { Label("剪一段", systemImage: "scissors") }
        if track.sourceURL != nil {
            Button { LinkOpener.open(track) } label: { Label("打开原视频", systemImage: "arrow.up.right.square") }
        }
        Button(role: .destructive) { pendingDelete = track } label: { Label("删除", systemImage: "trash") }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(library.tracks.isEmpty ? "匣子还是空的" : "没有符合的音轨")
                .font(.title3.weight(.semibold))
                .foregroundStyle(SX.ink)
            Text(library.tracks.isEmpty
                 ? "去「提取」粘贴链接，或把 mp3、m4a、flac 放进「文件」App 的声匣 / Music，再下拉这里。"
                 : "换个筛选，或者把搜索词清掉。")
                .font(.subheadline)
                .foregroundStyle(SX.ink.opacity(0.68))
        }
        .padding(.vertical, 12)
    }
}

struct PlaylistPicker: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let track: Track
    @State private var name = ""
    @State private var creating = false

    var body: some View {
        NavigationStack {
            List {
                if library.playlists.isEmpty {
                    Text("还没有歌单。先新建一个。")
                        .foregroundStyle(.secondary)
                }
                ForEach(library.playlists) { playlist in
                    Button {
                        library.add([track.id], to: playlist.id)
                        dismiss()
                    } label: {
                        HStack {
                            Text(playlist.name).foregroundStyle(SX.ink)
                            Spacer()
                            Text("\(playlist.trackIDs.count)")
                                .foregroundStyle(.secondary)
                            if playlist.trackIDs.contains(track.id) {
                                Image(systemName: "checkmark").foregroundStyle(SX.cinnabar)
                            }
                        }
                    }
                }
            }
            .navigationTitle("加入歌单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("新建") { creating = true } }
            }
            .alert("新歌单", isPresented: $creating) {
                TextField("名称", text: $name)
                Button("创建") {
                    let playlist = library.createPlaylist(name: name)
                    library.add([track.id], to: playlist.id)
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            }
        }
        .presentationDetents([.medium, .large])
    }
}
