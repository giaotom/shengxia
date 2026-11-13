import ShengXiaCore
import SwiftUI

struct TrackRow: View {
    @EnvironmentObject private var player: PlayerModel
    let track: Track
    var subtitle: String?

    var body: some View {
        HStack(spacing: 12) {
            CoverThumb(track: track, side: 56, radius: 10)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(track.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(SX.ink)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    if track.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.caption2)
                            .foregroundStyle(SX.cinnabar)
                    }
                }
                Text(track.artist)
                    .font(.subheadline)
                    .foregroundStyle(SX.ink.opacity(0.62))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(track.sourceKind.shortName)
                    Text(track.formatLabel)
                    Text(track.duration > 0 ? Clock.string(track.duration) : "时长未知")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(SX.brass)
                .lineLimit(1)
                if let note = subtitle ?? track.processingNote, !note.isEmpty {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(SX.ink.opacity(0.45))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Image(systemName: isCurrent && player.isPlaying ? "waveform" : "play.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(isCurrent ? SX.cinnabar : SX.ink.opacity(0.4))
                .frame(width: 22)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(track.title)，\(track.artist)，\(track.sourceKind.shortName)")
    }

    private var isCurrent: Bool { player.current?.id == track.id }
}
