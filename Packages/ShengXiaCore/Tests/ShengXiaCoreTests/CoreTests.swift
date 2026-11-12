import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ShengXiaCore

final class ScriptedHTTPClient: HTTPClient {
    var handlers: [(URLRequest) -> HTTPResponse] = []

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        guard !handlers.isEmpty else {
            XCTFail("没有预设响应：\(request.url?.absoluteString ?? "")")
            throw ResolveError.network("没有预设响应")
        }
        return handlers.removeFirst()(request)
    }
}

final class LinkAndFileTests: XCTestCase {
    func testExtractsBilibiliAndDouyinLinks() {
        let share = "7.43 复制打开抖音，看看【示例】https://v.douyin.com/J4IQiholWbo/ 复制此链接"
        let urls = LinkParser.extractURLs(from: share)
        XCTAssertEqual(urls.map(\.host), ["v.douyin.com"])
        XCTAssertEqual(LinkParser.douyinID(in: URL(string: "https://www.douyin.com/video/7624728488368732900")!), "7624728488368732900")
        XCTAssertEqual(
            LinkParser.douyinID(in: URL(string: "https://www.douyin.com/jingxuan?modal_id=7624728488368732900")!),
            "7624728488368732900"
        )
        XCTAssertEqual(LinkParser.firstBVID(in: "https://www.bilibili.com/video/BV1hrW367Emp?p=2"), "BV1hrW367Emp")
        XCTAssertEqual(LinkParser.identity(from: URL(string: "https://b23.tv/BV1hrW367Emp")!)?.bvid, "BV1hrW367Emp")
        XCTAssertEqual(LinkParser.identity(from: URL(string: "https://www.bilibili.com/video/av2")!)?.aid, 2)
        XCTAssertEqual(LinkParser.bilibiliIdentity(in: "BV1xx411c7mD")?.bvid, "BV1xx411c7mD")
        XCTAssertEqual(LinkParser.pageNumber(from: URL(string: "https://www.bilibili.com/video/BV1hrW367Emp?p=2")!), 2)
    }

    func testFilenameSanitizer() {
        XCTAssertEqual(FileNameSanitizer.filename(title: "你好/世界:测试", extension: "m4a"), "你好 世界 测试.m4a")
        XCTAssertEqual(FileNameSanitizer.filename(title: "   ", extension: ".mp3"), "未命名音轨.mp3")
        XCTAssertFalse(FileNameSanitizer.sanitizeBase(String(repeating: "音", count: 80)).count > 60)
    }

    func testMediaSniffer() {
        var mp4 = Data(repeating: 0, count: 16)
        mp4.replaceSubrange(4..<8, with: Data("ftyp".utf8))
        XCTAssertTrue(MediaSniffer.looksLikeMedia(mp4))
        XCTAssertTrue(MediaSniffer.looksLikeMedia(Data("ID3.........".utf8)))
        XCTAssertTrue(MediaSniffer.looksLikeMedia(Data("fLaC........".utf8)))
        XCTAssertFalse(MediaSniffer.looksLikeMedia(Data("<html>not media</html>".utf8)))
        XCTAssertFalse(MediaSniffer.looksLikeMedia(Data("{\"code\":0}".utf8)))
    }
}

final class BilibiliParserTests: XCTestCase {
    func testSelectsHighestAACAndSkipsDolby() throws {
        let json = """
        {"code":0,"message":"OK","data":{"format":"flv720","dash":{"audio":[
          {"id":30216,"bandwidth":1000,"mimeType":"audio/mp4","codecs":"mp4a.40.2","baseUrl":"https://cdn.example/low.m4s","backupUrl":[]},
          {"id":30280,"bandwidth":5000,"mimeType":"audio/mp4","codecs":"mp4a.40.2","baseUrl":"https://cdn.example/hi.m4s","backupUrl":["https://cdn.example/hi-b.m4s"]},
          {"id":30250,"bandwidth":9000,"mimeType":"audio/mp4","codecs":"ec-3","baseUrl":"https://cdn.example/dolby.m4s"}
        ],"flac":null}}}
        """
        let pick = try BilibiliParser.parsePlay(Data(json.utf8))
        XCTAssertEqual(pick.kind, .audio)
        XCTAssertEqual(pick.fileExtension, "m4a")
        XCTAssertEqual(pick.formatLabel, "M4A（AAC）")
        XCTAssertEqual(pick.urls.map(\.absoluteString), ["https://cdn.example/hi.m4s", "https://cdn.example/hi-b.m4s"])
    }

    func testPrefersFLACWhenPresent() throws {
        let json = """
        {"code":0,"data":{"dash":{"audio":[
          {"bandwidth":4000,"mimeType":"audio/mp4","codecs":"mp4a.40.2","baseUrl":"https://cdn.example/a.m4s"}
        ],"flac":{"audio":{"bandwidth":20000,"mimeType":"audio/flac","codecs":"flac","baseUrl":"https://cdn.example/a.flac"}}}}}
        """
        let pick = try BilibiliParser.parsePlay(Data(json.utf8))
        XCTAssertEqual(pick.fileExtension, "flac")
        XCTAssertEqual(pick.formatLabel, "FLAC")
        XCTAssertEqual(pick.urls.first?.absoluteString, "https://cdn.example/a.flac")
    }

    func testMissingVideoAndBannedAndFLV() {
        XCTAssertThrowsError(try BilibiliParser.parseView(Data(#"{"code":-404,"message":"啥都木有"}"#.utf8))) { error in
            XCTAssertEqual(error as? ResolveError, .bilibiliNotFound)
        }
        XCTAssertThrowsError(try BilibiliParser.parseView(Data(#"{"code":-412,"message":"request was banned"}"#.utf8))) { error in
            XCTAssertEqual(error as? ResolveError, .bilibiliBanned)
        }
        XCTAssertThrowsError(try BilibiliParser.parsePlay(Data(#"{"code":0,"data":{"format":"flv480","durl":[{"url":"https://cdn.example/a.flv"}]}}"#.utf8))) { error in
            XCTAssertEqual(error as? ResolveError, .bilibiliFLVOnly)
        }
        XCTAssertEqual(ResolveError.bilibiliVipBlocked.errorDescription, "该内容需要大会员，声匣不会绕过付费墙")
    }

    func testSelectsRequestedPage() throws {
        let json = """
        {"code":0,"data":{"bvid":"BV1hrW367Emp","aid":1,"cid":11,"title":"辽阔","pic":"http://i1.hdslb.com/a.jpg","duration":42,"owner":{"name":"小王"},"pages":[
          {"page":1,"cid":11,"part":"一"},
          {"page":2,"cid":22,"part":"二"}
        ]}}
        """
        let video = try BilibiliParser.parseView(Data(json.utf8))
        XCTAssertEqual(video.cover?.scheme, "https")
        let page = try BilibiliParser.selectPage(video, requested: 2)
        XCTAssertEqual(page.cid, 22)
        XCTAssertEqual(BilibiliParser.displayTitle(video, page: page), "辽阔 · 二")
    }

    func testResolveShortLinkAndBareBV() async throws {
        let client = ScriptedHTTPClient()
        client.handlers = [
            { _ in HTTPResponse(statusCode: 200, finalURL: URL(string: "https://www.bilibili.com/video/BV1hrW367Emp?p=2"), data: Data()) },
            { _ in HTTPResponse(statusCode: 200, finalURL: nil, data: Data(#"{"code":0,"data":{"b_3":"buvid-value","b_4":"buvid-four"}}"#.utf8)) },
            { request in
                XCTAssertTrue(request.allHTTPHeaderFields?["Cookie"]?.contains("buvid3=buvid-value") == true)
                return HTTPResponse(statusCode: 200, finalURL: request.url, data: Data("""
                {"code":0,"data":{"bvid":"BV1hrW367Emp","aid":9,"cid":11,"title":"辽阔的土地","pic":"https://i1.hdslb.com/a.jpg","duration":42,"owner":{"name":"小王"},"pages":[{"page":1,"cid":11,"part":"一"},{"page":2,"cid":22,"part":"二"}]}}
                """.utf8))
            },
            { _ in HTTPResponse(statusCode: 200, finalURL: nil, data: Data("""
                {"code":0,"data":{"dash":{"audio":[{"bandwidth":164299,"mimeType":"audio/mp4","codecs":"mp4a.40.2","baseUrl":"https://cdn.example/hi.m4s","backupUrl":["https://cdn.example/backup.m4s"]}]}}}
                """.utf8)) }
        ]
        let step = try await BilibiliSource().resolve("https://b23.tv/abcXYZ", client: client)
        guard case .ready(let media) = step else {
            return XCTFail("应当直接得到音频")
        }
        XCTAssertEqual(media.title, "辽阔的土地 · 二")
        XCTAssertEqual(media.author, "小王")
        XCTAssertEqual(media.sourceName, "哔哩哔哩")
        XCTAssertEqual(media.stream.kind, .audio)
        XCTAssertEqual(media.stream.formatLabel, "M4A（AAC）")
        XCTAssertEqual(media.stream.urls.first?.absoluteString, "https://cdn.example/hi.m4s")
        XCTAssertEqual(media.stream.headers["Referer"], "https://www.bilibili.com/video/BV1hrW367Emp/")
        XCTAssertTrue(client.handlers.isEmpty)
    }
}

final class DouyinParserTests: XCTestCase {
    func testCurrentSharePageNeedsWebCapture() {
        let html = """
        <html><script>window._ROUTER_DATA = {"loaderData":{"video_(id)/page":{"itemId":"7634107283886148915","lastPath":"7634107283886148915"}}};</script></html>
        """
        let parsed = DouyinDocumentParser.parse(html)
        guard case .needWeb(let id) = parsed else { return XCTFail("\(parsed)") }
        XCTAssertEqual(id, "7634107283886148915")
    }

    func testLegacyPlayURLIsUnwrapped() throws {
        let html = """
        <script>window._ROUTER_DATA = {"loaderData":{"video_(id)/page":{"videoInfoRes":{"item_list":[{
          "aweme_id":"7624728488368732900","desc":"示例标题","author":{"nickname":"示例作者"},
          "video":{"duration":15000,"cover":{"url_list":["http://example.com/c.jpg"]},
                   "play_addr":{"url_list":["https://example.com/aweme/v1/playwm/?video_id=abc"]}}
        }]}}}};</script>
        """
        guard case .media(let item) = DouyinDocumentParser.parse(html) else {
            return XCTFail("应当解析出视频")
        }
        XCTAssertEqual(item.title, "示例标题")
        XCTAssertEqual(item.author, "示例作者")
        XCTAssertEqual(item.duration, 15)
        XCTAssertEqual(item.coverURL?.scheme, "https")
        XCTAssertEqual(item.playURLs.first?.absoluteString, "https://example.com/aweme/v1/play/?video_id=abc")
        let media = try DouyinCaptureAssembler.assemble(
            detailBodies: [html],
            mediaURLs: [],
            expectedID: "7624728488368732900",
            pageURL: "https://www.douyin.com/video/7624728488368732900"
        )
        XCTAssertEqual(media.title, "示例标题")
        XCTAssertEqual(media.stream.kind, .video)
        XCTAssertEqual(media.stream.fileExtension, "mp4")
    }

    func testImagePostAndMismatchedID() {
        let images = #"{"aweme_id":"7624728488368732900","desc":"图","images":[{"url_list":["https://example.com/a.jpg"]}]}"#
        XCTAssertEqual(DouyinDocumentParser.parse(images), .imagePost)
        XCTAssertThrowsError(try DouyinCaptureAssembler.assemble(
            detailBodies: [images],
            mediaURLs: [],
            expectedID: "7624728488368732900",
            pageURL: "https://www.douyin.com/video/7624728488368732900"
        )) { error in
            XCTAssertEqual(error as? ResolveError, .douyinImagePost)
        }
        XCTAssertEqual(ResolveError.douyinResolveFailed.errorDescription, "抖音解析失败，可能是抖音更新了校验")
    }

    func testURLRankingPrefersUnsignedProgressive() {
        let urls = [
            URL(string: "https://www.douyinstatic.com/uuu_265.mp4")!,
            URL(string: "https://v3.douyinvod.com/obj/media-audio-und.mp4")!,
            URL(string: "https://v9.zjcdn.com/obj/video.mp4?signature=abc&tk=webid")!,
            URL(string: "https://v9.zjcdn.com/obj/clean.mp4")!
        ]
        let ranked = DouyinURLPicker.rank(urls)
        XCTAssertEqual(ranked.first?.url.absoluteString, "https://v9.zjcdn.com/obj/clean.mp4")
        XCTAssertEqual(ranked.first?.kind, .video)
        XCTAssertTrue(ranked.contains { $0.kind == .audio })
        XCTAssertFalse(ranked.contains { $0.url.host == "www.douyinstatic.com" })
    }

    func testShareTextResolvesToWebCaptureWhenPageHasNoMedia() async throws {
        let html = """
        <html>window._ROUTER_DATA = {"loaderData":{"video_(id)/page":{"itemId":"7624728488368732900"}}};</html>
        """
        let client = ScriptedHTTPClient()
        client.handlers = [
            { _ in
                HTTPResponse(
                    statusCode: 200,
                    finalURL: URL(string: "https://www.iesdouyin.com/share/video/7624728488368732900/"),
                    data: Data(html.utf8)
                )
            },
            { _ in HTTPResponse(statusCode: 200, finalURL: nil, data: Data()) },
            { _ in HTTPResponse(statusCode: 200, finalURL: nil, data: Data(#"{"status_code":0,"aweme_details":null}"#.utf8)) }
        ]
        let text = "看看这个 https://v.douyin.com/J4IQiholWbo/ 复制打开抖音"
        let step = try await DouyinSource().resolve(text, client: client)
        guard case .webCapture(let request) = step else { return XCTFail("\(step)") }
        XCTAssertEqual(request.awemeID, "7624728488368732900")
        XCTAssertEqual(request.pageURL.absoluteString, "https://www.douyin.com/video/7624728488368732900")
        XCTAssertEqual(request.sourceName, "抖音")
    }

    func testAssemblerUsesCapturedCDNWhenDetailIsEmpty() throws {
        let media = try DouyinCaptureAssembler.assemble(
            detailBodies: ["{}"],
            mediaURLs: [URL(string: "https://v5-dy-o.zjcdn.com/obj/full.mp4")!],
            expectedID: "7624728488368732900",
            pageURL: "https://www.douyin.com/video/7624728488368732900"
        )
        XCTAssertEqual(media.stream.urls.first?.host, "v5-dy-o.zjcdn.com")
        XCTAssertEqual(media.stream.kind, .video)
        XCTAssertEqual(media.stream.headers["Referer"], "https://www.douyin.com/")
    }
}

final class RouterTests: XCTestCase {
    func testRoutesByFirstURLAndRejectsUnknown() async {
        let router = SourceRouter()
        XCTAssertEqual(router.pick("BV1GJ411x7h7")?.id, "bilibili")
        XCTAssertEqual(router.pick("标题 https://v.douyin.com/abc/ 完")?.id, "douyin")
        XCTAssertEqual(router.pick("BV1hrW367Emp https://v.douyin.com/abc/")?.id, "douyin")
        XCTAssertNil(router.pick("https://music.163.com/song/1"))
        let client = ScriptedHTTPClient()
        do {
            _ = try await router.resolve("   ", client: client)
            XCTFail("空输入应失败")
        } catch let error as ResolveError {
            XCTAssertEqual(error, .emptyInput)
        } catch {
            XCTFail("意外错误 \(error)")
        }
        do {
            _ = try await router.resolve("https://example.com/video", client: client)
            XCTFail("未知站点应失败")
        } catch let error as ResolveError {
            XCTAssertEqual(error, .unsupportedLink)
            XCTAssertEqual(error.errorDescription, "暂时只支持哔哩哔哩和抖音的视频链接")
        } catch {
            XCTFail("意外错误 \(error)")
        }
    }
}
