import SwiftUI
import UIKit

struct MiniPlayer: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerModel
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    cover
                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.current?.title ?? "未在播放")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(SX.ink)
                            .lineLimit(1)
                        Text(player.current.map { "\($0.formatLabel) · \($0.artist)" } ?? "")
                            .font(.caption)
                            .foregroundStyle(SX.brass)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("打开正在播放")

            Button(action: { player.toggle() }) {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(player.isPlaying ? "暂停" : "播放")
            .foregroundStyle(SX.cinnabar)
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(SX.mist.opacity(0.7), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var cover: some View {
        Group {
            if let track = player.current, let url = library.coverURL(for: track), let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    SX.cinnabar.opacity(0.18)
                    Image(systemName: "music.note").foregroundStyle(SX.cinnabar)
                }
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct PlayerScreen: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerModel
    @Environment(\.dismiss) private var dismiss
    let onDelete: (Track) -> Void

    var body: some View {
        ZStack {
            SX.paper.ignoresSafeArea()
            if let track = player.current {
                ScrollView {
                    VStack(spacing: 22) {
                        cover(track)
                            .padding(.top, 28)
                        VStack(spacing: 6) {
                            Text(track.title)
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(SX.ink)
                                .multilineTextAlignment(.center)
                            Text(track.artist)
                                .font(.body)
                                .foregroundStyle(SX.ink.opacity(0.68))
                            Text("\(track.formatLabel) · \(track.sourceName) · 整轨，未做人声分离")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(SX.brass)
                                .multilineTextAlignment(.center)
                            if track.byteCount > 0 {
                                Text(ByteText.string(track.byteCount))
                                    .font(.caption2)
                                    .foregroundStyle(SX.ink.opacity(0.45))
                            }
                        }
                        .padding(.horizontal, 24)

                        VStack(spacing: 8) {
                            Slider(
                                value: Binding(
                                    get: { player.currentTime },
                                    set: { player.currentTime = $0 }
                                ),
                                in: 0...max(player.duration, 0.1),
                                onEditingChanged: { editing in
                                    player.isScrubbing = editing
                                    if !editing { player.seek(to: player.currentTime) }
                                }
                            )
                            .tint(SX.cinnabar)
                            .accessibilityLabel("播放进度")
                            HStack {
                                Text(Clock.string(player.currentTime))
                                Spacer()
                                Text(Clock.string(player.duration))
                            }
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(SX.ink.opacity(0.55))
                        }
                        .padding(.horizontal, 28)

                        HStack(spacing: 22) {
                            modeButton(
                                symbol: "shuffle",
                                label: player.shuffle ? "关闭随机" : "随机播放",
                                active: player.shuffle
                            ) { player.toggleShuffle() }
                            transportButton("backward.fill", label: "上一首") { player.playPrevious() }
                            Button(action: { player.toggle() }) {
                                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundStyle(SX.paper)
                                    .frame(width: 72, height: 72)
                                    .background(SX.cinnabar, in: Circle())
                            }
                            .accessibilityLabel(player.isPlaying ? "暂停" : "播放")
                            transportButton("forward.fill", label: "下一首") { player.playNext(automatic: false) }
                            modeButton(
                                symbol: player.repeatMode.symbol,
                                label: player.repeatMode.title,
                                active: player.repeatMode != .off
                            ) { player.cycleRepeat() }
                        }

                        if let playbackError = player.playbackError {
                            Text(playbackError)
                                .font(.footnote)
                                .foregroundStyle(SX.cinnabar)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }

                        Button(role: .destructive) {
                            onDelete(track)
                        } label: {
                            Label("删除这首", systemImage: "trash")
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 28)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Text("还没有在播的音轨")
                        .font(.headline)
                        .foregroundStyle(SX.ink)
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private func cover(_ track: Track) -> some View {
        Group {
            if let url = library.coverURL(for: track), let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    SX.cinnabar.opacity(0.18)
                    Image(systemName: "music.note")
                        .font(.system(size: 64))
                        .foregroundStyle(SX.cinnabar)
                }
            }
        }
        .frame(width: 280, height: 280)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(SX.brass.opacity(0.45), lineWidth: 1)
        )
        .shadow(color: SX.ink.opacity(0.12), radius: 18, y: 10)
    }

    private func transportButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title2)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel(label)
        .foregroundStyle(SX.ink)
    }

    private func modeButton(symbol: String, label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel(label)
        .foregroundStyle(active ? SX.cinnabar : SX.ink.opacity(0.45))
    }
}
