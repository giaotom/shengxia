import Foundation

public enum MediaSniffer {
    public static func looksLikeMedia(_ data: Data) -> Bool {
        guard data.count >= 12 else { return false }
        if data.starts(with: Data("<".utf8)) || data.starts(with: Data("{".utf8)) || data.starts(with: Data("[".utf8)) {
            return false
        }
        if data.starts(with: Data("ID3".utf8)) { return true }
        if data.starts(with: Data("fLaC".utf8)) { return true }
        if data.starts(with: Data("OggS".utf8)) { return true }
        if data.subdata(in: 4..<8) == Data("ftyp".utf8) { return true }
        if data[0] == 0xFF && (data[1] & 0xE0) == 0xE0 { return true }
        return false
    }

    public static func looksLikeMedia(file url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let header = (try? handle.read(upToCount: 64)) ?? Data()
        return looksLikeMedia(header)
    }
}
