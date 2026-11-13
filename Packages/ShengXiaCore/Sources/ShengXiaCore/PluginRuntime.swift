import CommonCrypto
import Foundation
import JavaScriptCore

public enum PluginCallError: Error, Equatable, LocalizedError {
    case script(String)
    case failed(message: String, code: String)
    case timeout

    public var errorDescription: String? {
        switch self {
        case .timeout: return "插件超时了，稍后再试。"
        case .script(let message): return message
        case .failed(let message, _): return message
        }
    }
}

public final class PluginMemory: @unchecked Sendable {
    private let lock = NSLock()
    public var storage: [String: String]
    public var settings: [String: String]
    public var phrases: [String: String]
    public var onStorage: (@Sendable ([String: String]) -> Void)?

    public init(
        storage: [String: String] = [:],
        settings: [String: String] = [:],
        phrases: [String: String] = [:]
    ) {
        self.storage = storage
        self.settings = settings
        self.phrases = phrases
    }

    func getStorage(_ key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    func setSetting(_ key: String, _ value: String) {
        lock.lock()
        settings[key] = value
        lock.unlock()
    }

    func setStorage(_ key: String, _ value: String) {
        lock.lock()
        storage[key] = value
        let snapshot = storage
        lock.unlock()
        onStorage?(snapshot)
    }

    func removeStorage(_ key: String) {
        lock.lock()
        storage.removeValue(forKey: key)
        let snapshot = storage
        lock.unlock()
        onStorage?(snapshot)
    }

    func setting(_ key: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        return settings[key] ?? ""
    }

    func phrase(_ key: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        return phrases[key] ?? key
    }
}

public struct PluginWebSignIn: Sendable, Equatable {
    public var url: String
    public var cookiesOf: String
    public var until: [String]
    public var userAgent: String?

    public init(url: String, cookiesOf: String, until: [String], userAgent: String?) {
        self.url = url
        self.cookiesOf = cookiesOf
        self.until = until
        self.userAgent = userAgent
    }
}

public enum PluginNetwork {
    public static func allows(_ url: URL, rules: [String]) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return false }
        guard let host = url.host?.lowercased(), !host.isEmpty else { return false }
        if rules.contains("*") { return true }
        for rule in rules {
            let item = rule.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if item.isEmpty { continue }
            if item.hasPrefix("*.") {
                let bare = String(item.dropFirst(2))
                if host == bare || host.hasSuffix("." + bare) { return true }
            } else if host == item {
                return true
            }
        }
        return false
    }
}

enum PluginCrypto {
    static func md5(_ text: String) -> String {
        let data = Data(text.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_MD5(buffer.baseAddress, CC_LONG(buffer.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func aesECB(key: String, text: String) -> Result<String, PluginCallError> {
        let keyBytes = Array(key.utf8)
        guard keyBytes.count == 16 || keyBytes.count == 24 || keyBytes.count == 32 else {
            return .failure(.failed(message: "AES 密钥长度不对", code: "unsupported"))
        }
        let plain = Array(text.utf8)
        var output = [UInt8](repeating: 0, count: plain.count + kCCBlockSizeAES128)
        var moved: size_t = 0
        let status = CCCrypt(
            CCOperation(kCCEncrypt),
            CCAlgorithm(kCCAlgorithmAES),
            CCOptions(kCCOptionPKCS7Padding | kCCOptionECBMode),
            keyBytes,
            keyBytes.count,
            nil,
            plain,
            plain.count,
            &output,
            output.count,
            &moved
        )
        guard status == kCCSuccess else {
            return .failure(.failed(message: "AES 加密失败", code: "unsupported"))
        }
        let hex = output.prefix(moved).map { String(format: "%02x", $0) }.joined()
        return .success(hex)
    }
}

enum PluginAssets {
    static func text(named name: String, subdirectory: String? = nil) -> String {
        let candidates = [
            Bundle.module.url(forResource: name, withExtension: "js", subdirectory: subdirectory),
            Bundle.module.url(forResource: name, withExtension: "js"),
            Bundle.module.url(forResource: name, withExtension: "js", subdirectory: "Resources"),
            Bundle.module.url(forResource: name, withExtension: "js", subdirectory: subdirectory.map { "Resources/\($0)" })
        ]
        for url in candidates.compactMap({ $0 }) {
            if let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty { return text }
        }
        return ""
    }

    static func vendors() -> [String: String] {
        let names = ["crypto-js", "dayjs", "he", "qs", "big-integer"]
        var files: [String: String] = [:]
        for name in names {
            let source = text(named: name, subdirectory: "vendor")
            if !source.isEmpty { files[name] = source }
        }
        return files
    }
}

enum PluginLinker {
    static func bundle(files: [String: String], entry: String) throws -> String {
        let linker = PluginAssets.text(named: "Linker")
        guard !linker.isEmpty else { throw PluginCallError.script("插件打包器没有放进 App（\(PluginEngine.bundleListing())）") }
        let context = JSContext()!
        context.exceptionHandler = { _, value in
            context.setObject(value?.toString() ?? "打包失败", forKeyedSubscript: "__sxLinkError" as NSString)
        }
        context.exception = nil
        context.evaluateScript(linker)
        if let error = context.objectForKeyedSubscript("__sxLinkError")?.toString(), !error.isEmpty {
            throw PluginCallError.script(error)
        }
        let object = JSValue(newObjectIn: context)!
        for (path, source) in files {
            object.setObject(source, forKeyedSubscript: path as NSString)
        }
        context.exception = nil
        guard let function = context.objectForKeyedSubscript("sxBundle"),
              let result = function.call(withArguments: [object, entry]),
              !result.isUndefined, !result.isNull else {
            let error = context.exception?.toString() ?? context.objectForKeyedSubscript("__sxLinkError")?.toString() ?? "打包失败"
            throw PluginCallError.script(error)
        }
        if let error = context.exception?.toString() {
            throw PluginCallError.script(error)
        }
        return result.toString()
    }
}

public final class PluginEngine: @unchecked Sendable {
    public let memory: PluginMemory
    public var webSignInHandler: (@Sendable (PluginWebSignIn) async throws -> String)?
    public var signInPromptHandler: (@Sendable (String) -> Void)?
    public var openURLHandler: (@Sendable (String) -> Void)?

    private let network: [String]
    private let vendors: [String: String]
    private let thread = PluginLoop()
    private var context: JSContext?
    private var session: URLSession!
    private var nextBodyLimit = 4_000_000

    public init(
        files: [String: String],
        entry: String,
        network: [String],
        directory: String,
        memory: PluginMemory,
        vendors: [String: String]? = nil,
        urlProtocolClass: AnyClass? = nil
    ) throws {
        self.memory = memory
        self.network = network
        self.vendors = vendors ?? PluginAssets.vendors()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 40
        configuration.httpMaximumConnectionsPerHost = 6
        if let urlProtocolClass {
            configuration.protocolClasses = [urlProtocolClass]
        }
        self.session = URLSession(configuration: configuration)
        try bootstrap(files: files, entry: entry, directory: directory)
    }

    public func exports() -> [String] {
        var names: [String] = []
        let ready = DispatchSemaphore(value: 0)
        thread.perform { [weak self] in
            guard let self, let context = self.context else { ready.signal(); return }
            let value = context.evaluateScript("""
            Object.keys(__sxExports || {}).filter(function(name){ return typeof __sxExports[name] === "function"; })
            """)
            names = value?.toArray() as? [String] ?? []
            ready.signal()
        }
        ready.wait()
        return names.sorted()
    }

    public func call(_ name: String, json: String? = nil, timeout: TimeInterval = 30) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            thread.perform { [weak self] in
                guard let self else {
                    continuation.resume(throwing: PluginCallError.script("插件已经卸掉了"))
                    return
                }
                do {
                    let result = try self.callOnThread(name: name, json: json, timeout: timeout)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func bootstrap(files: [String: String], entry: String, directory: String) throws {
        let program = try Self.program(files: files, entry: entry)
        var setupError: Error?
        let ready = DispatchSemaphore(value: 0)
        thread.perform { [self] in
            do {
                try self.install(program: program, directory: directory)
            } catch {
                setupError = error
            }
            ready.signal()
        }
        ready.wait()
        if let setupError { throw setupError }
    }

    private static func program(files: [String: String], entry: String) throws -> String {
        let source = files[entry] ?? ""
        let looksLikeModule = source.contains("module.exports")
            && !source.contains("export ")
            && !source.contains("\nimport ")
            && !source.hasPrefix("import ")
        if looksLikeModule {
            return "__sxCommonJS(\(jsString(source)));"
        }
        return try PluginLinker.bundle(files: files, entry: entry)
    }

    private func install(program: String, directory: String) throws {
        guard let context = JSContext() else { throw PluginCallError.script("JavaScript 引擎没有起来") }
        self.context = context
        var scriptError: String?
        context.exceptionHandler = { _, value in
            scriptError = value?.toString()
        }
        let bridge = PluginBridge(engine: self)
        context.setObject(bridge.storageGet, forKeyedSubscript: "__sxStorageGet" as NSString)
        context.setObject(bridge.storageSet, forKeyedSubscript: "__sxStorageSet" as NSString)
        context.setObject(bridge.storageRemove, forKeyedSubscript: "__sxStorageRemove" as NSString)
        context.setObject(bridge.setting, forKeyedSubscript: "__sxSetting" as NSString)
        context.setObject(bridge.translate, forKeyedSubscript: "__sxTranslate" as NSString)
        context.setObject(bridge.md5, forKeyedSubscript: "__sxMD5" as NSString)
        context.setObject(bridge.aes, forKeyedSubscript: "__sxAES" as NSString)
        context.setObject(bridge.open, forKeyedSubscript: "__sxOpen" as NSString)
        context.setObject(bridge.log, forKeyedSubscript: "__sxLog" as NSString)
        context.setObject(bridge.signIn, forKeyedSubscript: "__sxSignIn" as NSString)
        context.setObject(bridge.webSignIn, forKeyedSubscript: "__sxWebSignIn" as NSString)
        context.setObject(bridge.fetch, forKeyedSubscript: "__sxFetch" as NSString)
        context.setObject(bridge.schedule, forKeyedSubscript: "__sxSchedule" as NSString)
        context.setObject(bridge.builtin, forKeyedSubscript: "__sxBuiltin" as NSString)
        context.evaluateScript("var __sxDir = \(Self.jsString(directory));")
        let prelude = PluginAssets.text(named: "PluginPrelude")
        guard !prelude.isEmpty else {
            throw PluginCallError.script("插件运行时没有放进 App（\(Self.bundleListing())）")
        }
        context.evaluateScript(prelude)
        if let scriptError { throw PluginCallError.script(scriptError) }
        context.evaluateScript(program)
        if let scriptError { throw PluginCallError.script(scriptError) }
        let exported = context.evaluateScript("typeof __sxExports")?.toString()
        if exported != "object" { throw PluginCallError.script("插件没有导出函数") }
    }

    private func callOnThread(name: String, json: String?, timeout: TimeInterval) throws -> String {
        guard let context else { throw PluginCallError.script("插件还没有装好") }
        context.exception = nil
        let argument = json.map(Self.jsString) ?? "null"
        context.evaluateScript("__sxInvoke(\(Self.jsString(name)), \(argument));")
        if let exception = context.exception?.toString() {
            context.exception = nil
            throw PluginCallError.script(exception)
        }
        let deadline = Date().addingTimeInterval(timeout)
        while context.objectForKeyedSubscript("__sxDone")?.toBool() != true {
            if Date() >= deadline {
                context.evaluateScript("__sxGen++;")
                throw PluginCallError.timeout
            }
            context.evaluateScript("void 0")
            if context.objectForKeyedSubscript("__sxDone")?.toBool() == true { break }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        if let errorValue = context.objectForKeyedSubscript("__sxError"), errorValue.isString, let text = errorValue.toString() {
            throw Self.pluginError(from: text)
        }
        return context.objectForKeyedSubscript("__sxResult")?.toString() ?? "null"
    }

    private static func pluginError(from text: String) -> PluginCallError {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failed(message: text, code: "")
        }
        let message = object["message"] as? String ?? text
        let code = object["code"] as? String ?? ""
        return .failed(message: message, code: code)
    }

    fileprivate func startFetch(id: Int, json: String) {
        guard let context else { return }
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let urlString = object["url"] as? String,
              let url = URL(string: urlString) else {
            finishFetch(id: id, status: 0, headers: [:], body: Data(), error: "地址不对")
            return
        }
        guard PluginNetwork.allows(url, rules: network) else {
            finishFetch(id: id, status: 0, headers: [:], body: Data(), error: "这个插件的网络权限不包括 \(url.host ?? urlString)")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = (object["method"] as? String) ?? "GET"
        if let headers = object["headers"] as? [String: String] {
            for (key, value) in headers where !key.isEmpty { request.setValue(value, forHTTPHeaderField: key) }
        }
        if let body = object["body"] as? String, request.httpMethod != "GET", request.httpMethod != "HEAD" {
            request.httpBody = Data(body.utf8)
        }
        let task = session.dataTask(with: request) { [weak self] body, response, error in
            guard let self else { return }
            self.thread.perform {
                if let error {
                    self.finishFetch(id: id, status: 0, headers: [:], body: Data(), error: error.localizedDescription)
                    return
                }
                let http = response as? HTTPURLResponse
                var headers: [String: String] = [:]
                http?.allHeaderFields.forEach { key, value in
                    headers[String(describing: key)] = String(describing: value)
                }
                let payload = body ?? Data()
                if payload.count > self.nextBodyLimit {
                    self.finishFetch(id: id, status: http?.statusCode ?? 0, headers: headers, body: Data(), error: "响应太大")
                    return
                }
                self.finishFetch(id: id, status: http?.statusCode ?? 0, headers: headers, body: payload, error: nil)
            }
        }
        task.resume()
    }

    private func finishFetch(id: Int, status: Int, headers: [String: String], body: Data, error: String?) {
        guard let context else { return }
        let headerJSON = (try? String(data: JSONSerialization.data(withJSONObject: headers), encoding: .utf8)) ?? "{}"
        let base64 = body.base64EncodedString()
        let errorJS = error.map(Self.jsString) ?? "null"
        context.evaluateScript("__sxFinish(\(id), \(status), \(Self.jsString(headerJSON)), \(Self.jsString(base64)), \(errorJS));")
    }

    fileprivate func startWebSignIn(id: Int, json: String) {
        let handler = webSignInHandler
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let url = object["url"] as? String else {
            finishWeb(id: id, cookie: nil, error: "网页登录缺少地址")
            return
        }
        let request = PluginWebSignIn(
            url: url,
            cookiesOf: object["cookiesOf"] as? String ?? url,
            until: object["until"] as? [String] ?? [],
            userAgent: object["userAgent"] as? String
        )
        guard let handler else {
            finishWeb(id: id, cookie: nil, error: "这个插件要打开网页登录，声匣这次没有弹出窗口")
            return
        }
        Task {
            do {
                let cookie = try await handler(request)
                self.thread.perform { self.finishWeb(id: id, cookie: cookie, error: nil) }
            } catch {
                self.thread.perform { self.finishWeb(id: id, cookie: nil, error: error.localizedDescription) }
            }
        }
    }

    private func finishWeb(id: Int, cookie: String?, error: String?) {
        guard let context else { return }
        if let cookie {
            context.evaluateScript("""
            (function(){
              var pending = __sxReqs[\(id)];
              delete __sxReqs[\(id)];
              if (pending) pending.resolve(\(Self.jsString(cookie)));
            })();
            """)
        } else {
            let message = Self.jsString(error ?? "网页登录没有完成")
            context.evaluateScript("""
            (function(){
              var pending = __sxReqs[\(id)];
              delete __sxReqs[\(id)];
              if (pending) pending.reject(Object.assign(new Error(\(message)), { code: "signIn" }));
            })();
            """)
        }
    }

    fileprivate static func bundleListing() -> String {
        (try? FileManager.default.subpathsOfDirectory(atPath: Bundle.module.bundlePath))?.prefix(24).joined(separator: ", ")
            ?? Bundle.module.bundlePath
    }

    fileprivate static func jsString(_ text: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [text]),
              let wrapped = String(data: data, encoding: .utf8),
              wrapped.count >= 2 else { return "\"\"" }
        return String(wrapped.dropFirst().dropLast())
    }
}

private final class PluginBridge {
    weak var engine: PluginEngine?
    let storageGet: @convention(block) (String) -> String?
    let storageSet: @convention(block) (String, String) -> Void
    let storageRemove: @convention(block) (String) -> Void
    let setting: @convention(block) (String) -> String
    let translate: @convention(block) (String) -> String
    let md5: @convention(block) (String) -> String
    let aes: @convention(block) (String, String) -> String
    let open: @convention(block) (String) -> Void
    let log: @convention(block) (String, String) -> Void
    let signIn: @convention(block) (String) -> Void
    let webSignIn: @convention(block) (Int, String) -> Void
    let fetch: @convention(block) (Int, String) -> Void
    let schedule: @convention(block) (Int, Double) -> Void
    let builtin: @convention(block) (String) -> String?

    init(engine: PluginEngine) {
        self.engine = engine
        let memory = engine.memory
        let vendors = engine.vendors
        storageGet = { memory.getStorage($0) }
        storageSet = { memory.setStorage($0, $1) }
        storageRemove = { memory.removeStorage($0) }
        setting = { memory.setting($0) }
        translate = { memory.phrase($0) }
        md5 = { PluginCrypto.md5($0) }
        aes = { key, text in
            switch PluginCrypto.aesECB(key: key, text: text) {
            case .success(let hex): return hex
            case .failure(let error):
                if case .failed(let message, _) = error { return "ERR \(message)" }
                return "ERR AES"
            }
        }
        open = { [weak engine] url in
            engine?.openURLHandler?(url)
        }
        log = { _, _ in }
        signIn = { [weak engine] json in
            engine?.signInPromptHandler?(json)
        }
        webSignIn = { [weak engine] id, json in
            engine?.startWebSignIn(id: id, json: json)
        }
        fetch = { [weak engine] id, json in
            engine?.startFetch(id: id, json: json)
        }
        schedule = { [weak engine] id, ms in
            let delay = max(0, ms) / 1000
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay) {
                engine?.thread.perform {
                    engine?.context?.evaluateScript("__sxFire(\(id));")
                }
            }
        }
        builtin = { vendors[$0] }
    }
}

private final class PluginLoop: Thread {
    private let started = DispatchSemaphore(value: 0)
    fileprivate var loop: CFRunLoop?

    override init() {
        super.init()
        name = "shengxia.plugin"
        qualityOfService = .userInitiated
        start()
    }

    override func main() {
        loop = CFRunLoopGetCurrent()
        started.signal()
        while !isCancelled {
            _ = CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.5, false)
        }
    }

    func perform(_ block: @escaping () -> Void) {
        if loop != nil, CFRunLoopGetCurrent() == loop {
            block()
            return
        }
        started.wait()
        guard let loop else { return }
        CFRunLoopPerformBlock(loop, kCFRunLoopDefaultMode, block)
        CFRunLoopWakeUp(loop)
    }

    deinit {
        cancel()
        if let loop {
            CFRunLoopStop(loop)
            CFRunLoopWakeUp(loop)
        }
    }
}
