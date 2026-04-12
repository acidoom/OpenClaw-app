//
//  PaperAudioPlayerView.swift
//  OpenClaw
//
//  Full-screen player for paper audiobooks with section navigation and transcript
//

import SwiftUI

struct PaperAudioPlayerView: View {
    let job: PaperAudioJob
    
    @EnvironmentObject private var playerManager: AudioPlayerManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var manifest: PaperAudioManifest?
    @State private var isLoadingManifest = true
    @State private var loadError: String?
    @State private var showSectionList = false
    @State private var showTranscript = false
    @State private var showSpeedPicker = false
    @State private var isDraggingSlider = false
    @State private var dragPosition: Double = 0
    
    private let service = PaperAudioService.shared
    
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.backgroundDark,
                    Color.surfacePrimary.opacity(0.8),
                    Color.backgroundDark
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            if isLoadingManifest {
                loadingView
            } else if let error = loadError {
                errorView(error)
            } else {
                playerContent
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSectionList) {
            sectionListSheet
        }
        .sheet(isPresented: $showTranscript) {
            transcriptSheet
        }
        .task {
            await loadManifestAndPlay()
        }
    }
    
    // MARK: - Loading
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(Color.anthropicCoral)
                .scaleEffect(1.5)
            Text("Loading paper audio...")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
        }
    }
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(Color.statusDisconnected)
            Text("Failed to Load")
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                Task { await loadManifestAndPlay() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                    Text("Retry")
                }
                .fontWeight(.semibold)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.anthropicCoral)
                .foregroundStyle(.white)
                .clipShape(Capsule())
            }
            
            Button("Dismiss") { dismiss() }
                .foregroundStyle(Color.textSecondary)
                .padding(.top, 8)
        }
    }
    
    // MARK: - Player Content
    
    private var playerContent: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.down")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.textSecondary)
                }
                
                Spacer()
                
                if let chapter = playerManager.currentChapter {
                    Text(chapter.title)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Mode badge
                HStack(spacing: 4) {
                    Image(systemName: job.mode.iconName)
                        .font(.caption2)
                    Text(job.mode.displayName)
                        .font(.caption2)
                        .fontWeight(.medium)
                }
                .foregroundStyle(Color.anthropicCoral)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.anthropicCoral.opacity(0.15))
                .clipShape(Capsule())
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            
            Spacer()
            
            // Paper "cover" illustration
            paperCoverView
            
            Spacer()
            
            // Title
            titleSection
            
            // Progress slider
            progressSection
                .padding(.top, 24)
            
            // Controls
            controlsSection
                .padding(.top, 16)
            
            // Bottom toolbar
            bottomToolbar
                .padding(.top, 24)
            
            Spacer(minLength: 32)
        }
        .padding(.horizontal, 24)
    }
    
    // MARK: - Paper Cover
    
    private var paperCoverView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [Color.surfaceSecondary, Color.surfaceElevated],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: horizontalSizeClass == .regular ? 320 : 240, height: horizontalSizeClass == .regular ? 320 : 240)
                .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
            
            VStack(spacing: 16) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.anthropicCoral.opacity(0.7))
                
                Image(systemName: "waveform")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.anthropicCoral.opacity(0.5))
            }
        }
    }
    
    // MARK: - Title
    
    private var titleSection: some View {
        VStack(spacing: 4) {
            Text(job.paperTitle)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            
            Text("Paper Audio • \(job.mode.displayName)")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
            
            if let manifest = manifest {
                Text(manifest.formattedDuration)
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            }
        }
    }
    
    // MARK: - Progress
    
    private var progressSection: some View {
        VStack(spacing: 4) {
            Slider(
                value: isDraggingSlider
                    ? $dragPosition
                    : Binding(
                        get: { playerManager.currentTime },
                        set: { _ in }
                    ),
                in: 0...max(playerManager.duration, 1)
            ) { editing in
                if editing {
                    isDraggingSlider = true
                    dragPosition = playerManager.currentTime
                } else {
                    isDraggingSlider = false
                    playerManager.seek(to: dragPosition)
                }
            }
            .tint(Color.anthropicCoral)
            
            HStack {
                Text(formatTime(isDraggingSlider ? dragPosition : playerManager.currentTime))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(Color.textSecondary)
                
                Spacer()
                
                Text("-\(formatTime(playerManager.remainingTime))")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }
    
    // MARK: - Controls
    
    private var controlsSection: some View {
        HStack(spacing: 36) {
            Button { playerManager.skipBackward(15) } label: {
                Image(systemName: "gobackward.15")
                    .font(.title2)
                    .foregroundStyle(Color.textPrimary)
            }
            
            Button { playerManager.previousChapter() } label: {
                Image(systemName: "backward.end.fill")
                    .font(.title3)
                    .foregroundStyle(Color.textPrimary)
            }
            
            Button { playerManager.togglePlayPause() } label: {
                ZStack {
                    if playerManager.isBuffering {
                        ProgressView()
                            .tint(Color.anthropicCoral)
                            .scaleEffect(1.5)
                    } else {
                        Image(systemName: playerManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(Color.anthropicCoral)
                    }
                }
                .frame(width: 64, height: 64)
            }
            .disabled(playerManager.isBuffering)
            
            Button { playerManager.nextChapter() } label: {
                Image(systemName: "forward.end.fill")
                    .font(.title3)
                    .foregroundStyle(Color.textPrimary)
            }
            
            Button { playerManager.skipForward(30) } label: {
                Image(systemName: "goforward.30")
                    .font(.title2)
                    .foregroundStyle(Color.textPrimary)
            }
        }
    }
    
    // MARK: - Bottom Toolbar
    
    private var bottomToolbar: some View {
        HStack {
            // Speed
            Button { showSpeedPicker.toggle() } label: {
                Text("\(playerManager.playbackSpeed, specifier: "%.1f")x")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.surfaceSecondary)
                    .clipShape(Capsule())
                    .foregroundStyle(Color.textPrimary)
            }
            .popover(isPresented: $showSpeedPicker) {
                SpeedPickerView(selectedSpeed: Binding(
                    get: { playerManager.playbackSpeed },
                    set: { playerManager.playbackSpeed = $0 }
                ))
                .presentationCompactAdaptation(.popover)
            }
            
            Spacer()
            
            // Section list
            Button { showSectionList = true } label: {
                Image(systemName: "list.bullet")
                    .foregroundStyle(Color.textPrimary)
            }
            
            Spacer()
            
            // Transcript
            Button { showTranscript = true } label: {
                Image(systemName: "text.alignleft")
                    .foregroundStyle(Color.textPrimary)
            }
            
            Spacer()
            
            // AirPlay
            AirPlayButton()
                .frame(width: 24, height: 24)
        }
    }
    
    // MARK: - Section List Sheet
    
    private var sectionListSheet: some View {
        NavigationStack {
            ZStack {
                Color.backgroundDark.ignoresSafeArea()
                
                if let manifest = manifest {
                    ScrollViewReader { proxy in
                        List {
                            ForEach(Array(manifest.sections.enumerated()), id: \.element.id) { index, section in
                                Button {
                                    playerManager.seek(to: section.startSec)
                                    showSectionList = false
                                } label: {
                                    HStack(spacing: 12) {
                                        Text("\(index + 1)")
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .foregroundStyle(
                                                playerManager.currentChapter?.chapterIndex == index
                                                    ? Color.anthropicCoral
                                                    : Color.textTertiary
                                            )
                                            .frame(width: 28)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(section.name)
                                                .font(.subheadline)
                                                .foregroundStyle(
                                                    playerManager.currentChapter?.chapterIndex == index
                                                        ? Color.anthropicCoral
                                                        : Color.textPrimary
                                                )
                                            
                                            Text(section.formattedDuration)
                                                .font(.caption2)
                                                .foregroundStyle(Color.textTertiary)
                                        }
                                        
                                        Spacer()
                                        
                                        if playerManager.currentChapter?.chapterIndex == index {
                                            Image(systemName: "speaker.wave.2.fill")
                                                .font(.caption)
                                                .foregroundStyle(Color.anthropicCoral)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                                .listRowBackground(Color.surfacePrimary)
                                .id(section.id)
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .onAppear {
                            if let currentIndex = playerManager.currentChapter?.chapterIndex,
                               currentIndex < manifest.sections.count {
                                proxy.scrollTo(manifest.sections[currentIndex].id, anchor: .center)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Sections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showSectionList = false }
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.anthropicCoral)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Transcript Sheet
    
    private var transcriptSheet: some View {
        NavigationStack {
            ZStack {
                Color.backgroundDark.ignoresSafeArea()
                
                if let manifest = manifest {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            ForEach(manifest.sections) { section in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(section.name.uppercased())
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(Color.anthropicCoral)
                                        .tracking(0.5)
                                    
                                    ForEach(section.chunks) { chunk in
                                        Text(chunk.text)
                                            .font(.subheadline)
                                            .foregroundStyle(Color.textPrimary)
                                            .lineSpacing(4)
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                } else {
                    Text("No transcript available")
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .navigationTitle("Transcript")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showTranscript = false }
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.anthropicCoral)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Load & Play
    
    private func loadManifestAndPlay() async {
        isLoadingManifest = true
        loadError = nil
        
        do {
            let fetchedManifest = try await service.fetchManifest(jobId: job.id)
            manifest = fetchedManifest
            
            // Build Audiobook and chapters from manifest for AudioPlayerManager
            await playPaperAudio(job: job, manifest: fetchedManifest)
        } catch {
            loadError = error.localizedDescription
            print("[PaperAudioPlayer] Failed to load manifest: \(error)")
        }
        
        isLoadingManifest = false
    }
    
    private func playPaperAudio(job: PaperAudioJob, manifest: PaperAudioManifest) async {
        let audiobook = Audiobook(
            id: "paper-\(job.id)",
            title: job.paperTitle,
            author: "Paper Audio",
            narrator: job.mode.displayName,
            durationSeconds: manifest.totalDurationSec,
            coverUrl: nil,
            localPath: nil,
            format: .mp3,
            downloaded: true,
            transcribed: false,
            indexed: false,
            summarized: false,
            diarized: false
        )
        
        await playerManager.playPaperAudio(audiobook: audiobook, jobId: job.id)
    }
}
