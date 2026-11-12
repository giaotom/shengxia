import SwiftUI

enum SX {
    static let paper = Color("Paper")
    static let ink = Color("Ink")
    static let cinnabar = Color("Cinnabar")
    static let brass = Color("Brass")
    static let card = Color("Card")
    static let mist = Color("Mist")
}

enum Clock {
    static func string(_ time: TimeInterval) -> String {
        guard time.isFinite, time > 0 else { return "0:00" }
        let total = Int(time.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

enum ByteText {
    static func string(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kilobytes = Double(bytes) / 1024
        if kilobytes < 1024 { return String(format: "%.0f KB", kilobytes) }
        return String(format: "%.1f MB", kilobytes / 1024)
    }
}
