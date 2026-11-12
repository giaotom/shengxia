import Foundation

public enum FileNameSanitizer {
    public static func sanitizeBase(_ title: String, maxLength: Int = 60) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.newlines).union(.controlCharacters)
        let pieces = title.unicodeScalars.map { scalar -> Character in
            illegal.contains(scalar) ? " " : Character(scalar)
        }
        let collapsed = String(pieces)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        let base = collapsed.isEmpty ? "未命名音轨" : collapsed
        if base.count <= maxLength { return base }
        let trimmed = String(base.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未命名音轨" : trimmed
    }

    public static func filename(title: String, extension ext: String) -> String {
        let clean = ext.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        return "\(sanitizeBase(title)).\(clean)"
    }
}
