import AVFoundation
import MediaPlayer
import SwiftUI
import UIKit

@MainActor
final class PlayerModel: ObservableObject {
    enum RepeatMode: String {
        case off, all, one

        var title: String {
            switch self {
            case .off: return "不循环"
            case .all: return "列表循环"
            case .one: return "单曲循环"
            }
        }

        var symbol: String {
            switch self {
            case .off, .all: return "repeat"
            case .one: return "repeat.1"
            }
        }
    }

    @Published var current: Track?
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var shuffle = false
    @Published var repeatMode: RepeatMode = .off
    @Published var isScrubbing = false
    @Published var playbackError: String?

    private let library: LibraryStore
    private let player = AVPlayer()
    private var queue: [Track] = []
    private var shuffledQueue: [Track] = []
    private var timeObserver: Any?
    private var sessionReady = false
    private var lastNowPlayingUpdate = Date.distantPast

    init(library: LibraryStore) {
        self.library = library
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

    func syncQueue(_ tracks: [Track]) {
        let sameOrder = queue.map(\.id) == tracks.map(\.id)
        queue = tracks
        if let current, !tracks.contains(where: { $0.id == current.id }) {
            stop()
            return
        }
        if shuffle && !sameOrder {
            reshuffle(keepingCurrentFirst: true)
        }
        if let current, let updated = tracks.first(where: { $0.id == current.id }) {
            self.current = updated
        }
    }

    func play(_ track: Track) {
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
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        player.play()
        isPlaying = true
        publishNowPlaying(force: true)
    }

    func toggle() {
        if current == nil {
            let list = activeQueue
            if let first = list.first { play(first) }
            return
        }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
        publishNowPlaying(force: true)
    }

    func playNext(automatic: Bool) {
        let list = activeQueue
        guard let current, let index = list.firstIndex(where: { $0.id == current.id }) else {
            if let first = list.first { play(first) }
            return
        }
        if automatic && repeatMode == .one {
            seek(to: 0)
            player.play()
            isPlaying = true
            publishNowPlaying(force: true)
            return
        }
        let next = index + 1
        if next < list.count {
            play(list[next])
        } else if repeatMode == .all || (!automatic && repeatMode == .one) {
            play(list[0])
        } else {
            player.pause()
            isPlaying = false
            publishNowPlaying(force: true)
        }
    }

    func playPrevious() {
        if currentTime > 3 {
            seek(to: 0)
            return
        }
        let list = activeQueue
        guard let current, let index = list.firstIndex(where: { $0.id == current.id }) else { return }
        let previous = index - 1
        if previous >= 0 {
            play(list[previous])
        } else if repeatMode == .all, let last = list.last {
            play(last)
        } else {
            seek(to: 0)
        }
    }

    func seek(to time: TimeInterval) {
        let upper = duration > 0 ? duration : max(time, 0)
        let clamped = min(max(0, time), upper)
        currentTime = clamped
        let cm = CMTime(seconds: clamped, preferredTimescale: 600)
        player.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero)
        publishNowPlaying(force: true)
    }

    func toggleShuffle() {
        shuffle.toggle()
        if shuffle { reshuffle(keepingCurrentFirst: true) }
    }

    func cycleRepeat() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        current = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private var activeQueue: [Track] {
        shuffle ? shuffledQueue : queue
    }

    private func reshuffle(keepingCurrentFirst: Bool) {
        guard let current, keepingCurrentFirst else {
            shuffledQueue = queue.shuffled()
            return
        }
        let rest = queue.filter { $0.id != current.id }.shuffled()
        shuffledQueue = [current] + rest
    }

    private func installObservers() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self, !self.isScrubbing else { return }
                if time.seconds.isFinite { self.currentTime = time.seconds }
                if let item = self.player.currentItem {
                    let seconds = item.duration.seconds
                    if seconds.isFinite, seconds > 0 { self.duration = seconds }
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
                    self.publishNowPlaying(force: true)
                } else if AVAudioSession.InterruptionOptions(rawValue: optionRaw).contains(.shouldResume) {
                    self.player.play()
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
            Task { @MainActor in
                if self?.isPlaying == false { self?.toggle() }
            }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                if self?.isPlaying == true { self?.toggle() }
            }
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
            let time = event.positionTime
            Task { @MainActor in self?.seek(to: time) }
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
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if let cover = library.coverURL(for: current), let image = UIImage(contentsOfFile: cover.path) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
