import Foundation

public enum AudioQuality: String, CaseIterable, Codable, Sendable {
    case best
    case standard
    case compact

    public var title: String {
        switch self {
        case .best: return "最高音质"
        case .standard: return "标准 AAC"
        case .compact: return "省空间"
        }
    }

    public var detail: String {
        switch self {
        case .best: return "B 站有无损就存 FLAC，否则取最高码率"
        case .standard: return "只取 AAC，体积和兼容性更均衡"
        case .compact: return "取最低码率 AAC，适合存很多"
        }
    }
}

public struct AudioAnalysis: Equatable, Sendable {
    public var levelsDB: [Float]
    public var windowSeconds: Double
    public var peakDB: Float
    public var duration: TimeInterval

    public init(levelsDB: [Float], windowSeconds: Double, peakDB: Float, duration: TimeInterval) {
        self.levelsDB = levelsDB
        self.windowSeconds = windowSeconds
        self.peakDB = peakDB
        self.duration = duration
    }

    public var loudnessDB: Float { AudioMath.gatedLoudness(levelsDB) }
}

public enum AudioMath {
    public static let floorDB: Float = -120

    public static func decibels(_ linear: Float) -> Float {
        guard linear > 0, linear.isFinite else { return floorDB }
        return max(floorDB, 20 * log10(linear))
    }

    public static func linear(_ db: Float) -> Float {
        pow(10, db / 20)
    }

    public static func gatedLoudness(_ levelsDB: [Float], gateDB: Float = -60) -> Float {
        let loud = levelsDB.filter { $0 > gateDB }
        guard !loud.isEmpty else { return floorDB }
        let meanPower = loud.reduce(Float(0)) { $0 + pow(10, $1 / 10) } / Float(loud.count)
        return 10 * log10(meanPower)
    }

    public static func silenceTrimRange(
        levelsDB: [Float],
        windowSeconds: Double,
        thresholdDB: Float = -50,
        padding: Double = 0.25,
        minimumTrim: Double = 0.4
    ) -> ClosedRange<Double>? {
        guard windowSeconds > 0, !levelsDB.isEmpty else { return nil }
        guard let first = levelsDB.firstIndex(where: { $0 > thresholdDB }),
              let last = levelsDB.lastIndex(where: { $0 > thresholdDB }) else { return nil }
        let total = Double(levelsDB.count) * windowSeconds
        let start = max(0, Double(first) * windowSeconds - padding)
        let end = min(total, Double(last + 1) * windowSeconds + padding)
        guard end - start > 1 else { return nil }
        let trimmed = start + (total - end)
        guard trimmed >= minimumTrim else { return nil }
        return start...end
    }

    public static func normalizationGain(
        loudnessDB: Float,
        peakDB: Float,
        targetDB: Float = -16,
        ceilingDB: Float = -1,
        maxBoostDB: Float = 12,
        maxCutDB: Float = 12
    ) -> Float {
        guard loudnessDB > floorDB, peakDB > floorDB else { return 0 }
        var gain = targetDB - loudnessDB
        gain = min(gain, ceilingDB - peakDB)
        gain = max(-maxCutDB, min(maxBoostDB, gain))
        return abs(gain) < 0.5 ? 0 : gain
    }

    public static func waveform(levelsDB: [Float], bars: Int, floorDB: Float = -60) -> [Float] {
        guard bars > 0, !levelsDB.isEmpty else { return Array(repeating: 0, count: max(bars, 0)) }
        var result: [Float] = []
        result.reserveCapacity(bars)
        for bar in 0..<bars {
            let lower = bar * levelsDB.count / bars
            let upper = max(lower + 1, (bar + 1) * levelsDB.count / bars)
            let slice = levelsDB[lower..<min(upper, levelsDB.count)]
            let loudest = slice.max() ?? floorDB
            result.append(max(0, min(1, (loudest - floorDB) / -floorDB)))
        }
        return result
    }

    public static func clampClip(
        start: Double,
        end: Double,
        duration: Double,
        minimumLength: Double = 1
    ) -> ClosedRange<Double> {
        guard duration > 0 else { return 0...0 }
        let minLength = min(minimumLength, duration)
        let lower = max(0, min(start, duration - minLength))
        let upper = min(duration, max(end, lower + minLength))
        if upper - lower < minLength {
            let fixedLower = max(0, upper - minLength)
            return fixedLower...min(duration, fixedLower + minLength)
        }
        return lower...upper
    }

    public static func processingNote(trimmed: Double, gainDB: Float) -> String? {
        var parts: [String] = []
        if trimmed >= 0.1 { parts.append(String(format: "去静音 %.1f 秒", trimmed)) }
        if gainDB != 0 {
            parts.append("响度 " + (gainDB > 0 ? "+" : "") + String(format: "%.1f dB", gainDB))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
