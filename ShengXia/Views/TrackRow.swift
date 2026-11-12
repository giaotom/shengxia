import SwiftUI
import UIKit

struct TrackRow: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerModel
    let track: Track
    let onPlay: () -> Void

    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 12) {
                cover
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(SX.ink)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    Text(track.artist)
                        .font(.subheadline)
                        .foregroundStyle(SX.ink.opacity(0.62))
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Text(track.formatLabel)
                        Text(track.duration > 0 ? Clock.string(track.duration) : "时长未知")
                        Text(track.sourceName)
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(SX.brass)
                    .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: isCurrent && player.isPlaying ? "waveform" : "play.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isCurrent ? SX.cinnabar : SX.ink.opacity(0.55))
                    .frame(width: 28)
            }
            .padding(12)
            .background(SX.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(track.title)，\(track.artist)，\(track.formatLabel)")
        .accessibilityHint("播放")
    }

    private var isCurrent: Bool { player.current?.id == track.id }

    @ViewBuilder
    private var cover: some View {
        Group {
            if let url = library.coverURL(for: track), let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    SX.cinnabar.opacity(0.16)
                    Image(systemName: "music.note")
                        .foregroundStyle(SX.cinnabar)
                }
            }
        }
        .frame(width: 58, height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
