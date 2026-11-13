import AVFoundation
import MediaPlayer
import ShengXiaCore
import SwiftUI
import UIKit

@MainActor
final class PlayerModel: ObservableObject {
    @Published var current: Track?
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var shuffle = false
    @Published var repeatMode: RepeatMode = .off
    @Published var isScrubbing = false
    @Published var playbackError: String?
    @Published var rate: Float
    @Published private(set) var queue = PlayQueue()
    @Published var loopA: TimeInterval?
    @Published var loopB: TimeInterval?
    @Published var sleepDeadline: Date?
    @Published var sleepAfterCurrent = false
    @Published var lyricText: String?

    private let library: LibraryStore
    private let settings: SettingsStore
    private let player = AVPlayer()
    private var timeObserver: Any?
    private var sessionReady = false
    private var lastNowPlayingUpdate = Date.distantPast
    private var transition: Task<Void, Never>?
    private var sleepTask: Task<Void, Never>?

    init(library: LibraryStore, settings: SettingsStore) {
        self.library = library
        self.settings = settings
        rate = settings.playbackRate
    }

    var upcomingTracks: [Track] { queue.upcoming.compactMap { library.track(id: $0) } }

    var abActive: Bool { loopA != nil }

    var abTitle: String {
        if loopA == nil { return "A-B" }
        if loopB == nil { return "设 B" }
        return "A-B"
    }

    func sleepCaption(at date: Date = Date()) -> String? {
        if sleepAfterCurrent { return "播完" }
        guard let sleepDeadline else { return nil }
        return Clock.string(max(0, sleepDeadline.timeIntervalSince(date)))
    }

    func activateSession() {
        guard !sessionReady else { return }
        sessionReady = true
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
        installObservers()
        installRemoteCommands()
    }

    func noteLibrary(_ tracks: [Track]) {
        let removed = updateQueue { $0.retain(Set(tracks.map(\.id))) }
        if let current, let updated = tracks.first(where: { $0.id == current.id }) {
            self.current = updated
        }
        guard removed else { return }
        if let id = queue.current, let track = tracks.first(where: { $0.id == id }) {
            begin(track, fadeIn: false)
        } else {
            halt()
        }
    }

    func play(_ track: Track, in context: [Track]) {
        activateSession()
        var ids = context.map(\.id)
        if !ids.contains(track.id) { ids.insert(track.id, at: 0) }
        if queue.context != ids || !queue.items.contains(track.id) {
            updateQueue { $0.load(ids, startAt: track.id, shuffle: shuffle) }
        } else {
            updateQueue { $0.jump(toID: track.id) }
        }
        transitionTo(track)
    }

    func toggle() {
        if current == nil {
            if let id = queue.current ?? queue.items.first, let track = library.track(id: id) {
                play(track, in: library.tracks)
            } else if let first = library.tracks.first {
                play(first, in: library.tracks)
            }
            return
        }
        if isPlaying {
            transition?.cancel()
            transition = Task { await fadeOutAndPause() }
        } else {
            player.volume = 0
            player.playImmediately(atRate: rate)
            isPlaying = true
            publishNowPlaying(force: true)
            transition?.cancel()
            transition = Task { await ramp(to: 1, duration: 0.16) }
        }
    }

    func playNext(automatic: Bool) {
        if automatic && sleepAfterCurrent {
            sleepAfterCurrent = false
            Task { await fadeOutAndPause() }
            return
        }
        guard let index = queue.nextIndex(repeatMode: repeatMode, automatic: automatic) else {
            if automatic { Task { await fadeOutAndPause() } }
            return
        }
        if automatic && repeatMode == .one && index == queue.currentIndex {
            seek(to: 0)
            if !isPlaying {
                player.playImmediately(atRate: rate)
                isPlaying = true
            }
            publishNowPlaying(force: true)
            return
        }
        updateQueue { $0.jump(to: index) }
        guard let id = queue.current, let track = library.track(id: id) else { return }
        transitionTo(track)
    }

    func playPrevious() {
        if currentTime > 3 {
            seek(to: 0)
            return
        }
        guard let index = queue.previousIndex(repeatMode: repeatMode) else {
            seek(to: 0)
            return
        }
        updateQueue { $0.jump(to: index) }
        guard let id = queue.current, let track = library.track(id: id) else { return }
        transitionTo(track)
    }

    func seek(to time: TimeInterval) {
        let upper = duration > 0 ? duration : max(time, 0)
        let clamped = min(max(0, time), upper)
        currentTime = clamped
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        publishNowPlaying(force: true)
    }

    func toggleShuffle() {
        shuffle.toggle()
        updateQueue { $0.setShuffle(shuffle) }
    }

    func cycleRepeat() { repeatMode = repeatMode.next }

    func setRate(_ value: Float) {
        let clamped = min(2, max(0.5, (value * 20).rounded() / 20))
        rate = clamped
        settings.playbackRate = clamped
        if isPlaying { player.rate = clamped }
        publishNowPlaying(force: true)
    }

    func toggleAB() {
        guard current != nil else { return }
        if loopA == nil {
            loopA = currentTime
            loopB = nil
        } else if loopB == nil {
            var start = loopA ?? 0
            var end = currentTime
            if end < start { swap(&start, &end) }
            if end - start < 0.5 { end = min(duration > 0 ? duration : start + 0.5, start + 0.5) }
            loopA = start
            loopB = end
        } else {
            loopA = nil
            loopB = nil
        }
    }

    func queueNext(_ track: Track) {
        guard current != nil else {
            play(track, in: library.tracks)
            return
        }
        updateQueue { $0.playNext(track.id) }
    }

    func queueAppend(_ track: Track) {
        guard current != nil else {
            play(track, in: library.tracks)
            return
        }
        updateQueue { $0.append(track.id) }
    }

    func moveUpcoming(from offsets: IndexSet, to destination: Int) {
        updateQueue { $0.moveUpcoming(fromOffsets: offsets, toOffset: destination) }
    }

    func removeUpcoming(at offsets: IndexSet) {
        updateQueue { $0.removeUpcoming(atOffsets: offsets) }
    }

    func clearUpcoming() { updateQueue { $0.clearUpcoming() } }

    func jumpUpcoming(_ track: Track) {
        guard queue.items.contains(track.id) else {
            play(track, in: library.tracks)
            return
        }
        updateQueue { $0.jump(toID: track.id) }
        transitionTo(track)
    }

    func startSleep(minutes: Int) {
        sleepAfterCurrent = false
        sleepDeadline = Date().addingTimeInterval(Double(minutes) * 60)
        armSleep()
    }

    func sleepAtEndOfTrack() {
        sleepTask?.cancel()
        sleepDeadline = nil
        sleepAfterCurrent = true
    }

    func cancelSleep() {
        sleepDeadline = nil
        sleepAfterCurrent = false
        sleepTask?.cancel()
    }

    func stop() {
        halt()
        queue = PlayQueue()
    }

    private func transitionTo(_ track: Track) {
        transition?.cancel()
        transition = Task { @MainActor in
            if self.isPlaying { await self.ramp(to: 0, duration: 0.12) }
            if Task.isCancelled { return }
            self.begin(track, fadeIn: true)
            await self.ramp(to: 1, duration: 0.16)
        }
    }

    func playStream(
        url: URL,
        headers: [String: String],
        title: String,
        artist: String,
        sourceName: String,
        format: String,
        lyrics: String?
    ) {
        activateSession()
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        current = Track(
            title: title,
            artist: artist,
            sourceName: sourceName,
            sourceURL: url.absoluteString,
            relativePath: "",
            duration: 0,
            formatLabel: format,
            byteCount: 0
        )
        duration = 0
        currentTime = 0
        loopA = nil
        loopB = nil
        lyricText = lyrics
        playbackError = nil
        player.replaceCurrentItem(with: item)
        player.volume = 1
        player.playImmediately(atRate: rate)
        isPlaying = true
        publishNowPlaying(force: true)
    }

    private func lyricsBeside(_ track: Track) -> String? {
        guard !track.relativePath.isEmpty else { return nil }
        let sidecar = library.fileURL(for: track).deletingPathExtension().appendingPathExtension("lrc")
        guard let text = try? String(contentsOf: sidecar, encoding: .utf8), !text.isEmpty else { return nil }
        return text
    }

    private func begin(_ track: Track, fadeIn: Bool) {
        activateSession()
        let url = library.fileURL(for: track)
        guard FileManager.default.fileExists(atPath: url.path) else {
            playbackError = "文件不在了。到「文件」App 确认一下，或下拉刷新资料库。"
            return
        }
        playbackError = nil
        current = track
        duration = track.duration
        currentTime = 0
        loopA = nil
        loopB = nil
        lyricText = lyricsBeside(track)
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        player.volume = fadeIn ? 0 : 1
        player.playImmediately(atRate: rate)
        isPlaying = true
        library.markPlayed(track.id)
        publishNowPlaying(force: true)
    }

    private func fadeOutAndPause() async {
        await ramp(to: 0, duration: 0.18)
        if Task.isCancelled { return }
        player.pause()
        player.volume = 1
        isPlaying = false
        publishNowPlaying(force: true)
    }

    private func halt() {
        transition?.cancel()
        player.pause()
        player.replaceCurrentItem(with: nil)
        player.volume = 1
        current = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        loopA = nil
        loopB = nil
        lyricText = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func ramp(to target: Float, duration: TimeInterval) async {
        let start = player.volume
        let steps = 6
        for step in 1...steps {
            if Task.isCancelled { return }
            let amount = Float(step) / Float(steps)
            player.volume = start + (target - start) * amount
            try? await Task.sleep(nanoseconds: UInt64(duration / Double(steps) * 1_000_000_000))
        }
        if !Task.isCancelled { player.volume = target }
    }

    @discardableResult
    private func updateQueue<T>(_ body: (inout PlayQueue) -> T) -> T {
        var copy = queue
        let result = body(&copy)
        queue = copy
        return result
    }

    private func armSleep() {
        sleepTask?.cancel()
        sleepTask = Task { @MainActor in
            while let deadline = self.sleepDeadline {
                if Task.isCancelled { return }
                if deadline.timeIntervalSinceNow <= 0 {
                    self.sleepDeadline = nil
                    await self.fadeOutAndPause()
                    return
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    private func installObservers() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.4, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self, !self.isScrubbing else { return }
                if time.seconds.isFinite { self.currentTime = time.seconds }
                if let item = self.player.currentItem {
                    let seconds = item.duration.seconds
                    if seconds.isFinite, seconds > 0 { self.duration = seconds }
                }
                if let start = self.loopA, let end = self.loopB, end > start, self.currentTime >= end {
                    self.seek(to: start)
                }
                self.publishNowPlaying(force: false)
            }
        }
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.playNext(automatic: true) }
        }
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let info = note.userInfo,
                  let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            let optionRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor in
                guard let self else { return }
                if type == .began {
                    self.isPlaying = false
                    self.player.volume = 1
                    self.publishNowPlaying(force: true)
                } else if AVAudioSession.InterruptionOptions(rawValue: optionRaw).contains(.shouldResume) {
                    self.player.playImmediately(atRate: self.rate)
                    self.isPlaying = true
                    self.publishNowPlaying(force: true)
                }
            }
        }
    }

    private func installRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)
        center.nextTrackCommand.removeTarget(nil)
        center.previousTrackCommand.removeTarget(nil)
        center.changePlaybackPositionCommand.removeTarget(nil)
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true
        center.changePlaybackPositionCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in if self?.isPlaying == false { self?.toggle() } }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in if self?.isPlaying == true { self?.toggle() } }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.toggle() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.playNext(automatic: false) }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.playPrevious() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            Task { @MainActor in self?.seek(to: position) }
            return .success
        }
    }

    private func publishNowPlaying(force: Bool) {
        guard let current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        if !force, Date().timeIntervalSince(lastNowPlayingUpdate) < 5 { return }
        lastNowPlayingUpdate = Date()
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: current.title,
            MPMediaItemPropertyArtist: current.artist,
            MPMediaItemPropertyPlaybackDuration: duration > 0 ? duration : current.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(rate) : 0
        ]
        if let cover = library.coverURL(for: current), let image = UIImage(contentsOfFile: cover.path) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
