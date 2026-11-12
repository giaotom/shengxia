import Foundation

enum JSON {
    static func object(from data: Data) throws -> [String: Any] {
        if data.isEmpty { throw ResolveError.badResponse("空响应") }
        let any: Any
        do {
            any = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw ResolveError.badResponse("返回的不是 JSON")
        }
        guard let object = any as? [String: Any] else {
            throw ResolveError.badResponse("返回的不是 JSON 对象")
        }
        return object
    }

    static func any(from text: String) -> Any? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    static func string(_ dict: [String: Any], _ key: String) -> String? {
        if let value = dict[key] as? String { return value }
        if let number = dict[key] as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    static func int(_ dict: [String: Any], _ key: String) -> Int? {
        if let value = dict[key] as? Int { return value }
        if let number = dict[key] as? NSNumber { return number.intValue }
        if let text = dict[key] as? String { return Int(text) }
        return nil
    }

    static func double(_ dict: [String: Any], _ key: String) -> Double? {
        if let value = dict[key] as? Double { return value }
        if let number = dict[key] as? NSNumber { return number.doubleValue }
        if let text = dict[key] as? String { return Double(text) }
        return nil
    }

    static func dictionary(_ dict: [String: Any], _ key: String) -> [String: Any]? {
        dict[key] as? [String: Any]
    }

    static func array(_ dict: [String: Any], _ key: String) -> [Any]? {
        dict[key] as? [Any]
    }
}

enum URLText {
    static func httpsURL(_ string: String?) -> URL? {
        guard var string, !string.isEmpty else { return nil }
        if string.hasPrefix("//") { string = "https:" + string }
        if string.hasPrefix("http://") {
            string = "https://" + string.dropFirst("http://".count)
        }
        string = string.replacingOccurrences(of: "\\u002F", with: "/")
        string = string.replacingOccurrences(of: "\\/", with: "/")
        return URL(string: string)
    }
}
