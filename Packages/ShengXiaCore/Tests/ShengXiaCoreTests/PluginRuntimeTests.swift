import XCTest
import ShengXiaCore

final class PluginRuntimeTests: XCTestCase {
    func testZipReadsPluginFiles() throws {
        let data = Data(base64Encoded: "UEsDBBQAAAAIAOiDbV33X2TwPQAAAEIAAAALAAAAcGx1Z2luLmpzb26rVspMUbJSSknNzVfSUcpLzE0F8p4v2fVkXzeQX5ZaVJyZnwcUMtQz0DMAiuQmZoK4mXkpqRV6WcVKtVwAUEsDBBQAAAAIAOiDbV3+3BaVUQAAAFQAAAAIAAAAaW5kZXguanMFwUEKgCAQBdB9p/g7CyJoa0eJFmITSTTmOEIh3r336H2iKFz+2OMo7DVERiYn/uzTUCGkRRgVKs5f2WKtCLuFmc0IdjdZpCkVkg9tQ1vQuh9QSwECFAMUAAAACADog21d919k8D0AAABCAAAACwAAAAAAAAAAAAAAgAEAAAAAcGx1Z2luLmpzb25QSwECFAMUAAAACADog21d/twWlVEAAABUAAAACAAAAAAAAAAAAAAAgAFmAAAAaW5kZXguanNQSwUGAAAAAAIAAgBvAAAA3QAAAAAA")!
        let files = try PluginZip.extract(data)
        let source = String(data: files["index.js"] ?? Data(), encoding: .utf8)
        XCTAssertTrue(source?.contains("export async function search") == true)
        XCTAssertTrue(String(data: files["plugin.json"] ?? Data(), encoding: .utf8)?.contains("\"demo\"") == true)
    }

    func testNetworkAllowlistMatchesSuffix() {
        let url = URL(string: "https://aqqmusic.tc.qq.com/a.mp3")!
        XCTAssertTrue(PluginNetwork.allows(url, rules: ["*.qq.com"]))
        XCTAssertFalse(PluginNetwork.allows(url, rules: ["music.163.com"]))
        XCTAssertFalse(PluginNetwork.allows(URL(string: "file:///tmp/a.js")!, rules: ["*"]))
        XCTAssertTrue(PluginNetwork.allows(url, rules: ["*"]))
    }

    func testModuleExportsSearchAndCrypto() async throws {
        let engine = try makeEngine(files: [
            "index.js": """
            export async function search(query) {
              return {
                tracks: [{ id: "1", name: query.query }],
                md5: host.crypto.md5("abc"),
                aes: host.crypto.aesEcbEncrypt("e82ckenh8dichen8", "hello-声匣")
              };
            }
            """
        ], network: [])
        let names = engine.exports()
        XCTAssertEqual(names, ["search"])
        let json = try await engine.call("search", json: #"{"query":"晴天"}"#)
        XCTAssertTrue(json.contains("晴天"))
        XCTAssertTrue(json.contains("900150983cd24fb0d6963f7d28e17f72"))
        XCTAssertTrue(json.contains("b6505931a6316f104bf4a33957a54e85"))
    }

    func testRelativeImport() async throws {
        let engine = try makeEngine(files: [
            "util.js": "export function add(a, b) { return a + b; }\n",
            "index.js": """
            import { add } from "./util.js";
            export function search() { return { tracks: [{ id: "1", name: String(add(2, 3)) }] }; }
            """
        ], network: [])
        let json = try await engine.call("search")
        XCTAssertTrue(json.contains("\"name\":\"5\"") || json.contains("\"name\": \"5\""))
    }

    func testFetchAndAxiosStayInsideThePlugin() async throws {
        PluginTestProtocol.body = "{\"ok\":7}"
        let fetchEngine = try makeEngine(files: [
            "index.js": """
            export async function search() {
              const response = await fetch("https://example.com/song");
              const data = await response.json();
              return { tracks: [{ id: "1", name: String(data.ok) }] };
            }
            """
        ], network: ["example.com"], urlProtocol: PluginTestProtocol.self)
        let fetched = try await fetchEngine.call("search")
        XCTAssertTrue(fetched.contains("7"))

        let axiosEngine = try makeEngine(files: [
            "index.js": """
            const axios = require("axios");
            module.exports.search = async function () {
              const response = await axios.get("https://example.com/song");
              return { tracks: [{ id: "1", name: String(response.data.ok) }] };
            };
            """
        ], network: ["example.com"], urlProtocol: PluginTestProtocol.self)
        let viaAxios = try await axiosEngine.call("search")
        XCTAssertTrue(viaAxios.contains("7"))

        let blocked = try makeEngine(files: [
            "index.js": """
            export async function search() {
              await fetch("https://evil.example/x");
              return { tracks: [] };
            }
            """
        ], network: ["example.com"], urlProtocol: PluginTestProtocol.self)
        do {
            _ = try await blocked.call("search")
            XCTFail("越权请求应该失败")
        } catch let error as PluginCallError {
            guard case .failed(let message, _) = error else {
                XCTFail("意外错误 \(error)")
                return
            }
            XCTAssertTrue(message.contains("网络权限"))
        }
    }

    func testTimeoutDoesNotBreakTheNextPlugin() async throws {
        let slow = try makeEngine(files: [
            "index.js": """
            export async function search() {
              await new Promise(function (resolve) { setTimeout(resolve, 2000); });
              return { tracks: [] };
            }
            export function ping() { return { tracks: [{ id: "1", name: "还在" }] }; }
            """
        ], network: [])
        do {
            _ = try await slow.call("search", timeout: 0.35)
            XCTFail("应该超时")
        } catch let error as PluginCallError {
            XCTAssertEqual(error, .timeout)
        }
        let again = try await slow.call("ping", timeout: 2)
        XCTAssertTrue(again.contains("还在"))

        let other = try makeEngine(files: [
            "index.js": "export function search() { return { tracks: [{ id: \"1\", name: \"另一只\" }] }; }\n"
        ], network: [])
        let isolated = try await other.call("search")
        XCTAssertTrue(isolated.contains("另一只"))
    }

    func testCryptoJSLibraryLoads() async throws {
        let engine = try makeEngine(files: [
            "index.js": """
            const CryptoJS = require("crypto-js");
            const dayjs = require("dayjs");
            module.exports.search = function () {
              return { md5: CryptoJS.MD5("abc").toString(), day: typeof dayjs };
            };
            """
        ], network: [])
        let json = try await engine.call("search")
        XCTAssertTrue(json.contains("900150983cd24fb0d6963f7d28e17f72"))
        XCTAssertTrue(json.contains("function"))
    }

    private func makeEngine(
        files: [String: String],
        network: [String],
        urlProtocol: AnyClass? = nil
    ) throws -> PluginEngine {
        try PluginEngine(
            files: files,
            entry: "index.js",
            network: network,
            directory: "/tmp/shengxia-plugin",
            memory: PluginMemory(),
            urlProtocolClass: urlProtocol
        )
    }
}

private final class PluginTestProtocol: URLProtocol, @unchecked Sendable {
    static var body = "{\"ok\":1}"

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com/")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
