//
//  AudioPlayerView.swift
//  OpenClaw
//
//  Full-screen now-playing view with controls
//

import SwiftUI
import AVKit

struct AudioPlayerView: View {
    @EnvironmentObject private var playerManager: AudioPlayerManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showSpeedPicker = false
    @State private var showChapterList = false
    @State private var showHighlightsList = false
    @State private var isDraggingSlider = false
    @State private var bookmarkBounce = false
    @State private var dragPosition: Double = 0
    
    var body: some View {
        ZStack {
            // Background gradient
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
            
            VStack(spacing: 0) {
                // Drag handle + close
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.textSecondary)
                    }
                    
                    Spacer()
                    
                    if playerManager.isDownloadingForSeek {
                        HStack(spacing: 6) {
                            ProgressView()
                                .tint(Color.anthropicCoral)
                                .scaleEffect(0.6)
                            Text("Downloading \(Int(playerManager.downloadForSeekProgress * 100))%")
                                .font(.caption2)
                                .foregroundStyle(Color.textTertiary)
                        }
                    } else if let chapter = playerManager.currentChapter, playerManager.hasChapters {
                        Text(chapter.title)
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    // Placeholder for symmetry
                    Color.clear.frame(width: 24, height: 24)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                
                Spacer()
                
                // Cover art
                coverArtView
                    .padding(.horizontal, 48)
                
                Spacer()
                
                // Title + Author
                titleSection
                
                // Progress slider
                progressSection
                    .padding(.top, 24)
                
                // Playback controls
                controlsSection
                    .padding(.top, 16)
                
                // Bottom toolbar
                bottomToolbar
                    .padding(.top, 24)
                
                Spacer(minLength: 32)
            }
            .padding(.horizontal, 24)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showChapterList) {
            ChapterListSheet()
                .environmentObject(playerManager)
        }
        .sheet(isPresented: $showHighlightsList) {
            if let audiobookId = playerManager.currentAudiobook?.id {
                NavigationStack {
                    HighlightsListView(audiobookId: audiobookId, isTranscribed: playerManager.currentAudiobook?.transcribed ?? false)
                        .environmentObject(playerManager)
                        .navigationTitle("AI Highlights")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { showHighlightsList = false }
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color.anthropicCoral)
                            }
                        }
                }
                .presentationDetents([.medium, .large])
                .preferredColorScheme(.dark)
            } else if let episode = playerManager.currentPodcastEpisode {
                NavigationStack {
                    PodcastHighlightsListView(episodeId: episode.id, isTranscribed: episode.isTranscribed)
                        .environmentObject(playerManager)
                        .navigationTitle("AI Highlights")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { showHighlightsList = false }
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color.anthropicCoral)
                            }
                        }
                }
                .presentationDetents([.medium, .large])
                .preferredColorScheme(.dark)
            }
        }
    }
    
    // MARK: - Cover Art
    
    @ViewBuilder
    private var coverArtView: some View {
        if playerManager.currentAudiobook != nil {
            CoverImageView(coverUrl: playerManager.currentAudiobook?.coverUrl, cornerRadius: 16)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: horizontalSizeClass == .regular ? 400 : 300, maxHeight: horizontalSizeClass == .regular ? 400 : 300)
                .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
        } else if let episode = playerManager.currentPodcastEpisode {
            AsyncImage(url: URL(string: episode.artworkUrl ?? playerManager.currentPodcast?.artworkUrl ?? "")) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.surfaceSecondary)
                    .overlay(
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.textTertiary)
                    )
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: horizontalSizeClass == .regular ? 400 : 300, maxHeight: horizontalSizeClass == .regular ? 400 : 300)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
        }
    }
    
    // MARK: - Title Section
    
    private var titleSection: some View {
        VStack(spacing: 4) {
            if let audiobook = playerManager.currentAudiobook {
                Text(audiobook.title)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                
                Text(audiobook.author)
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                
                if let narrator = audiobook.narrator {
                    Text("Narrated by \(narrator)")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)
                }
            } else if let episode = playerManager.currentPodcastEpisode {
                Text(episode.title)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                
                Text(playerManager.currentPodcast?.title ?? "")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                
                Text(playerManager.currentPodcast?.author ?? "")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
            }
        }
    }
    
    // MARK: - Progress
    
    private var progressSection: some View {
        VStack(spacing: 4) {
            Slider(
                value: $dragPosition,
                in: 0...max(playerManager.duration, 1)
            ) { editing in
                isDraggingSlider = editing
                if !editing {
                    playerManager.seek(to: dragPosition)
                }
            }
            .tint(Color.anthropicCoral)
            .onChange(of: playerManager.currentTime) { _, newValue in
                if !isDraggingSlider {
                    dragPosition = newValue
                }
            }
            
            HStack {
                Text(formatTime(dragPosition))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(Color.textSecondary)
                
                Spacer()
                
                Text("-\(formatTime(max(0, playerManager.duration - dragPosition)))")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(Color.textSecondary)
            }
            
            if let warning = playerManager.seekWarning {
                Text(warning)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
        }
    }
    
    // MARK: - Controls
    
    private var controlsSection: some View {
        HStack(spacing: 36) {
            // Skip back 15s
            Button {
                playerManager.skipBackward(15)
            } label: {
                Image(systemName: "gobackward.15")
                    .font(.title2)
                    .foregroundStyle(Color.textPrimary)
            }
            
            // Previous chapter (or skip back 5 min if no chapters)
            Button {
                playerManager.previousChapter()
            } label: {
                Image(systemName: playerManager.hasChapters ? "backward.end.fill" : "gobackward.5")
                    .font(.title3)
                    .foregroundStyle(Color.textPrimary)
            }
            
            // Play/Pause
            Button {
                playerManager.togglePlayPause()
            } label: {
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
            
            // Next chapter (or skip forward 5 min if no chapters)
            Button {
                playerManager.nextChapter()
            } label: {
                Image(systemName: playerManager.hasChapters ? "forward.end.fill" : "goforward.5")
                    .font(.title3)
                    .foregroundStyle(Color.textPrimary)
            }
            
            // Skip forward 30s
            Button {
                playerManager.skipForward(30)
            } label: {
                Image(systemName: "goforward.30")
                    .font(.title2)
                    .foregroundStyle(Color.textPrimary)
            }
        }
    }
    
    // MARK: - Bottom Toolbar
    
    private var bottomToolbar: some View {
        HStack {
            // Playback speed
            Button {
                showSpeedPicker.toggle()
            } label: {
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
            
            // Chapter list
            Button {
                showChapterList = true
            } label: {
                Image(systemName: "list.bullet")
                    .foregroundStyle(playerManager.hasChapters ? Color.textPrimary : Color.textTertiary)
            }
            .disabled(!playerManager.hasChapters)
            
            Spacer()
            
            // Bookmark / AI Highlight
            Button {
                bookmarkBounce = true
                playerManager.createHighlightManually()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    bookmarkBounce = false
                }
            } label: {
                Image(systemName: playerManager.isCreatingHighlight ? "bookmark.fill" : "bookmark")
                    .foregroundStyle(playerManager.isCreatingHighlight ? Color.anthropicCoral : Color.textPrimary)
                    .symbolEffect(.bounce, value: bookmarkBounce)
            }
            .disabled(playerManager.isCreatingHighlight || !playerManager.hasActiveSession)
            
            Spacer()
            
            // Highlights list
            Button {
                showHighlightsList = true
            } label: {
                Image(systemName: "text.book.closed")
                    .foregroundStyle(Color.textPrimary)
            }
            .disabled(!playerManager.hasActiveSession)
            
            Spacer()
            
            // AirPlay picker
            AirPlayButton()
                .frame(width: 24, height: 24)
        }
    }
}

// MARK: - Speed Picker

struct SpeedPickerView: View {
    @Binding var selectedSpeed: Double
    @Environment(\.dismiss) private var dismiss
    
    private let speeds: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0]
    
    var body: some View {
        VStack(spacing: 8) {
            Text("Playback Speed")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Color.textSecondary)
                .padding(.top, 12)
            
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], spacing: 8) {
                ForEach(speeds, id: \.self) { speed in
                    Button {
                        selectedSpeed = speed
                        dismiss()
                    } label: {
                        Text("\(speed, specifier: "%.2g")x")
                            .font(.subheadline)
                            .fontWeight(speed == selectedSpeed ? .bold : .regular)
                            .frame(minWidth: 56)
                            .padding(.vertical, 8)
                            .background(speed == selectedSpeed ? Color.anthropicCoral : Color.surfaceSecondary)
                            .foregroundStyle(speed == selectedSpeed ? .white : Color.textPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(width: 220)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Chapter List Sheet

struct ChapterListSheet: View {
    @EnvironmentObject private var playerManager: AudioPlayerManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundDark.ignoresSafeArea()
                
                ScrollViewReader { proxy in
                    List {
                        ForEach(playerManager.chapters) { chapter in
                            Button {
                                playerManager.goToChapter(chapter)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Text("\(chapter.chapterIndex + 1)")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundStyle(
                                            playerManager.currentChapter?.id == chapter.id
                                                ? Color.anthropicCoral
                                                : Color.textTertiary
                                        )
                                        .frame(width: 28)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(chapter.title)
                                            .font(.subheadline)
                                            .foregroundStyle(
                                                playerManager.currentChapter?.id == chapter.id
                                                    ? Color.anthropicCoral
                                                    : Color.textPrimary
                                            )
                                            .lineLimit(2)
                                        
                                        Text(chapter.formattedDuration)
                                            .font(.caption2)
                                            .foregroundStyle(Color.textTertiary)
                                    }
                                    
                                    Spacer()
                                    
                                    if playerManager.currentChapter?.id == chapter.id {
                                        Image(systemName: "speaker.wave.2.fill")
                                            .font(.caption)
                                            .foregroundStyle(Color.anthropicCoral)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .listRowBackground(Color.surfacePrimary)
                            .id(chapter.id)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .onAppear {
                        if let current = playerManager.currentChapter {
                            proxy.scrollTo(current.id, anchor: .center)
                        }
                    }
                }
            }
            .navigationTitle("Chapters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.anthropicCoral)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }
}

// MARK: - AirPlay Button

struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = UIColor(Color.textPrimary)
        picker.activeTintColor = UIColor(Color.anthropicCoral)
        return picker
    }
    
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
