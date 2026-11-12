import ShengXiaCore
import SwiftUI

struct PasteCard: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerModel
    @EnvironmentObject private var importer: ImportController
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("取音")
                .font(.headline)
                .foregroundStyle(SX.ink)
            TextField("粘贴哔哩哔哩、抖音或 YouTube 链接", text: $importer.linkText, axis: .vertical)
                .lineLimit(1...5)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .focused($focused)
                .padding(12)
                .background(SX.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(SX.mist, lineWidth: 1)
                )
            Text("支持完整链接、b23.tv、BV 号、抖音分享文案，以及 YouTube、Shorts 和 youtu.be。")
                .font(.caption)
                .foregroundStyle(SX.ink.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button {
                    importer.pasteFromClipboard()
                } label: {
                    Label("粘贴", systemImage: "doc.on.clipboard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(importer.phase.isBusy)

                Button {
                    focused = false
                    Task { await importer.start(library: library, player: player) }
                } label: {
                    Label("获取音轨", systemImage: "arrow.down.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(importer.phase.isBusy || importer.linkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .controlSize(.large)

            status
        }
        .padding(16)
        .background(SX.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { focused = false }
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        switch importer.phase {
        case .idle:
            EmptyView()
        case .resolving:
            statusRow(title: "正在解析链接", progress: nil)
        case .openingDouyin:
            statusRow(title: importer.webHint, progress: nil)
        case .downloading(let value):
            if let value {
                statusRow(title: "正在下载 \(Int((value * 100).rounded()))%", progress: value)
            } else {
                statusRow(title: "正在下载…", progress: nil)
            }
        case .extracting(let value):
            statusRow(title: "正在提取音轨 \(Int((value * 100).rounded()))%", progress: value)
        case .saving:
            statusRow(title: "正在写入资料库", progress: nil)
        case .success(let message):
            Text(message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color(red: 0.16, green: 0.42, blue: 0.30))
                .fixedSize(horizontal: false, vertical: true)
        case .failed(let message):
            Text(message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(SX.cinnabar)
                .fixedSize(horizontal: false, vertical: true)
        }
        if importer.phase.isBusy {
            Button("取消", role: .cancel) { importer.cancel() }
                .font(.subheadline)
                .foregroundStyle(SX.ink.opacity(0.7))
        }
    }

    private func statusRow(title: String, progress: Double?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if progress == nil { ProgressView() }
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(SX.ink)
            }
            if let progress {
                ProgressView(value: min(max(progress, 0), 1))
                    .tint(SX.cinnabar)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct DouyinCapturePanel: View {
    let request: WebCaptureRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("抖音页面")
                .font(.headline)
                .foregroundStyle(SX.ink)
            Text("公开页面只用来拿到视频地址，不会登录你的抖音账号。如果出现验证，直接在页面里完成。")
                .font(.caption)
                .foregroundStyle(SX.ink.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)
            GeometryReader { proxy in
                let width: CGFloat = 1100
                let height: CGFloat = 720
                let scale = max(proxy.size.width / width, 0.2)
                DouyinWebRepresentable(request: request)
                    .frame(width: width, height: height)
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: proxy.size.width, height: height * scale, alignment: .topLeading)
            }
            .frame(height: 230)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(SX.mist, lineWidth: 1)
            )
        }
        .padding(16)
        .background(SX.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
