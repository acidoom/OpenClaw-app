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
    @Published private(set) var currentPodcastEpisode: PodcastEpisode?
    @Published private(set) var currentPodcast: Podcast?
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
    @Published private(set) var isDownloadingForSeek: Bool = false
    @Published private(set) var downloadForSeekProgress: Double = 0
    @Published private(set) var seekWarning: String?
    
    // MARK: - Computed
    
    var progress: Double { duration > 0 ? currentTime / duration : 0 }
    var hasActiveSession: Bool { currentAudiobook != nil || currentPodcastEpisode != nil }
    var remainingTime: Double { max(0, duration - currentTime) }
    
    var currentChapterProgress: Double {
        guard let chapter = currentChapter else { return 0 }
        let chapterDuration = chapter.endSeconds - chapter.startSeconds
        guard chapterDuration > 0 else { return 0 }
        return (currentTime - chapter.startSeconds) / chapterDuration
    }
    
    var hasChapters: Bool { chapters.count > 1 }
    
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
    
    // Now Playing artwork
    private var nowPlayingArtwork: MPMediaItemArtwork?
    
    // Bookmark trigger: two triple-presses (previousTrack) within 1s
    private var lastPreviousTrackTime: Date?
    
    // Background download for seek support
    private var backgroundDownloadTask: Task<Void, Never>?
    
    // KVO observations
    private var statusObservation: NSKeyValueObservation?
    private var durationObservation: NSKeyValueObservation?
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
        nowPlayingArtwork = nil
        
        // Load artwork for lock screen / Control Center
        if let coverUrl = audiobook.coverUrl, coverUrl.hasPrefix("http") {
            loadNowPlayingArtwork(from: coverUrl)
        }
        
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
                        let assetDuration = try await localAsset.load(.duration)
                        print("[AudioPlayer] Local file diagnostics:")
                        print("[AudioPlayer]   Size: \(fileSize) bytes (\(String(format: "%.1f", Double(fileSize) / 1_048_576.0)) MB)")
                        print("[AudioPlayer]   AVAsset duration: \(assetDuration.seconds)s (finite: \(assetDuration.seconds.isFinite))")
                        print("[AudioPlayer]   Metadata duration: \(audiobook.durationSeconds)s")
                        print("[AudioPlayer]   Playable: \(playable)")
                        print("[AudioPlayer]   Format: \(audiobook.format.rawValue)")
                        
                        // Check if duration is suspiciously wrong
                        if assetDuration.seconds.isFinite && assetDuration.seconds > 0 && audiobook.durationSeconds > 0 {
                            let ratio = assetDuration.seconds / audiobook.durationSeconds
                            if ratio < 0.1 {
                                print("[AudioPlayer] ⚠️ AVAsset duration is <10% of metadata — file may be truncated or corrupt!")
                            }
                        }
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
            
            // If streaming (no local file), download in background for seek support
            let isLocal = await service.localFileURL(for: audiobook) != nil
            if !isLocal && audiobook.downloaded {
                startBackgroundDownloadForSeek(audiobook: audiobook)
            }
            
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
        pushNowPlayingToWidget()
    }
    
    func pause() {
        player?.pause()
        isPlaying = false
        updateNowPlayingInfo()
        pushNowPlayingToWidget()
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
        // Use the best known upper bound for clamping
        let upperBound: Double
        if duration > 0 {
            upperBound = duration
        } else if let audiobook = currentAudiobook, audiobook.durationSeconds > 0 {
            upperBound = audiobook.durationSeconds
        } else {
            upperBound = seconds // allow seeking when duration is unknown
        }
        let clamped = max(0, min(seconds, upperBound))
        let time = CMTime(seconds: clamped, preferredTimescale: 600)
        
        // Use relaxed tolerance for MP3 files — they lack precise seek points,
        // so .zero tolerance can cause seeks to fail or hang on large files
        let isMP3 = currentAudiobook?.format == .mp3
        let tolerance = isMP3 ? CMTime(seconds: 2.0, preferredTimescale: 600) : CMTime.zero
        
        // Clear any previous warning
        seekWarning = nil
        
        player?.seek(to: time, toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] finished in
            Task { @MainActor in
                guard let self = self, let player = self.player else { return }
                if finished {
                    // Verify the player actually moved to the requested position
                    let actualTime = player.currentTime().seconds
                    let seekDelta = abs(actualTime - clamped)
                    
                    if seekDelta > 5.0 && clamped > 30 {
                        // Seek "succeeded" but player didn't actually move — file has seek issues
                        print("[AudioPlayer] ⚠️ Seek verification failed: requested \(clamped)s, actual \(actualTime)s (delta: \(seekDelta)s)")
                        print("[AudioPlayer] This file likely has corrupt frames or missing VBR headers")
                        self.seekWarning = "This audio file doesn't support seeking. It may be corrupt or missing index headers."
                        // Update currentTime to actual position instead of requested
                        self.currentTime = actualTime
                    } else {
                        self.currentTime = clamped
                    }
                    self.updateCurrentChapter()
                    self.updateNowPlayingInfo()
                } else {
                    print("[AudioPlayer] Seek to \(clamped)s was cancelled or failed")
                }
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
    
    /// Skip interval used for prev/next when no chapters are available (5 minutes)
    private let chapterlessSkipInterval: Double = 300
    
    func nextChapter() {
        if !hasChapters {
            skipForward(chapterlessSkipInterval)
            return
        }
        guard let current = currentChapter else {
            skipForward(chapterlessSkipInterval)
            return
        }
        let nextIndex = current.chapterIndex + 1
        if let next = chapters.first(where: { $0.chapterIndex == nextIndex }) {
            goToChapter(next)
        } else {
            // At the last chapter — skip forward instead of doing nothing
            skipForward(chapterlessSkipInterval)
        }
    }
    
    func previousChapter() {
        if !hasChapters {
            skipBackward(chapterlessSkipInterval)
            return
        }
        guard let current = currentChapter else {
            skipBackward(chapterlessSkipInterval)
            return
        }
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
        if currentPodcastEpisode != nil {
            Task { await syncPodcastPosition() }
        } else {
            Task { await syncPosition() }
        }
        // Capture audiobook state before clearing, so widget shows last listened book
        let lastBook = currentAudiobook
        let lastProgress = progress
        let lastCurrentTime = currentTime
        let lastDuration = duration
        let lastChapterTitle = currentChapter?.title
        stopInternal()
        currentAudiobook = nil
        currentPodcastEpisode = nil
        currentPodcast = nil
        chapters = []
        currentChapter = nil
        playerError = nil
        nowPlayingArtwork = nil
        clearNowPlayingInfo()
        // Push last book info to widget with isPlaying=false instead of clearing
        if let book = lastBook {
            let nowPlaying = WidgetNowPlaying(
                audiobookId: book.id,
                title: book.title,
                author: book.author,
                coverUrl: book.coverUrl,
                progress: lastProgress,
                currentTime: lastCurrentTime,
                duration: lastDuration,
                isPlaying: false,
                chapterTitle: lastChapterTitle,
                updatedAt: Date()
            )
            WidgetDataManager.shared.updateNowPlaying(nowPlaying)
            WidgetDataManager.shared.reloadWidgets()
        }
    }
    
    // MARK: - Background Download for Seek Support
    
    /// Downloads the audiobook locally in the background, then swaps the player to local file
    /// so that seeking/scrubbing works (streaming MP3 without Range support can't seek).
    private func startBackgroundDownloadForSeek(audiobook: Audiobook) {
        backgroundDownloadTask?.cancel()
        isDownloadingForSeek = true
        downloadForSeekProgress = 0
        
        print("[AudioPlayer] Starting background download for seek support: \(audiobook.id)")
        
        backgroundDownloadTask = Task {
            do {
                let localURL = try await service.downloadToDevice(audiobook: audiobook) { [weak self] progress in
                    Task { @MainActor in
                        self?.downloadForSeekProgress = progress
                    }
                }
                
                guard !Task.isCancelled else { return }
                guard self.currentAudiobook?.id == audiobook.id else { return }
                
                print("[AudioPlayer] Background download complete, switching to local file")
                await self.switchToLocalFile(localURL, for: audiobook)
                
            } catch {
                print("[AudioPlayer] Background download failed: \(error)")
            }
            
            self.isDownloadingForSeek = false
        }
    }
    
    /// Seamlessly swap the streaming player to a local file, preserving position and playback state.
    private func switchToLocalFile(_ localURL: URL, for audiobook: Audiobook) async {
        guard currentAudiobook?.id == audiobook.id else { return }
        
        let savedPosition = currentTime
        let wasPlaying = isPlaying
        let savedSpeed = playbackSpeed
        
        // Tear down current observers (but don't reset state)
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        statusObservation?.invalidate()
        durationObservation?.invalidate()
        bufferEmptyObservation?.invalidate()
        bufferKeepUpObservation?.invalidate()
        
        // Create new player with local file
        let asset = AVURLAsset(url: localURL)
        let newItem = AVPlayerItem(asset: asset)
        playerItem = newItem
        player?.replaceCurrentItem(with: newItem)
        
        // Re-setup observers
        observePlayerItem()
        
        // Wait for ready, then seek and resume
        let tolerance = CMTime(seconds: 0.5, preferredTimescale: 600)
        let seekTime = CMTime(seconds: savedPosition, preferredTimescale: 600)
        
        // Update duration from local file
        do {
            let localDuration = try await asset.load(.duration).seconds
            if localDuration.isFinite && localDuration > 0 {
                duration = localDuration
                print("[AudioPlayer] Local file duration: \(localDuration)s")
            }
        } catch {
            print("[AudioPlayer] Could not load local duration: \(error)")
        }
        
        player?.seek(to: seekTime, toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.currentTime = savedPosition
                if wasPlaying {
                    self.player?.rate = Float(savedSpeed)
                    self.isPlaying = true
                }
                self.startTimeObservation()
                self.updateNowPlayingInfo()
                print("[AudioPlayer] Switched to local file at \(formatTime(savedPosition))")
            }
        }
    }
    
    // MARK: - Paper Audio Playback
    
    /// Play a paper audio stream by building an Audiobook wrapper and using the paper audio stream URL
    func playPaperAudio(audiobook: Audiobook, jobId: String) async {
        // If same paper audio, just resume
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
            try audioSession.configureForAudiobookPlayback()
            
            // Fetch manifest to build chapters
            let manifest = try await PaperAudioService.shared.fetchManifest(jobId: jobId)
            chapters = manifest.sections.enumerated().map { index, section in
                AudiobookChapter(
                    id: index,
                    audiobookId: audiobook.id,
                    title: section.name,
                    startSeconds: section.startSec,
                    endSeconds: section.startSec + section.durationSec,
                    chapterIndex: index,
                    summary: nil
                )
            }
            
            // Build streaming URL with auth
            let streamURL = try PaperAudioService.shared.streamURL(jobId: jobId)
            let headers = try PaperAudioService.shared.authHeaders()
            
            print("[AudioPlayer] Streaming paper audio: \(streamURL)")
            let asset = AVURLAsset(
                url: streamURL,
                options: ["AVURLAssetHTTPHeaderFieldsKey": headers]
            )
            
            playerItem = AVPlayerItem(asset: asset)
            player = AVPlayer(playerItem: playerItem!)
            player?.automaticallyWaitsToMinimizeStalling = true
            
            observePlayerItem()
            observePlayerReadiness(startPosition: 0)
            
        } catch {
            print("[AudioPlayer] Error starting paper audio playback: \(error)")
            playerError = error.localizedDescription
            isBuffering = false
        }
    }
    
    // MARK: - Podcast Episode Playback
    
    func playPodcastEpisode(episode: PodcastEpisode, podcast: Podcast) async {
        // If same episode, just resume
        if currentPodcastEpisode?.id == episode.id, player != nil {
            resume()
            return
        }
        
        // Save current position before switching
        if currentPodcastEpisode != nil {
            await syncPodcastPosition()
        } else if currentAudiobook != nil {
            await syncPosition()
        }
        
        // Reset state
        stopInternal()
        playerError = nil
        currentAudiobook = nil
        currentPodcastEpisode = episode
        currentPodcast = podcast
        chapters = []
        currentChapter = nil
        isBuffering = true
        nowPlayingArtwork = nil
        
        // Load artwork for lock screen / Control Center
        loadNowPlayingArtwork(from: episode.artworkUrl ?? podcast.artworkUrl)
        
        do {
            try audioSession.configureForAudiobookPlayback()
            
            // Fetch saved playback position
            let savedState = try? await PodcastService.shared.fetchPlaybackState(episodeId: episode.id)
            let startPosition = savedState?.positionSeconds ?? 0
            if let savedSpeed = savedState?.playbackSpeed, savedSpeed > 0 {
                playbackSpeed = savedSpeed
            }
            
            // Play directly from podcast CDN (no auth headers needed)
            guard let url = URL(string: episode.audioUrl) else {
                playerError = "Invalid audio URL"
                isBuffering = false
                return
            }
            
            print("[AudioPlayer] Streaming podcast episode: \(url)")
            let asset = AVURLAsset(url: url)
            
            playerItem = AVPlayerItem(asset: asset)
            player = AVPlayer(playerItem: playerItem!)
            player?.automaticallyWaitsToMinimizeStalling = true
            
            observePlayerItem()
            observePlayerReadiness(startPosition: startPosition)
            
        } catch {
            print("[AudioPlayer] Error starting podcast playback: \(error)")
            playerError = error.localizedDescription
            isBuffering = false
        }
    }
    
    private func syncPodcastPosition() async {
        guard let episode = currentPodcastEpisode else { return }
        guard abs(currentTime - lastSyncedPosition) > syncThreshold else { return }
        
        do {
            try await PodcastService.shared.updatePlaybackState(
                episodeId: episode.id,
                position: currentTime,
                speed: playbackSpeed
            )
            lastSyncedPosition = currentTime
        } catch {
            print("[AudioPlayer] Podcast position sync failed: \(error)")
        }
    }
    
    // MARK: - Private Stop
    
    private func stopInternal() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        positionSyncTask?.cancel()
        positionSyncTask = nil
        backgroundDownloadTask?.cancel()
        backgroundDownloadTask = nil
        isDownloadingForSeek = false
        statusObservation?.invalidate()
        durationObservation?.invalidate()
        bufferEmptyObservation?.invalidate()
        bufferKeepUpObservation?.invalidate()
        statusObservation = nil
        durationObservation = nil
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
        var info: [String: Any] = [
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? playbackSpeed : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0
        ]
        
        if let audiobook = currentAudiobook {
            info[MPMediaItemPropertyTitle] = audiobook.title
            info[MPMediaItemPropertyArtist] = audiobook.author
            
            if let narrator = audiobook.narrator {
                info[MPMediaItemPropertyAlbumTitle] = "Narrated by \(narrator)"
            }
        } else if let episode = currentPodcastEpisode {
            info[MPMediaItemPropertyTitle] = episode.title
            info[MPMediaItemPropertyArtist] = currentPodcast?.title ?? ""
            info[MPMediaItemPropertyAlbumTitle] = currentPodcast?.author ?? ""
        } else {
            return
        }
        
        if let artwork = nowPlayingArtwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        
        if !chapters.isEmpty {
            info[MPNowPlayingInfoPropertyChapterCount] = chapters.count
            if let chapter = currentChapter {
                info[MPNowPlayingInfoPropertyChapterNumber] = chapter.chapterIndex
            }
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    
    private func loadNowPlayingArtwork(from urlString: String?) {
        guard let urlString = urlString, let url = URL(string: urlString) else { return }
        
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let image = UIImage(data: data) else { return }
                
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                self.nowPlayingArtwork = artwork
                self.updateNowPlayingInfo()
                print("[AudioPlayer] Now playing artwork loaded")
            } catch {
                print("[AudioPlayer] Failed to load artwork: \(error)")
            }
        }
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
        guard currentAudiobook != nil || currentPodcastEpisode != nil else {
            print("[AudioPlayer] No current content, ignoring bookmark")
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
        
        if let audiobook = currentAudiobook {
            // Audiobook highlight
            let chapter = currentChapter?.title
            let isTranscribed = audiobook.transcribed
            let bookId = audiobook.id
            
            print("[AudioPlayer] Audiobook bookmark at \(formatTime(position))")
            
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
                    print("[AudioPlayer] Audiobook bookmark complete: \(highlightId.prefix(8))...")
                }
            }
        } else if let episode = currentPodcastEpisode {
            // Podcast highlight
            let isTranscribed = episode.isTranscribed
            let episodeId = episode.id
            let podcastId = episode.podcastId
            let episodeTitle = episode.title
            
            print("[AudioPlayer] Podcast bookmark at \(formatTime(position))")
            
            Task {
                let highlightId = await PodcastHighlightManager.shared.createHighlight(
                    episodeId: episodeId,
                    podcastId: podcastId,
                    positionSeconds: position,
                    episodeTitle: episodeTitle,
                    isTranscribed: isTranscribed
                )
                
                await MainActor.run {
                    self.lastHighlightId = highlightId
                    self.isCreatingHighlight = false
                    print("[AudioPlayer] Podcast bookmark complete: \(highlightId.prefix(8))...")
                }
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
                pushNowPlayingToWidgetIfNeeded()
            }
        }
    }
    
    private func syncPosition() async {
        // Handle podcast episodes separately
        if currentPodcastEpisode != nil {
            await syncPodcastPosition()
            return
        }
        
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
    
    // MARK: - Widget Data Push
    
    private var lastWidgetPushTime: Date = .distantPast
    private var lastCachedCoverId: String?
    
    func pushNowPlayingToWidget() {
        guard let audiobook = currentAudiobook else {
            WidgetDataManager.shared.updateNowPlaying(nil)
            WidgetDataManager.shared.reloadWidgets()
            return
        }
        
        let nowPlaying = WidgetNowPlaying(
            audiobookId: audiobook.id,
            title: audiobook.title,
            author: audiobook.author,
            coverUrl: audiobook.coverUrl,
            progress: progress,
            currentTime: currentTime,
            duration: duration,
            isPlaying: isPlaying,
            chapterTitle: currentChapter?.title,
            updatedAt: Date()
        )
        
        WidgetDataManager.shared.updateNowPlaying(nowPlaying)
        WidgetDataManager.shared.reloadWidgets()
        lastWidgetPushTime = Date()
        
        // Cache cover image to App Group container for widget (only once per book)
        if lastCachedCoverId != audiobook.id {
            cacheWidgetCoverImage(for: audiobook)
        }
    }
    
    private func cacheWidgetCoverImage(for audiobook: Audiobook) {
        let bookId = audiobook.id
        
        // Check in-memory cache first
        if let coverUrl = audiobook.coverUrl, let cached = CoverImageCache.shared.get(coverUrl) {
            print("[Widget] Cover found in memory cache for \(bookId)")
            if let jpegData = cached.jpegData(compressionQuality: 0.7) {
                WidgetDataManager.shared.saveCoverImage(jpegData, for: bookId)
                WidgetDataManager.shared.clearOldCoverImages(except: bookId)
                lastCachedCoverId = bookId
                WidgetDataManager.shared.reloadWidgets()
            }
            return
        }
        
        // Fetch asynchronously
        guard let coverUrl = audiobook.coverUrl, !coverUrl.isEmpty else {
            print("[Widget] No coverUrl for \(bookId)")
            return
        }
        print("[Widget] Fetching cover for widget: \(coverUrl)")
        Task { [coverUrl] in
            do {
                let data: Data
                if coverUrl.hasPrefix("http") {
                    let (fetchedData, _) = try await URLSession.shared.data(from: URL(string: coverUrl)!)
                    data = fetchedData
                } else {
                    data = try await LibroAIService.shared.fetchCoverImageData(coverPath: coverUrl)
                }
                print("[Widget] Cover fetched: \(data.count) bytes")
                if let image = UIImage(data: data),
                   let jpegData = image.jpegData(compressionQuality: 0.7) {
                    WidgetDataManager.shared.saveCoverImage(jpegData, for: bookId)
                    WidgetDataManager.shared.clearOldCoverImages(except: bookId)
                    self.lastCachedCoverId = bookId
                    WidgetDataManager.shared.reloadWidgets()
                    print("[Widget] Cover saved and widget reloaded for \(bookId)")
                }
            } catch {
                print("[Widget] Failed to cache cover for widget: \(error)")
            }
        }
    }
    
    private func pushNowPlayingToWidgetIfNeeded() {
        // Throttle periodic updates to every 60 seconds
        guard Date().timeIntervalSince(lastWidgetPushTime) >= 60 else { return }
        pushNowPlayingToWidget()
    }
    
    // MARK: - Player Item Observation
    
    private func observePlayerItem() {
        guard let playerItem = playerItem else { return }
        
        // Observe duration — for MP3 streams, duration may become available after buffering
        durationObservation = playerItem.observe(\.duration, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self = self else { return }
                let newDuration = item.duration.seconds
                let metadataDuration = self.currentAudiobook?.durationSeconds ?? 0
                // Only accept if it's reasonable (at least 50% of metadata, or no metadata to compare)
                if newDuration.isFinite && newDuration > 0 && newDuration > self.duration {
                    if metadataDuration <= 0 || newDuration >= metadataDuration * 0.5 {
                        print("[AudioPlayer] Duration updated from stream: \(newDuration)s")
                        self.duration = newDuration
                        self.updateNowPlayingInfo()
                    }
                }
            }
        }
        
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
                    let itemDuration = item.duration.seconds
                    let metadataDuration = self.currentAudiobook?.durationSeconds ?? 0
                    
                    if itemDuration.isFinite && itemDuration > 0 && (metadataDuration <= 0 || itemDuration >= metadataDuration * 0.5) {
                        // AVPlayer duration looks reasonable (at least 50% of metadata)
                        self.duration = itemDuration
                    } else if metadataDuration > 0 {
                        // AVPlayer reported nothing, or a suspiciously small value — use metadata
                        print("[AudioPlayer] AVPlayer duration (\(itemDuration)s) too small vs metadata (\(metadataDuration)s), using metadata")
                        self.duration = metadataDuration
                    } else if let episode = self.currentPodcastEpisode, let epDuration = episode.durationSeconds, epDuration > 0 {
                        if itemDuration.isFinite && itemDuration > 0 && itemDuration >= epDuration * 0.5 {
                            self.duration = itemDuration
                        } else {
                            print("[AudioPlayer] Using podcast episode metadata duration: \(epDuration)s")
                            self.duration = epDuration
                        }
                    } else if itemDuration.isFinite && itemDuration > 0 {
                        self.duration = itemDuration
                    }
                    self.isBuffering = false
                    
                    // Seek to saved position
                    if startPosition > 0 {
                        let time = CMTime(seconds: startPosition, preferredTimescale: 600)
                        let isMP3 = self.currentAudiobook?.format == .mp3
                        let tol = isMP3 ? CMTime(seconds: 0.5, preferredTimescale: 600) : CMTime.zero
                        self.player?.seek(to: time, toleranceBefore: tol, toleranceAfter: tol) { [weak self] _ in
                            Task { @MainActor in
                                self?.currentTime = startPosition
                                self?.updateCurrentChapter()
                                self?.player?.rate = Float(self?.playbackSpeed ?? 1.0)
                                self?.isPlaying = true
                                self?.updateNowPlayingInfo()
                                self?.startTimeObservation()
                                self?.startPositionSyncTimer()
                                self?.pushNowPlayingToWidget()
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
                        self.pushNowPlayingToWidget()
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
