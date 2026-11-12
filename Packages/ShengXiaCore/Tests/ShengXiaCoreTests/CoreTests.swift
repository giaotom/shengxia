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
            XCTAssertEqual(error.errorDescription, "暂时只支持哔哩哔哩、抖音和 YouTube 的视频链接")
        } catch {
            XCTFail("意外错误 \(error)")
        }
    }
}

final class YouTubeTests: XCTestCase {
    func testParsesWatchShortsMusicAndShareText() {
        let samples: [(String, String)] = [
            ("https://www.youtube.com/watch?v=jNQXAC9IVRw", "jNQXAC9IVRw"),
            ("https://www.youtube.com/watch?v=jNQXAC9IVRw&t=30s&list=PL123", "jNQXAC9IVRw"),
            ("https://youtu.be/jNQXAC9IVRw", "jNQXAC9IVRw"),
            ("https://youtu.be/jNQXAC9IVRw?t=12", "jNQXAC9IVRw"),
            ("https://www.youtube.com/shorts/dQw4w9WgXcQ", "dQw4w9WgXcQ"),
            ("https://m.youtube.com/watch?v=dQw4w9WgXcQ", "dQw4w9WgXcQ"),
            ("https://music.youtube.com/watch?v=dQw4w9WgXcQ", "dQw4w9WgXcQ"),
            ("https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ", "dQw4w9WgXcQ"),
            ("看看这首 https://youtu.be/dQw4w9WgXcQ 复制打开", "dQw4w9WgXcQ")
        ]
        let source = YouTubeSource()
        for (text, expected) in samples {
            let urls = LinkParser.extractURLs(from: text)
            XCTAssertEqual(LinkParser.youtubeID(in: urls[0]), expected, text)
            XCTAssertTrue(source.canHandle(text), text)
        }
        XCTAssertFalse(source.canHandle("https://www.bilibili.com/video/BV1hrW367Emp"))
        XCTAssertFalse(source.canHandle("BV1GJ411x7h7"))
        XCTAssertTrue(source.canHandle("https://www.youtube.com/playlist?list=PLxxxxxxxxxxxxxxxxxxxxxx"))
        XCTAssertNil(LinkParser.youtubeID(in: URL(string: "https://www.youtube.com/playlist?list=PLxxxxxxxxxxxxxxxxxxxxxx")!))
        XCTAssertEqual(SourceRouter().pick("标题 https://youtu.be/dQw4w9WgXcQ 完")?.id, "youtube")
        XCTAssertEqual(SourceRouter().pick("https://youtu.be/dQw4w9WgXcQ https://v.douyin.com/abc/")?.id, "youtube")
    }

    func testPrefersItag140OverOpusAndHigherAAC() throws {
        let json = playerJSON(formats: """
        [
          {"itag":251,"mimeType":"audio/webm; codecs=\\"opus\\"","bitrate":200000,"url":"https://cdn.example/opus.webm"},
          {"itag":141,"mimeType":"audio/mp4; codecs=\\"mp4a.40.2\\"","bitrate":256000,"signatureCipher":"s=abc"},
          {"itag":139,"mimeType":"audio/mp4; codecs=\\"mp4a.40.5\\"","bitrate":49000,"url":"https://cdn.example/low.m4a"},
          {"itag":140,"mimeType":"audio/mp4; codecs=\\"mp4a.40.2\\"","bitrate":130677,"url":"https://cdn.example/140.m4a"}
        ]
        """)
        let result = try YouTubeParser.parse(json, videoID: "dQw4w9WgXcQ", headers: ["User-Agent": "test"])
        guard case .ready(let media) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(media.title, "示例标题")
        XCTAssertEqual(media.author, "示例作者")
        XCTAssertEqual(media.duration, 213)
        XCTAssertEqual(media.sourceName, "YouTube")
        XCTAssertEqual(media.pageURL, "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
        XCTAssertEqual(media.coverURL?.absoluteString, "https://i.ytimg.com/vi/dQw4w9WgXcQ/hq720.jpg")
        XCTAssertEqual(media.stream.kind, .audio)
        XCTAssertEqual(media.stream.fileExtension, "m4a")
        XCTAssertEqual(media.stream.formatLabel, "M4A（AAC）")
        XCTAssertEqual(media.stream.urls.map(\.absoluteString), ["https://cdn.example/140.m4a"])
        XCTAssertEqual(media.stream.headers["Referer"], nil)
        XCTAssertEqual(media.stream.headers["User-Agent"], "test")
    }

    func testFallsBackToBestAACThenMuxedMP4() throws {
        let higher = try YouTubeParser.parse(
            playerJSON(formats: """
            [
              {"itag":139,"mimeType":"audio/mp4; codecs=\\"mp4a.40.5\\"","bitrate":49000,"url":"https://cdn.example/low.m4a"},
              {"itag":256,"mimeType":"audio/mp4; codecs=\\"mp4a.40.2\\"","bitrate":180000,"url":"https://cdn.example/hi.m4a"}
            ]
            """),
            videoID: "dQw4w9WgXcQ",
            headers: [:]
        )
        guard case .ready(let aac) = higher else { return XCTFail("\(higher)") }
        XCTAssertEqual(aac.stream.urls.first?.absoluteString, "https://cdn.example/hi.m4a")

        let muxed = try YouTubeParser.parse(
            playerJSON(adaptive: "[]", formats: """
            [
              {"itag":22,"mimeType":"video/mp4; codecs=\\"avc1.64001F, mp4a.40.2\\"","bitrate":700000,"url":"https://cdn.example/22.mp4"},
              {"itag":18,"mimeType":"video/mp4; codecs=\\"avc1.42001E, mp4a.40.2\\"","bitrate":300000,"url":"https://cdn.example/18.mp4"}
            ]
            """),
            videoID: "dQw4w9WgXcQ",
            headers: [:]
        )
        guard case .ready(let video) = muxed else { return XCTFail("\(muxed)") }
        XCTAssertEqual(video.stream.kind, .video)
        XCTAssertEqual(video.stream.fileExtension, "mp4")
        XCTAssertEqual(video.stream.urls.first?.absoluteString, "https://cdn.example/18.mp4")
    }

    func testRejectsWebMOnlyAndClassifiesPlayability() throws {
        let webm = try YouTubeParser.parse(
            playerJSON(formats: #"[{"itag":251,"mimeType":"audio/webm; codecs=\"opus\"","bitrate":160000,"url":"https://cdn.example/a.webm"}]"#),
            videoID: "dQw4w9WgXcQ",
            headers: [:]
        )
        guard case .noAudio = webm else { return XCTFail("\(webm)") }

        try assertPlayability("LOGIN_REQUIRED", reason: "Sign in to confirm your age", equals: .youtubeAgeRestricted)
        try assertPlayability("LOGIN_REQUIRED", reason: "Sign in to confirm you’re not a bot", retry: true)
        try assertPlayability("UNPLAYABLE", reason: "This video is private.", equals: .youtubePrivate)
        try assertPlayability("UNPLAYABLE", reason: "This video is available to this channel's members on level: test", equals: .youtubeMembersOnly)
        try assertPlayability("ERROR", reason: "This video is unavailable", equals: .youtubeUnavailable)
        try assertPlayability("UNPLAYABLE", reason: "The uploader has not made this video available in your country", equals: .youtubeRegionBlocked)
        try assertPlayability("LIVE_STREAM", reason: "This live event will begin in a few moments.", equals: .youtubeLiveUnsupported)
        XCTAssertEqual(ResolveError.youtubeConnectionFailed.errorDescription, "YouTube 连接失败，请确认手机已开启代理")
        XCTAssertEqual(ResolveError.youtubeResolveFailed.errorDescription, "YouTube 解析失败，可能是风控更新")
    }

    func testResolveFallsBackWhenFirstClientIsBotChecked() async throws {
        let client = ScriptedHTTPClient()
        client.handlers = [
            { request in
                let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertTrue(request.url?.path.contains("/youtubei/v1/player") == true)
                XCTAssertTrue(body.contains("VISIONOS"))
                XCTAssertTrue(body.contains("dQw4w9WgXcQ"))
                return HTTPResponse(statusCode: 200, finalURL: request.url, data: Data(
                    #"{"playabilityStatus":{"status":"LOGIN_REQUIRED","reason":"Sign in to confirm you’re not a bot"}}"#.utf8
                ))
            },
            { request in
                let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
                XCTAssertTrue(body.contains("ANDROID_VR"))
                return HTTPResponse(
                    statusCode: 200,
                    finalURL: request.url,
                    data: self.playerJSON(formats: #"[{"itag":140,"mimeType":"audio/mp4; codecs=\"mp4a.40.2\"","bitrate":130677,"url":"https://cdn.example/140.m4a"}]"#)
                )
            }
        ]
        let step = try await YouTubeSource().resolve("https://youtu.be/dQw4w9WgXcQ", client: client)
        guard case .ready(let media) = step else { return XCTFail("\(step)") }
        XCTAssertEqual(media.stream.urls.first?.absoluteString, "https://cdn.example/140.m4a")
        XCTAssertEqual(media.stream.headers["User-Agent"], YouTubeClients.androidVRUserAgent)
        XCTAssertEqual(media.stream.headers["Referer"], "https://www.youtube.com/")
        XCTAssertTrue(client.handlers.isEmpty)
    }

    func testAgeRestrictionDoesNotTryAnotherClient() async {
        let client = ScriptedHTTPClient()
        client.handlers = [
            { _ in
                HTTPResponse(statusCode: 200, finalURL: nil, data: Data(
                    #"{"playabilityStatus":{"status":"LOGIN_REQUIRED","reason":"Sign in to confirm your age"}}"#.utf8
                ))
            }
        ]
        do {
            _ = try await YouTubeSource().resolve("https://www.youtube.com/watch?v=Tq92D6wQ1mg", client: client)
            XCTFail("年龄限制应失败")
        } catch let error as ResolveError {
            XCTAssertEqual(error, .youtubeAgeRestricted)
            XCTAssertEqual(client.handlers.count, 0)
        } catch {
            XCTFail("意外错误 \(error)")
        }
    }

    func testConnectionFailureAndMissingVideoID() async {
        do {
            _ = try await YouTubeSource().resolve("https://www.youtube.com/playlist?list=PLxxxxxxxxxxxxxxxxxxxxxx", client: ScriptedHTTPClient())
            XCTFail("播放列表应失败")
        } catch let error as ResolveError {
            XCTAssertEqual(error, .youtubeNotAVideo)
        } catch {
            XCTFail("意外错误 \(error)")
        }
        do {
            _ = try await YouTubeSource().resolve("https://youtu.be/dQw4w9WgXcQ", client: OfflineHTTPClient())
            XCTFail("断网应失败")
        } catch let error as ResolveError {
            XCTAssertEqual(error, .youtubeConnectionFailed)
        } catch {
            XCTFail("意外错误 \(error)")
        }
    }

    private func assertPlayability(
        _ status: String,
        reason: String,
        equals expected: ResolveError? = nil,
        retry: Bool = false
    ) throws {
        let data = Data(#"{"playabilityStatus":{"status":"\#(status)","reason":"\#(reason)"}}"#.utf8)
        do {
            let result = try YouTubeParser.parse(data, videoID: "dQw4w9WgXcQ", headers: [:])
            if retry {
                guard case .retry = result else { return XCTFail("\(result)") }
            } else {
                XCTFail("应当失败，实际 \(result)")
            }
        } catch let error as ResolveError {
            XCTAssertEqual(error, expected)
        }
    }

    private func playerJSON(adaptive: String? = nil, formats: String) -> Data {
        let adaptiveJSON = adaptive ?? formats
        let progressive = adaptive == nil ? "[]" : formats
        let text = """
        {"playabilityStatus":{"status":"OK"},"videoDetails":{"videoId":"dQw4w9WgXcQ","title":"示例标题","author":"示例作者","lengthSeconds":"213","thumbnail":{"thumbnails":[{"url":"https://i.ytimg.com/vi/dQw4w9WgXcQ/mqdefault.jpg","width":320},{"url":"https://i.ytimg.com/vi/dQw4w9WgXcQ/hq720.jpg","width":1280}]}},"streamingData":{"adaptiveFormats":\(adaptiveJSON),"formats":\(progressive)}}
        """
        return Data(text.utf8)
    }
}

private final class OfflineHTTPClient: HTTPClient {
    func send(_ request: URLRequest) async throws -> HTTPResponse {
        throw URLError(.cannotConnectToHost)
    }
}
