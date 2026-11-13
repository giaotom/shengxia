import ShengXiaCore
import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var scheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var autoTrimSilence: Bool { didSet { save() } }
    @Published var normalizeLoudness: Bool { didSet { save() } }
    @Published var quality: AudioQuality { didSet { save() } }
    @Published var appearance: AppAppearance { didSet { save() } }
    @Published var playbackRate: Float { didSet { save() } }

    private let defaults = UserDefaults.standard

    init() {
        autoTrimSilence = defaults.bool(forKey: Key.trim)
        normalizeLoudness = defaults.bool(forKey: Key.normalize)
        quality = AudioQuality(rawValue: defaults.string(forKey: Key.quality) ?? "") ?? .best
        appearance = AppAppearance(rawValue: defaults.string(forKey: Key.appearance) ?? "") ?? .system
        let stored = defaults.object(forKey: Key.rate) as? Double
        playbackRate = stored.map { min(2, max(0.5, Float($0))) } ?? 1
    }

    private func save() {
        defaults.set(autoTrimSilence, forKey: Key.trim)
        defaults.set(normalizeLoudness, forKey: Key.normalize)
        defaults.set(quality.rawValue, forKey: Key.quality)
        defaults.set(appearance.rawValue, forKey: Key.appearance)
        defaults.set(Double(playbackRate), forKey: Key.rate)
    }

    private enum Key {
        static let trim = "sx.trim"
        static let normalize = "sx.normalize"
        static let quality = "sx.quality"
        static let appearance = "sx.appearance"
        static let rate = "sx.rate"
    }
}
