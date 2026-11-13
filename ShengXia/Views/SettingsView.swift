import ShengXiaCore
import SwiftUI
import UniformTypeIdentifiers

struct JSONFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var usage = StorageUsage(musicBytes: 0, cacheBytes: 0)
    @State private var clearing = false
    @State private var confirmClear = false
    @State private var exporting = false
    @State private var backup: JSONFile?
    @State private var notice: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("去掉头尾静音", isOn: $settings.autoTrimSilence)
                    Toggle("响度对齐", isOn: $settings.normalizeLoudness)
                    Text("新保存的音轨会按这两个开关处理。已经在资料库里的不会重做。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("提取")
                }
                Section {
                    Picker("音质", selection: $settings.quality) {
                        ForEach(AudioQuality.allCases, id: \.self) { quality in
                            Text(quality.title).tag(quality)
                        }
                    }
                    Text(settings.quality.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("外观") {
                    Picker("主题", selection: $settings.appearance) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Text(appearance.title).tag(appearance)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section("存储") {
                    LabeledContent("音轨", value: ByteText.string(usage.musicBytes))
                    LabeledContent("缓存", value: ByteText.string(usage.cacheBytes))
                    LabeledContent("资料库", value: "\(library.tracks.count) 首")
                    Button("清除缓存") { confirmClear = true }
                        .disabled(clearing)
                    Button("导出资料库到文件") { exportLibrary() }
                    Text("音轨本来就在「文件」App 的声匣 / Music。导出的是歌单和信息；同一份也会放进声匣 / 备份。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("分享给声匣") {
                    Text("系统分享菜单里如果有「声匣」，点一下就会把链接排进提取队列。")
                    Text("免费 Apple ID 用 Sideloadly 安装时，分享扩展有时签不上。主 App 不受影响。签不上的话，用快捷指令：分享 → 快捷指令，打开 URL，地址写成 shengxia://extract?text= 再接上链接。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("关于") {
                    LabeledContent("版本", value: versionText)
                    Text("声匣只保存公开视频的整条音轨，不绕过大会员、会员或年龄限制，也不做人声分离。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let notice {
                    Section { Text(notice).font(.footnote) }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .onAppear { usage = library.storageUsage() }
            .confirmationDialog("清除缓存？", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("清除", role: .destructive) {
                    clearing = true
                    Task {
                        await library.clearCache()
                        usage = library.storageUsage()
                        clearing = false
                        notice = "缓存已清掉，音轨还在。"
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("只会清掉临时文件和网页缓存，资料库里的音轨不会动。")
            }
            .fileExporter(
                isPresented: $exporting,
                document: backup,
                contentType: .json,
                defaultFilename: "声匣资料库"
            ) { result in
                if case .failure(let error) = result { notice = error.localizedDescription }
            }
        }
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.0.1"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return build.isEmpty ? version : "\(version)（\(build)）"
    }

    private func exportLibrary() {
        do {
            _ = try library.makeBackup()
            backup = JSONFile(data: try library.backupData())
            exporting = true
            notice = "一份副本已经放进「文件」App 的声匣 / 备份。"
        } catch {
            notice = error.localizedDescription
        }
    }
}
