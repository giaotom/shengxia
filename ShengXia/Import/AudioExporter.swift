import AVFoundation
import Foundation

enum AudioExporter {
    static func duration(of url: URL) async -> TimeInterval {
        let asset = AVURLAsset(url: url)
        guard let value = try? await asset.load(.duration) else { return 0 }
        let seconds = value.seconds
        return seconds.isFinite && seconds > 0 ? seconds : 0
    }

    static func hasAudioTrack(_ url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        let tracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
        return !tracks.isEmpty
    }

    static func remuxToM4A(from source: URL, to destination: URL, onProgress: @escaping (Double) -> Void) async throws {
        do {
            try await export(source, to: destination, preset: AVAssetExportPresetPassthrough, onProgress: onProgress)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            try await export(source, to: destination, preset: AVAssetExportPresetAppleM4A, onProgress: onProgress)
        }
    }

    static func extractM4A(from source: URL, to destination: URL, onProgress: @escaping (Double) -> Void) async throws {
        let asset = AVURLAsset(url: source)
        let tracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
        if tracks.isEmpty { throw AppError.noAudioTrack }
        try await export(source, to: destination, preset: AVAssetExportPresetAppleM4A, onProgress: onProgress)
    }

    private static func export(
        _ source: URL,
        to destination: URL,
        preset: String,
        onProgress: @escaping (Double) -> Void
    ) async throws {
        let asset = AVURLAsset(url: source)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw AppError.exportFailed
        }
        try? FileManager.default.removeItem(at: destination)
        exporter.outputURL = destination
        exporter.outputFileType = .m4a
        exporter.shouldOptimizeForNetworkUse = true
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let poll = Task {
                while exporter.status == .unknown || exporter.status == .waiting || exporter.status == .exporting {
                    let progress = Double(exporter.progress)
                    DispatchQueue.main.async { onProgress(progress) }
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
            }
            exporter.exportAsynchronously {
                poll.cancel()
                switch exporter.status {
                case .completed:
                    continuation.resume()
                case .cancelled:
                    continuation.resume(throwing: AppError.cancelled)
                default:
                    continuation.resume(throwing: exporter.error ?? AppError.exportFailed)
                }
            }
        }
        onProgress(1)
    }
}
