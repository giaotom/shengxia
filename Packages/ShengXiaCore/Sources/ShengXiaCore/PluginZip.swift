import CInflate
import Foundation

public enum PluginZipError: Error, Equatable {
    case notAZip
    case unsupportedMethod(Int)
    case inflateFailed(Int)
    case tooLarge
}

public enum PluginZip {
    /// Reads a zip into path → bytes. Only the files a plugin needs are kept by the caller.
    public static func extract(_ data: Data, maxFileBytes: Int = 4_000_000, maxTotalBytes: Int = 24_000_000) throws -> [String: Data] {
        let bytes = [UInt8](data)
        guard let directory = centralDirectory(in: bytes) else { throw PluginZipError.notAZip }
        var files: [String: Data] = [:]
        var total = 0
        for entry in directory {
            if entry.name.hasSuffix("/") || entry.name.contains("__MACOSX") || entry.name.hasPrefix(".") { continue }
            if entry.uncompressed > maxFileBytes || entry.compressed > maxFileBytes { throw PluginZipError.tooLarge }
            let payload = try inflate(entry, in: bytes)
            total += payload.count
            if total > maxTotalBytes { throw PluginZipError.tooLarge }
            files[entry.name] = payload
        }
        return files
    }

    private struct Entry {
        var name: String
        var method: Int
        var compressed: Int
        var uncompressed: Int
        var localOffset: Int
    }

    private static func centralDirectory(in bytes: [UInt8]) -> [Entry]? {
        guard let eocd = lastIndex(of: [0x50, 0x4b, 0x05, 0x06], in: bytes, limit: 70_000) else { return nil }
        if eocd + 22 > bytes.count { return nil }
        let count = int16(bytes, eocd + 10)
        let offset = int32(bytes, eocd + 16)
        if offset < 0 || offset >= bytes.count { return nil }
        var cursor = offset
        var entries: [Entry] = []
        for _ in 0..<count {
            if cursor + 46 > bytes.count || int32(bytes, cursor) != 0x02014b50 { return nil }
            let method = int16(bytes, cursor + 10)
            let compressed = int32(bytes, cursor + 20)
            let uncompressed = int32(bytes, cursor + 24)
            let nameLength = int16(bytes, cursor + 28)
            let extraLength = int16(bytes, cursor + 30)
            let commentLength = int16(bytes, cursor + 32)
            let local = int32(bytes, cursor + 42)
            let nameStart = cursor + 46
            let nameEnd = nameStart + nameLength
            if nameEnd > bytes.count || compressed < 0 || uncompressed < 0 { return nil }
            let name = String(decoding: bytes[nameStart..<nameEnd], as: UTF8.self)
            entries.append(Entry(name: name, method: method, compressed: compressed, uncompressed: uncompressed, localOffset: local))
            cursor = nameEnd + extraLength + commentLength
        }
        return entries
    }

    private static func inflate(_ entry: Entry, in bytes: [UInt8]) throws -> Data {
        let local = entry.localOffset
        if local < 0 || local + 30 > bytes.count || int32(bytes, local) != 0x04034b50 {
            throw PluginZipError.notAZip
        }
        let nameLength = int16(bytes, local + 26)
        let extraLength = int16(bytes, local + 28)
        let start = local + 30 + nameLength + extraLength
        let end = start + entry.compressed
        if start < 0 || end > bytes.count { throw PluginZipError.notAZip }
        if entry.method == 0 {
            return Data(bytes[start..<end])
        }
        if entry.method != 8 { throw PluginZipError.unsupportedMethod(entry.method) }
        if entry.uncompressed == 0 { return Data() }
        var output = Data(count: entry.uncompressed)
        var destlen = UInt(entry.uncompressed)
        var sourcelen = UInt(entry.compressed)
        let status: Int32 = output.withUnsafeMutableBytes { dest in
            bytes.withUnsafeBufferPointer { source in
                guard let destPtr = dest.bindMemory(to: UInt8.self).baseAddress,
                      let sourceBase = source.baseAddress else { return Int32(2) }
                return puff(destPtr, &destlen, sourceBase + start, &sourcelen)
            }
        }
        if status != 0 { throw PluginZipError.inflateFailed(Int(status)) }
        return output.prefix(Int(destlen))
    }

    private static func int16(_ bytes: [UInt8], _ offset: Int) -> Int {
        Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
    }

    private static func int32(_ bytes: [UInt8], _ offset: Int) -> Int {
        Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8) | (Int(bytes[offset + 2]) << 16) | (Int(bytes[offset + 3]) << 24)
    }

    private static func lastIndex(of marker: [UInt8], in bytes: [UInt8], limit: Int) -> Int? {
        if bytes.count < marker.count { return nil }
        let start = max(0, bytes.count - limit)
        var index = bytes.count - marker.count
        while index >= start {
            if Array(bytes[index..<(index + marker.count)]) == marker { return index }
            index -= 1
        }
        return nil
    }
}
