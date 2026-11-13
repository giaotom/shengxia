import XCTest
@testable import ShengXiaCore

final class LibraryModelTests: XCTestCase {
    func testDecodesVersionOneIndexWithDefaults() throws {
        let json = """
        {"version":1,"tracks":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","title":"春日影","artist":"MyGO","sourceName":"哔哩哔哩",
        "sourceURL":"https://www.bilibili.com/video/BV1hrW367Emp","relativePath":"Music/春日影.m4a","duration":275,
        "formatLabel":"M4A（AAC）","addedAt":"2026-11-01T10:00:00Z","byteCount":4200000}]}
        """
        let index = try LibraryIndex.decode(Data(json.utf8))
        XCTAssertEqual(index.version, LibraryIndex.currentVersion)
        XCTAssertEqual(index.playlists, [])
        let track = try XCTUnwrap(index.tracks.first)
        XCTAssertFalse(track.isFavorite)
        XCTAssertEqual(track.playCount, 0)
        XCTAssertEqual(track.sourceKind, .bilibili)
        XCTAssertEqual(track.sourceKey, "bilibili:BV1hrW367Emp")
    }

    func testRoundTripAndPrune() throws {
        let track = Track(title: "A", artist: "x", sourceName: "抖音", relativePath: "Music/a.m4a", duration: 10, formatLabel: "M4A", byteCount: 1)
        let ghost = UUID()
        var index = LibraryIndex(tracks: [track], playlists: [Playlist(name: "通勤", trackIDs: [track.id, ghost])])
        let decoded = try LibraryIndex.decode(try index.encoded())
        XCTAssertEqual(decoded.playlists.first?.trackIDs, [track.id])
        index.pruneDanglingReferences()
        XCTAssertEqual(index.playlists.first?.trackIDs, [track.id])
    }

    func testPlaylistEditing() {
        let ids = (0..<4).map { _ in UUID() }
        var list = Playlist(name: "  ")
        XCTAssertEqual(Playlist.cleanName("  "), "新歌单")
        XCTAssertEqual(list.add(ids), 4)
        XCTAssertEqual(list.add([ids[0]]), 0)
        list.move(fromOffsets: IndexSet(integer: 0), toOffset: 4)
        XCTAssertEqual(list.trackIDs, [ids[1], ids[2], ids[3], ids[0]])
        list.move(fromOffsets: IndexSet(integer: 3), toOffset: 0)
        XCTAssertEqual(list.trackIDs, ids)
        list.remove(atOffsets: IndexSet([1, 2]))
        XCTAssertEqual(list.trackIDs, [ids[0], ids[3]])
        list.remove(ids[0])
        XCTAssertEqual(list.trackIDs, [ids[3]])
    }

    func testQueryFiltersSearchesAndSorts() {
        let now = Date()
        let tracks = [
            Track(title: "Beta", artist: "乙", sourceName: "YouTube", relativePath: "1", duration: 50, formatLabel: "", addedAt: now, byteCount: 0),
            Track(title: "alpha", artist: "甲", sourceName: "哔哩哔哩", relativePath: "2", duration: 300, formatLabel: "", addedAt: now.addingTimeInterval(-10), byteCount: 0, isFavorite: true, playCount: 5),
            Track(title: "Gamma 春日", artist: "丙", sourceName: "文件", relativePath: "3", duration: 100, formatLabel: "", addedAt: now.addingTimeInterval(-20), byteCount: 0)
        ]
        XCTAssertEqual(LibraryQuery.apply(tracks).map(\.title), ["Beta", "alpha", "Gamma 春日"])
        XCTAssertEqual(LibraryQuery.apply(tracks, sort: .title).map(\.title), ["alpha", "Beta", "Gamma 春日"])
        XCTAssertEqual(LibraryQuery.apply(tracks, sort: .duration).map(\.title), ["alpha", "Gamma 春日", "Beta"])
        XCTAssertEqual(LibraryQuery.apply(tracks, sort: .mostPlayed).first?.title, "alpha")
        XCTAssertEqual(LibraryQuery.apply(tracks, filter: .favorites).map(\.title), ["alpha"])
        XCTAssertEqual(LibraryQuery.apply(tracks, filter: .source(.local)).map(\.title), ["Gamma 春日"])
        XCTAssertEqual(LibraryQuery.apply(tracks, filter: .source(.youtube)).map(\.title), ["Beta"])
        XCTAssertEqual(LibraryQuery.apply(tracks, search: "春日").map(\.title), ["Gamma 春日"])
        XCTAssertEqual(LibraryQuery.apply(tracks, search: "乙").map(\.title), ["Beta"])
        XCTAssertEqual(LibraryQuery.apply(tracks, search: "b站").map(\.title), ["alpha"])
    }
}

final class LinkBatchTests: XCTestCase {
    func testMediaKeys() {
        XCTAssertEqual(MediaKey.key(forInput: "https://www.bilibili.com/video/BV1hrW367Emp"), "bilibili:BV1hrW367Emp")
        XCTAssertEqual(MediaKey.key(forInput: "https://www.bilibili.com/video/BV1hrW367Emp?p=1"), "bilibili:BV1hrW367Emp")
        XCTAssertEqual(MediaKey.key(forInput: "https://www.bilibili.com/video/BV1hrW367Emp?p=3"), "bilibili:BV1hrW367Emp:p3")
        XCTAssertEqual(MediaKey.key(forInput: "BV1hrW367Emp"), "bilibili:BV1hrW367Emp")
        XCTAssertNil(MediaKey.key(forInput: "https://b23.tv/abcdEFG"))
        XCTAssertEqual(MediaKey.key(forInput: "https://youtu.be/dQw4w9WgXcQ?si=x"), "youtube:dQw4w9WgXcQ")
        XCTAssertEqual(MediaKey.key(forInput: "https://www.youtube.com/watch?v=dQw4w9WgXcQ"), "youtube:dQw4w9WgXcQ")
        XCTAssertEqual(MediaKey.key(forInput: "https://www.douyin.com/video/7624728488368732900"), "douyin:7624728488368732900")
        XCTAssertNil(MediaKey.key(forInput: "https://v.douyin.com/J4IQiholWbo/"))
    }

    func testBatchSplitting() {
        let text = """
        7.43 复制打开抖音，看看【示例】https://v.douyin.com/J4IQiholWbo/ 复制此链接
        https://www.bilibili.com/video/BV1hrW367Emp?p=2
        https://youtu.be/dQw4w9WgXcQ
        https://www.youtube.com/watch?v=dQw4w9WgXcQ
        https://example.com/nothing
        还有一个 BV1xx411c7mD
        """
        let jobs = BatchInput.jobs(from: text)
        XCTAssertEqual(jobs, [
            "https://v.douyin.com/J4IQiholWbo/",
            "https://www.bilibili.com/video/BV1hrW367Emp?p=2",
            "https://youtu.be/dQw4w9WgXcQ",
            "BV1xx411c7mD"
        ])
        XCTAssertEqual(BatchInput.jobs(from: "随便写点字"), ["随便写点字"])
        XCTAssertEqual(BatchInput.jobs(from: "   "), [])
        XCTAssertTrue(BatchInput.containsSupportedLink(text))
        XCTAssertFalse(BatchInput.containsSupportedLink("https://example.com"))
        XCTAssertEqual(BatchInput.sourceKind(of: jobs[0]), .douyin)
        XCTAssertEqual(BatchInput.sourceKind(of: jobs[3]), .bilibili)
    }

    func testAppLinkRoundTrip() throws {
        let share = "【示例】https://v.douyin.com/J4IQiholWbo/ 复制此链接&打开"
        let url = try XCTUnwrap(AppLink.extractURL(for: share))
        XCTAssertEqual(url.scheme, "shengxia")
        XCTAssertEqual(AppLink.extractText(from: url), share)
        XCTAssertEqual(
            AppLink.extractText(from: URL(string: "shengxia://extract?url=https%3A%2F%2Fyoutu.be%2FdQw4w9WgXcQ")!),
            "https://youtu.be/dQw4w9WgXcQ"
        )
        XCTAssertNil(AppLink.extractText(from: URL(string: "https://example.com/?url=x")!))
        XCTAssertNil(AppLink.extractText(from: URL(string: "shengxia://settings")!))
    }

    func testBilibiliQualityPreference() throws {
        let json = """
        {"code":0,"message":"0","data":{"dash":{"audio":[
          {"baseUrl":"https://up.bilivideo.com/hi.m4s","bandwidth":192000,"codecs":"mp4a.40.2","mimeType":"audio/mp4"},
          {"baseUrl":"https://up.bilivideo.com/lo.m4s","bandwidth":64000,"codecs":"mp4a.40.2","mimeType":"audio/mp4"}],
          "flac":{"audio":{"baseUrl":"https://up.bilivideo.com/lossless.flac","bandwidth":900000,"codecs":"fLaC","mimeType":"audio/mp4"}}}}}
        """
        let data = Data(json.utf8)
        XCTAssertEqual(try BilibiliParser.parsePlay(data).fileExtension, "flac")
        XCTAssertEqual(try BilibiliParser.parsePlay(data, quality: .standard).urls.first?.lastPathComponent, "hi.m4s")
        XCTAssertEqual(try BilibiliParser.parsePlay(data, quality: .compact).urls.first?.lastPathComponent, "lo.m4s")
    }
}

final class PlayQueueTests: XCTestCase {
    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    private let ids = (0..<5).map { _ in UUID() }

    func testSequentialNavigationAndRepeat() {
        var queue = PlayQueue()
        queue.load(ids, startAt: ids[3], shuffle: false)
        XCTAssertEqual(queue.current, ids[3])
        XCTAssertEqual(queue.nextIndex(repeatMode: .off, automatic: true), 4)
        queue.jump(to: 4)
        XCTAssertNil(queue.nextIndex(repeatMode: .off, automatic: true))
        XCTAssertEqual(queue.nextIndex(repeatMode: .all, automatic: true), 0)
        XCTAssertEqual(queue.nextIndex(repeatMode: .one, automatic: true), 4)
        XCTAssertEqual(queue.nextIndex(repeatMode: .one, automatic: false), 0)
        queue.jump(to: 0)
        XCTAssertNil(queue.previousIndex(repeatMode: .off))
        XCTAssertEqual(queue.previousIndex(repeatMode: .all), 4)
    }

    func testShuffleKeepsCurrentFirstAndRestoresOrder() {
        var rng = SeededGenerator(state: 42)
        var queue = PlayQueue()
        queue.load(ids, startAt: ids[2], shuffle: true, using: &rng)
        XCTAssertEqual(queue.current, ids[2])
        XCTAssertEqual(queue.currentIndex, 0)
        XCTAssertEqual(Set(queue.items), Set(ids))
        queue.setShuffle(false, using: &rng)
        XCTAssertEqual(queue.items, ids)
        XCTAssertEqual(queue.current, ids[2])
        queue.setShuffle(true, using: &rng)
        XCTAssertEqual(queue.items.first, ids[2])
    }

    func testPlayNextAppendMoveRemove() {
        var queue = PlayQueue()
        queue.load(Array(ids.prefix(3)), startAt: ids[0], shuffle: false)
        queue.playNext(ids[4])
        XCTAssertEqual(queue.upcoming, [ids[4], ids[1], ids[2]])
        queue.playNext(ids[2])
        XCTAssertEqual(queue.upcoming, [ids[2], ids[4], ids[1]])
        queue.append(ids[3])
        XCTAssertEqual(queue.upcoming.last, ids[3])
        queue.moveUpcoming(fromOffsets: IndexSet(integer: 3), toOffset: 0)
        XCTAssertEqual(queue.upcoming, [ids[3], ids[2], ids[4], ids[1]])
        queue.removeUpcoming(atOffsets: IndexSet(integer: 0))
        XCTAssertEqual(queue.upcoming, [ids[2], ids[4], ids[1]])
        XCTAssertEqual(queue.current, ids[0])
        queue.clearUpcoming()
        XCTAssertEqual(queue.items, [ids[0]])
    }

    func testRetainDropsDeletedTracks() {
        var queue = PlayQueue()
        queue.load(ids, startAt: ids[2], shuffle: false)
        XCTAssertFalse(queue.retain(Set(ids).subtracting([ids[0], ids[4]])))
        XCTAssertEqual(queue.current, ids[2])
        XCTAssertEqual(queue.items, [ids[1], ids[2], ids[3]])
        XCTAssertTrue(queue.retain([ids[1]]))
        XCTAssertNil(queue.current)
    }
}

final class AudioMathTests: XCTestCase {
    func testSilenceTrimRange() throws {
        let levels: [Float] = Array(repeating: -90, count: 40) + Array(repeating: -12, count: 200) + Array(repeating: -80, count: 20)
        let range = try XCTUnwrap(AudioMath.silenceTrimRange(levelsDB: levels, windowSeconds: 0.05))
        XCTAssertEqual(range.lowerBound, 1.75, accuracy: 0.001)
        XCTAssertEqual(range.upperBound, 12.25, accuracy: 0.001)
        XCTAssertNil(AudioMath.silenceTrimRange(levelsDB: Array(repeating: -10, count: 100), windowSeconds: 0.05))
        XCTAssertNil(AudioMath.silenceTrimRange(levelsDB: Array(repeating: -100, count: 100), windowSeconds: 0.05))
    }

    func testNormalizationGainRespectsCeiling() {
        XCTAssertEqual(AudioMath.normalizationGain(loudnessDB: -26, peakDB: -12), 10, accuracy: 0.001)
        XCTAssertEqual(AudioMath.normalizationGain(loudnessDB: -26, peakDB: -3), 2, accuracy: 0.001)
        XCTAssertEqual(AudioMath.normalizationGain(loudnessDB: -8, peakDB: 0), -8, accuracy: 0.001)
        XCTAssertEqual(AudioMath.normalizationGain(loudnessDB: -16.2, peakDB: -2), 0)
        XCTAssertEqual(AudioMath.normalizationGain(loudnessDB: -50, peakDB: -40), 12, accuracy: 0.001)
        XCTAssertEqual(AudioMath.normalizationGain(loudnessDB: AudioMath.floorDB, peakDB: AudioMath.floorDB), 0)
    }

    func testGatedLoudnessIgnoresSilence() {
        XCTAssertEqual(AudioMath.gatedLoudness([-20, -20, -100, -100]), -20, accuracy: 0.001)
        XCTAssertEqual(AudioMath.decibels(1), 0, accuracy: 0.0001)
        XCTAssertEqual(AudioMath.linear(-6), 0.501, accuracy: 0.001)
    }

    func testWaveformAndClipClamp() {
        XCTAssertEqual(AudioMath.waveform(levelsDB: [-60, 0, -30, -30], bars: 2), [1, 0.5])
        XCTAssertEqual(AudioMath.clampClip(start: -5, end: 400, duration: 300), 0...300)
        XCTAssertEqual(AudioMath.clampClip(start: 299.8, end: 299.9, duration: 300), 299...300)
        XCTAssertEqual(AudioMath.clampClip(start: 20, end: 10, duration: 300), 20...21)
        XCTAssertEqual(AudioMath.processingNote(trimmed: 1.24, gainDB: 3.04), "去静音 1.2 秒 · 响度 +3.0 dB")
        XCTAssertNil(AudioMath.processingNote(trimmed: 0, gainDB: 0))
    }

    func testDisplayTitleKeepsTenGraphemes() {
        XCTAssertEqual(DisplayTitle.shortened("从小被教要吃饱却很少被"), "从小被教要吃饱却很少")
        XCTAssertEqual(DisplayTitle.shortened("大连这座城市"), "大连这座城市")
        XCTAssertEqual(DisplayTitle.shortened("这个世界会好吗"), "这个世界会好吗")
        XCTAssertEqual(DisplayTitle.shortened(String(repeating: "🌆", count: 11)), String(repeating: "🌆", count: 10))
        XCTAssertEqual(DisplayTitle.shortened(String(repeating: "e\u{0301}", count: 12)).count, 10)
        XCTAssertEqual(DisplayTitle.shortened("  \n"), "未命名音轨")
        XCTAssertEqual(DisplayTitle.shortened("小猫想吃🍕，2021年"), "小猫想吃🍕，2021")
    }
}
