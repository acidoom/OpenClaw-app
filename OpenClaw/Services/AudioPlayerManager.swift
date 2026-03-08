//
//  AudioPlayerManager.swift
//  OpenClaw
//
//  Core audiobook playback controller wrapping AVPlayer
//

import Foundation
import AVFoundation
import MediaPlayer
import Combine
import UIKit

@MainActor
final class AudioPlayerManager: ObservableObject {
    static let shared = AudioPlayerManager()
    
    // MARK: - Published State
    
    @Published private(set) var currentAudiobook: Audiobook?
    @Published private(set) var chapters: [AudiobookChapter] = []
    @Published private(set) var currentChapter: AudiobookChapter?
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published var playbackSpeed: Double = 1.0 {
        didSet {
            if isPlaying {
                player?.rate = Float(playbackSpeed)
            }
            updateNowPlayingInfo()
        }
    }
    @Published private(set) var isBuffering: Bool = false
    @Published private(set) var playerError: String?
    @Published private(set) var lastHighlightId: String?
    @Published private(set) var isCreatingHighlight: Bool = false
    
    // MARK: - Computed
    
    var progress: Double { duration > 0 ? currentTime / duration : 0 }
    var hasActiveSession: Bool { currentAudiobook != nil }
    var remainingTime: Double { max(0, duration - currentTime) }
    
    var currentChapterProgress: Double {
        guard let chapter = currentChapter else { return 0 }
        let chapterDuration = chapter.endSeconds - chapter.startSeconds
        guard chapterDuration > 0 else { return 0 }
        return (currentTime - chapter.startSeconds) / chapterDuration
    }
    
    // MARK: - Private Properties
    
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private var positionSyncTask: Task<Void, Never>?
    private let service = LibroAIService.shared
    private let audioSession = AudioSessionManager.shared
    
    // Position sync
    private var lastSyncedPosition: Double = 0
    private let syncThreshold: Double = 15.0
    
    // Bookmark trigger: two triple-presses (previousTrack) within 1s
    private var lastPreviousTrackTime: Date?
    
    // KVO observations
    private var statusObservation: NSKeyValueObservation?
    private var bufferEmptyObservation: NSKeyValueObservation?
    private var bufferKeepUpObservation: NSKeyValueObservation?
    
    private init() {
        setupRemoteCommandCenter()
        setupInterruptionHandling()
    }
    
    // MARK: - Playback Control
    
    func play(audiobook: Audiobook) async {
        // If same audiobook, just resume
        if currentAudiobook?.id == audiobook.id, player != nil {
            resume()
            return
        }
        
        // Save current position before switching
        if currentAudiobook != nil {
            await syncPosition()
        }
        
        // Reset state
        stopInternal()
        playerError = nil
        currentAudiobook = audiobook
        isBuffering = true
        
        do {
            // Configure audio session
            try audioSession.configureForAudiobookPlayback()
            
            // Fetch chapters
            chapters = (try? await service.fetchChapters(audiobookId: audiobook.id)) ?? []
            
            // Fetch last playback state
            let savedState = try? await service.fetchPlaybackState(audiobookId: audiobook.id)
            let startPosition = savedState?.positionSeconds ?? 0
            if let savedSpeed = savedState?.playbackSpeed, savedSpeed > 0 {
                playbackSpeed = savedSpeed
            }
            
            // Use local file if available, otherwise stream
            let asset: AVURLAsset
            if let localURL = await service.localFileURL(for: audiobook) {
                // Validate file before playing
                let attrs = try? FileManager.default.attributesOfItem(atPath: localURL.path)
                let fileSize = attrs?[.size] as? Int64 ?? 0
                print("[AudioPlayer] Playing from local file: \(localURL.lastPathComponent) (\(fileSize) bytes)")
                
                // If the file is suspiciously small (< 10KB), it's likely corrupt or an error response
                if fileSize < 10_000 {
                    let preview = try? String(contentsOf: localURL, encoding: .utf8)
                    print("[AudioPlayer] File too small, content preview: \(preview?.prefix(200) ?? "unreadable")")
                    // Remove corrupt file and fall through to streaming
                    try? FileManager.default.removeItem(at: localURL)
                    let streamURL = try await service.streamURL(audiobookId: audiobook.id)
                    let headers = try await service.authHeaders()
                    print("[AudioPlayer] Falling back to streaming: \(streamURL)")
                    asset = AVURLAsset(
                        url: streamURL,
                        options: ["AVURLAssetHTTPHeaderFieldsKey": headers]
                    )
                } else {
                    // Check if AVPlayer can actually open this file (DRM, unsupported codec, etc.)
                    let localAsset = AVURLAsset(url: localURL)
                    var playable = false
                    do {
                        playable = try await localAsset.load(.isPlayable)
                    } catch {
                        print("[AudioPlayer] Failed to check isPlayable: \(error)")
                    }
                    if playable {
                        asset = localAsset
                    } else {
                        print("[AudioPlayer] Local file not playable (possibly DRM-protected), falling back to streaming")
                        let streamURL = try await service.streamURL(audiobookId: audiobook.id)
                        let headers = try await service.authHeaders()
                        print("[AudioPlayer] Streaming fallback URL: \(streamURL)")
                        asset = AVURLAsset(
                            url: streamURL,
                            options: ["AVURLAssetHTTPHeaderFieldsKey": headers]
                        )
                    }
                }
            } else {
                let streamURL = try await service.streamURL(audiobookId: audiobook.id)
                let headers = try await service.authHeaders()
                print("[AudioPlayer] Streaming from server: \(streamURL)")
                asset = AVURLAsset(
                    url: streamURL,
                    options: ["AVURLAssetHTTPHeaderFieldsKey": headers]
                )
            }
            
            playerItem = AVPlayerItem(asset: asset)
            player = AVPlayer(playerItem: playerItem!)
            player?.automaticallyWaitsToMinimizeStalling = true
            
            // Observe player item
            observePlayerItem()
            
            // Wait for player to be ready, then seek and play
            observePlayerReadiness(startPosition: startPosition)
            
        } catch {
            print("[AudioPlayer] Error starting playback: \(error)")
            playerError = error.localizedDescription
            isBuffering = false
        }
    }
    
    func resume() {
        guard let player = player else { return }
        player.rate = Float(playbackSpeed)
        isPlaying = true
        updateNowPlayingInfo()
    }
    
    func pause() {
        player?.pause()
        isPlaying = false
        updateNowPlayingInfo()
        Task { await syncPosition() }
    }
    
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }
    
    func seek(to seconds: Double) {
        let clamped = max(0, min(seconds, duration))
        let time = CMTime(seconds: clamped, preferredTimescale: 600)
        player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                self?.currentTime = clamped
                self?.updateCurrentChapter()
                self?.updateNowPlayingInfo()
            }
        }
    }
    
    func seekRelative(_ delta: Double) {
        seek(to: currentTime + delta)
    }
    
    func skipForward(_ seconds: Double = 30) {
        seekRelative(seconds)
    }
    
    func skipBackward(_ seconds: Double = 15) {
        seekRelative(-seconds)
    }
    
    func goToChapter(_ chapter: AudiobookChapter) {
        seek(to: chapter.startSeconds)
    }
    
    func nextChapter() {
        guard let current = currentChapter else { return }
        let nextIndex = current.chapterIndex + 1
        if let next = chapters.first(where: { $0.chapterIndex == nextIndex }) {
            goToChapter(next)
        }
    }
    
    func previousChapter() {
        guard let current = currentChapter else { return }
        // If more than 3 seconds into chapter, restart it. Otherwise go to previous.
        if currentTime - current.startSeconds > 3 {
            goToChapter(current)
        } else {
            let prevIndex = current.chapterIndex - 1
            if let prev = chapters.first(where: { $0.chapterIndex == prevIndex }) {
                goToChapter(prev)
            } else {
                seek(to: 0)
            }
        }
    }
    
    func stop() {
        Task { await syncPosition() }
        stopInternal()
        currentAudiobook = nil
        chapters = []
        currentChapter = nil
        playerError = nil
        clearNowPlayingInfo()
    }
    
    // MARK: - Private Stop
    
    private func stopInternal() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        positionSyncTask?.cancel()
        positionSyncTask = nil
        statusObservation?.invalidate()
        bufferEmptyObservation?.invalidate()
        bufferKeepUpObservation?.invalidate()
        statusObservation = nil
        bufferEmptyObservation = nil
        bufferKeepUpObservation = nil
        player?.pause()
        player = nil
        playerItem = nil
        isPlaying = false
        isBuffering = false
        currentTime = 0
        duration = 0
        lastSyncedPosition = 0
    }
    
    // MARK: - Now Playing Info
    
    private func updateNowPlayingInfo() {
        guard let audiobook = currentAudiobook else { return }
        
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: audiobook.title,
            MPMediaItemPropertyArtist: audiobook.author,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? playbackSpeed : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0
        ]
        
        if let narrator = audiobook.narrator {
            info[MPMediaItemPropertyAlbumTitle] = "Narrated by \(narrator)"
        }
        
        if !chapters.isEmpty {
            info[MPNowPlayingInfoPropertyChapterCount] = chapters.count
            if let chapter = currentChapter {
                info[MPNowPlayingInfoPropertyChapterNumber] = chapter.chapterIndex
            }
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    
    private func clearNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
    
    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        
        commandCenter.skipForwardCommand.preferredIntervals = [30]
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skipForward(30) }
            return .success
        }
        
        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skipBackward(15) }
            return .success
        }
        
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }
        
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.nextChapter() }
            return .success
        }
        
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                print("[AudioPlayer] Triple-press (previousTrack) → bookmark")
                self?.handleBookmarkCommand()
            }
            return .success
        }
        
        commandCenter.changePlaybackRateCommand.supportedPlaybackRates = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0]
        commandCenter.changePlaybackRateCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackRateCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.playbackSpeed = Double(event.playbackRate) }
            return .success
        }
        
        // Bookmark command — triggered by AirPods triple-press
        commandCenter.bookmarkCommand.isEnabled = true
        commandCenter.bookmarkCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.handleBookmarkCommand()
            }
            return .success
        }
    }
    
    // MARK: - Bookmark / AI Highlight
    
    private func handleBookmarkCommand() {
        print("[AudioPlayer] handleBookmarkCommand called, isCreatingHighlight=\(isCreatingHighlight)")
        guard let audiobook = currentAudiobook else {
            print("[AudioPlayer] No current audiobook, ignoring bookmark")
            return
        }
        
        // Immediate haptic feedback — double-pulse pattern
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.prepare()
        generator.impactOccurred()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let secondTap = UIImpactFeedbackGenerator(style: .medium)
            secondTap.impactOccurred()
        }
        
        // Prevent rapid double-triggers (auto-reset after 10s as safety net)
        guard !isCreatingHighlight else {
            print("[AudioPlayer] Bookmark blocked — already creating highlight")
            return
        }
        isCreatingHighlight = true
        
        let position = currentTime
        let chapter = currentChapter?.title
        let isTranscribed = audiobook.transcribed
        let bookId = audiobook.id
        
        print("[AudioPlayer] Bookmark triggered at \(formatTime(position))")
        
        Task {
            let highlightId = await HighlightManager.shared.createHighlight(
                audiobookId: bookId,
                positionSeconds: position,
                chapterTitle: chapter,
                isTranscribed: isTranscribed
            )
            
            await MainActor.run {
                self.lastHighlightId = highlightId
                self.isCreatingHighlight = false
                print("[AudioPlayer] Bookmark creation complete: \(highlightId.prefix(8))...")
            }
        }
        
        // Safety net: reset flag after 30s in case the task hangs
        Task {
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            if isCreatingHighlight {
                print("[AudioPlayer] Safety net: resetting isCreatingHighlight after timeout")
                isCreatingHighlight = false
            }
        }
    }
    
    /// Manual trigger from UI (bookmark button in AudioPlayerView)
    func createHighlightManually() {
        handleBookmarkCommand()
    }
    
    // MARK: - Time Observation
    
    private func startTimeObservation() {
        guard let player = player else { return }
        
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self = self else { return }
                self.currentTime = time.seconds
                self.updateCurrentChapter()
            }
        }
    }
    
    private func updateCurrentChapter() {
        guard !chapters.isEmpty else {
            currentChapter = nil
            return
        }
        
        // Find the chapter containing the current time
        let time = currentTime
        if let chapter = chapters.first(where: { time >= $0.startSeconds && time < $0.endSeconds }) {
            if currentChapter?.id != chapter.id {
                currentChapter = chapter
            }
        } else if let last = chapters.last, time >= last.startSeconds {
            // Past the last chapter's endSeconds, still in last chapter
            if currentChapter?.id != last.id {
                currentChapter = last
            }
        }
    }
    
    // MARK: - Position Sync
    
    private func startPositionSyncTimer() {
        positionSyncTask?.cancel()
        positionSyncTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                guard !Task.isCancelled else { break }
                await syncPosition()
            }
        }
    }
    
    private func syncPosition() async {
        guard let audiobook = currentAudiobook else { return }
        guard abs(currentTime - lastSyncedPosition) > syncThreshold else { return }
        
        do {
            try await service.updatePlaybackState(
                audiobookId: audiobook.id,
                position: currentTime,
                speed: playbackSpeed
            )
            lastSyncedPosition = currentTime
        } catch {
            print("[AudioPlayer] Position sync failed: \(error)")
        }
    }
    
    // MARK: - Interruption Handling
    
    private func setupInterruptionHandling() {
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .sink { [weak self] notification in
                Task { @MainActor in
                    self?.handleInterruption(notification)
                }
            }
            .store(in: &cancellables)
    }
    
    private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        
        switch type {
        case .began:
            pause()
        case .ended:
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    resume()
                }
            }
        @unknown default:
            break
        }
    }
    
    // MARK: - Player Item Observation
    
    private func observePlayerItem() {
        guard let playerItem = playerItem else { return }
        
        bufferEmptyObservation = playerItem.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] _, change in
            Task { @MainActor in
                if change.newValue == true {
                    self?.isBuffering = true
                }
            }
        }
        
        bufferKeepUpObservation = playerItem.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] _, change in
            Task { @MainActor in
                if change.newValue == true {
                    self?.isBuffering = false
                }
            }
        }
    }
    
    private func observePlayerReadiness(startPosition: Double) {
        guard let playerItem = playerItem else { return }
        
        statusObservation = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self = self else { return }
                
                switch item.status {
                case .readyToPlay:
                    self.duration = item.duration.seconds.isFinite ? item.duration.seconds : 0
                    self.isBuffering = false
                    
                    // Seek to saved position
                    if startPosition > 0 {
                        let time = CMTime(seconds: startPosition, preferredTimescale: 600)
                        self.player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                            Task { @MainActor in
                                self?.currentTime = startPosition
                                self?.updateCurrentChapter()
                                self?.player?.rate = Float(self?.playbackSpeed ?? 1.0)
                                self?.isPlaying = true
                                self?.updateNowPlayingInfo()
                                self?.startTimeObservation()
                                self?.startPositionSyncTimer()
                            }
                        }
                    } else {
                        self.currentTime = 0
                        self.updateCurrentChapter()
                        self.player?.rate = Float(self.playbackSpeed)
                        self.isPlaying = true
                        self.updateNowPlayingInfo()
                        self.startTimeObservation()
                        self.startPositionSyncTimer()
                    }
                    
                case .failed:
                    self.isBuffering = false
                    print("[AudioPlayer] Player failed: \(item.error?.localizedDescription ?? "unknown")")
                    
                    // Detect DRM / unsupported format errors and show a helpful message
                    var friendlyMessage = item.error?.localizedDescription ?? "Playback failed"
                    if let error = item.error as NSError? {
                        print("[AudioPlayer] Error domain: \(error.domain), code: \(error.code)")
                        if let underlyingError = error.userInfo[NSUnderlyingErrorKey] as? NSError {
                            print("[AudioPlayer] Underlying: \(underlyingError.domain), code: \(underlyingError.code), \(underlyingError.localizedDescription)")
                            // OSStatus -12848: media data unreadable (typically DRM-encrypted)
                            if underlyingError.domain == "NSOSStatusErrorDomain" && underlyingError.code == -12848 {
                                friendlyMessage = "This audiobook may be DRM-protected and cannot be played. The server needs to provide a DRM-free version."
                            }
                        }
                    }
                    self.playerError = friendlyMessage
                    
                case .unknown:
                    break
                    
                @unknown default:
                    break
                }
            }
        }
    }
}
