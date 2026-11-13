import ShengXiaCore
import SwiftUI

struct ExtractView: View {
    @EnvironmentObject private var importer: ImportController
    @FocusState private var focused: Bool
    @State private var promptDrag: CGFloat = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let prompt = importer.clipboardPrompt {
                        clipboardCard(prompt)
                            .offset(y: min(0, promptDrag))
                            .opacity(promptOpacity)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    header
                    pasteCard
                    if importer.webRequest != nil {
                        DouyinCaptureStatus()
                    }
                    if !importer.jobs.isEmpty {
                        jobList
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 28)
                .animation(.easeInOut(duration: 0.32), value: importer.clipboardPrompt)
            }
            .background(SXBackground())
            .scrollDismissesKeyboard(.interactively)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { SettingsButton() }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { focused = false }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("声匣")
                .font(.system(size: 40, weight: .semibold, design: .serif))
                .foregroundStyle(SX.ink)
            Text("把公开视频的整条音轨留在这台手机上。")
                .font(.subheadline)
                .foregroundStyle(SX.ink.opacity(0.68))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var promptOpacity: Double {
        promptDrag < 0 ? max(0, 1 + Double(promptDrag) / 160) : 1
    }

    private func clipboardCard(_ prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("要提取这条吗？")
                .font(.headline)
                .foregroundStyle(SX.ink)
            Text(prompt)
                .font(.subheadline)
                .foregroundStyle(SX.ink.opacity(0.75))
                .lineLimit(2)
            HStack(spacing: 10) {
                Button("先不了") { hidePrompt { importer.dismissClipboard() } }
                    .sxGlassButton()
                Button("提取") { hidePrompt { importer.acceptClipboard() } }
                    .sxGlassButton(prominent: true)
            }
            .controlSize(.regular)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sxGlass(cornerRadius: 24)
        .contentShape(Rectangle())
        .gesture(promptSwipe)
        .accessibilityHint("向上滑动可以关掉")
    }

    private var promptSwipe: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                let travel = value.translation.height
                guard travel < 0, abs(travel) > abs(value.translation.width) else { return }
                promptDrag = travel
            }
            .onEnded { value in
                let travel = value.translation.height
                let shouldHide = travel < -42 && abs(travel) > abs(value.translation.width)
                if shouldHide {
                    withAnimation(.easeIn(duration: 0.26)) { promptDrag = -180 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            importer.dismissClipboard()
                            promptDrag = 0
                        }
                    }
                } else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { promptDrag = 0 }
                }
            }
    }

    private func hidePrompt(_ change: () -> Void) {
        withAnimation(.easeInOut(duration: 0.32)) {
            promptDrag = 0
            change()
        }
    }

    private var pasteCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("提取")
                .font(.headline)
                .foregroundStyle(SX.ink)
            TextField("粘贴哔哩哔哩、抖音或 YouTube 链接，一行一个也能批量", text: $importer.linkText, axis: .vertical)
                .lineLimit(1...6)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused)
                .padding(12)
                .background(SX.paper.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text("支持完整链接、b23.tv、BV 号、抖音分享文案，YouTube、Shorts 和 youtu.be。多条链接会排成队列。")
                .font(.caption)
                .foregroundStyle(SX.ink.opacity(0.62))
            HStack(spacing: 10) {
                Button { importer.pasteFromClipboard() } label: {
                    Label("粘贴", systemImage: "doc.on.clipboard").frame(maxWidth: .infinity)
                }
                .sxGlassButton()
                .disabled(importer.phase.isBusy)
                Button {
                    focused = false
                    let text = importer.linkText
                    importer.linkText = ""
                    importer.enqueue(text)
                } label: {
                    Label("获取音轨", systemImage: "arrow.down.circle.fill").frame(maxWidth: .infinity)
                }
                .sxGlassButton(prominent: true)
                .disabled(importer.phase.isBusy || importer.linkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .controlSize(.large)
            status
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .environment(\.colorScheme, .light)
    }

    @ViewBuilder
    private var status: some View {
        switch importer.phase {
        case .idle:
            EmptyView()
        case .resolving:
            statusRow("正在解析链接", progress: nil)
        case .openingDouyin:
            statusRow(importer.webHint, progress: nil)
        case .downloading(let value):
            if let value {
                statusRow("正在下载 \(Int((value * 100).rounded()))%", progress: value)
            } else {
                statusRow("正在下载…", progress: nil)
            }
        case .extracting(let value):
            statusRow("正在处理音轨 \(Int((value * 100).rounded()))%", progress: value)
        case .saving:
            statusRow("正在写入资料库", progress: nil)
        case .success(let message):
            Text(message).font(.subheadline.weight(.medium)).foregroundStyle(Color(red: 0.16, green: 0.45, blue: 0.32))
        case .failed(let message):
            Text(message).font(.subheadline.weight(.medium)).foregroundStyle(SX.cinnabar)
        }
        if importer.phase.isBusy {
            Button("取消当前", role: .cancel) { importer.cancelCurrent() }
                .font(.subheadline)
                .foregroundStyle(SX.ink.opacity(0.72))
        }
    }

    private func statusRow(_ title: String, progress: Double?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if progress == nil { ProgressView() }
                Text(title).font(.subheadline).foregroundStyle(SX.ink)
            }
            if let progress {
                ProgressView(value: min(max(progress, 0), 1)).tint(SX.cinnabar)
            }
        }
    }

    private var jobList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("队列")
                    .font(.headline)
                    .foregroundStyle(SX.ink)
                Spacer()
                Text("\(importer.jobs.filter { if case .succeeded = $0.state { return true }; return false }.count)/\(importer.jobs.count)")
                    .font(.caption)
                    .foregroundStyle(SX.brass)
                Button("清除完成") { importer.clearFinished() }
                    .font(.caption)
                if importer.jobs.contains(where: { if case .queued = $0.state { return true }; return false }) {
                    Button("全部取消") { importer.cancelAll() }
                        .font(.caption)
                }
            }
            ForEach(importer.jobs) { job in
                VStack(alignment: .leading, spacing: 6) {
                    Text(job.input)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(SX.ink)
                        .lineLimit(2)
                    Text(job.title)
                        .font(.caption)
                        .foregroundStyle(jobColor(job))
                    if let progress = job.progress, case .working = job.state {
                        ProgressView(value: min(max(progress, 0), 1)).tint(SX.cinnabar)
                    }
                    HStack(spacing: 12) {
                        if case .failed = job.state {
                            Button("重试") { importer.retry(job.id) }.font(.caption.weight(.semibold))
                        }
                        if case .skipped = job.state {
                            Button("仍然提取") { importer.force(job.id) }.font(.caption.weight(.semibold))
                        }
                        Button("移除") { importer.remove(job.id) }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(SX.card.opacity(0.88), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private func jobColor(_ job: ImportJob) -> Color {
        switch job.state {
        case .failed: return SX.cinnabar
        case .succeeded: return Color(red: 0.16, green: 0.45, blue: 0.32)
        case .skipped: return SX.brass
        default: return SX.ink.opacity(0.7)
        }
    }
}

private struct DouyinCaptureStatus: View {
    @EnvironmentObject private var importer: ImportController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("抖音页面")
                .font(.headline)
                .foregroundStyle(SX.ink)
            Text(importer.verificationVisible
                 ? "验证页已打开。滑块可以双指放大后再拖，通过后会自动继续。"
                 : "公开页面只用来拿到视频地址，不会登录你的抖音账号。出现验证时会打开接近全屏的页面。")
                .font(.caption)
                .foregroundStyle(SX.ink.opacity(0.68))
            if !importer.verificationVisible {
                Button {
                    importer.showVerification()
                } label: {
                    Label("打开验证页", systemImage: "viewfinder")
                }
                .sxGlassButton(prominent: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .sxGlass(cornerRadius: 24)
    }
}
