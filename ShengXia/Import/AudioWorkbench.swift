import AVFoundation
import ShengXiaCore
import UIKit

enum AudioWorkbench {
    static func analyze(_ url: URL) async -> AudioAnalysis? {
        await Task.detached(priority: .userInitiated) {
            analyzeSync(url)
        }.value
    }

    static func waveform(for url: URL, bars: Int) async -> [Float] {
        guard let analysis = await analyze(url) else { return [] }
        return AudioMath.waveform(levelsDB: analysis.levelsDB, bars: bars)
    }

    static func videoFrame(at url: URL, seconds: Double) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let tracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []
        guard !tracks.isEmpty else { return nil }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 800, height: 800)
        let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        guard let cg = try? await generator.image(at: time).image else { return nil }
        return UIImage(cgImage: cg)
    }

    static func render(
        from source: URL,
        to destination: URL,
        range: ClosedRange<Double>?,
        gainDB: Float,
        onProgress: @escaping (Double) -> Void
    ) async throws {
        let asset = AVURLAsset(url: source)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw AppError.exportFailed
        }
        try? FileManager.default.removeItem(at: destination)
        exporter.outputURL = destination
        exporter.outputFileType = .m4a
        exporter.shouldOptimizeForNetworkUse = true
        if let range {
            let start = CMTime(seconds: max(0, range.lowerBound), preferredTimescale: 600)
            let end = CMTime(seconds: max(range.upperBound, range.lowerBound + 0.2), preferredTimescale: 600)
            exporter.timeRange = CMTimeRange(start: start, end: end)
        }
        if gainDB != 0 {
            let tracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
            if let track = tracks.first {
                let params = AVMutableAudioMixInputParameters(track: track)
                params.setVolume(AudioMath.linear(gainDB), at: .zero)
                let mix = AVMutableAudioMix()
                mix.inputParameters = [params]
                exporter.audioMix = mix
            }
        }
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

    private static func analyzeSync(_ url: URL) -> AudioAnalysis? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let sampleRate = format.sampleRate
        guard sampleRate > 0, format.channelCount > 0 else { return nil }
        let windowSeconds = 0.05
        let window = AVAudioFrameCount(sampleRate * windowSeconds)
        guard window > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: window) else { return nil }
        var levels: [Float] = []
        var peak: Float = 0
        let total = file.length
        while file.framePosition < total {
            buffer.frameLength = 0
            do { try file.read(into: buffer) } catch { break }
            let frames = Int(buffer.frameLength)
            if frames == 0 { break }
            guard let channels = buffer.floatChannelData else { return nil }
            var sum: Float = 0
            var count = 0
            for channel in 0..<Int(format.channelCount) {
                let samples = channels[channel]
                for index in 0..<frames {
                    let sample = samples[index]
                    peak = max(peak, abs(sample))
                    sum += sample * sample
                    count += 1
                }
            }
            let rms: Float = count > 0 ? sqrt(sum / Float(count)) : 0
            levels.append(AudioMath.decibels(rms))
        }
        guard !levels.isEmpty else { return nil }
        return AudioAnalysis(
            levelsDB: levels,
            windowSeconds: windowSeconds,
            peakDB: AudioMath.decibels(peak),
            duration: Double(total) / sampleRate
        )
    }
}
