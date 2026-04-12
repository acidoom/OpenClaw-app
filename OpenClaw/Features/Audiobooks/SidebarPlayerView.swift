//
//  SidebarPlayerView.swift
//  OpenClaw
//
//  Persistent right-column audio player for iPad landscape
//

import SwiftUI
import AVKit

struct SidebarPlayerView: View {
    @EnvironmentObject private var playerManager: AudioPlayerManager
    @EnvironmentObject private var appState: AppState
    @State private var showSpeedPicker = false
    @State private var showChapterList = false
    @State private var showHighlightsList = false
    @State private var isDraggingSlider = false
    @State private var bookmarkBounce = false
    @State private var dragPosition: Double = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Collapse button
            HStack {
                if let chapter = playerManager.currentChapter {
                    Text(chapter.title)
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    withAnimation { appState.isSidebarPlayerExpanded = false }
                } label: {
                    Image(systemName: "sidebar.trailing")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            
            Divider()
            
            ScrollView {
                VStack(spacing: 16) {
                    // Cover art
                    sidebarCoverArt
                        .padding(.top, 16)
                    
                    // Title + subtitle
                    titleSection
                    
                    // Progress
                    progressSection
                        .padding(.horizontal, 4)
                    
                    // Controls
                    controlsSection
                    
                    // Toolbar (speed, chapters, bookmark, highlights, AirPlay)
                    toolbarSection
                    
                    Divider()
                        .padding(.vertical, 4)
                    
                    // Inline highlights
                    highlightsSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .background(Color.surfacePrimary)
        .sheet(isPresented: $showChapterList) {
            ChapterListSheet()
                .environmentObject(playerManager)
        }
    }
    
    // MARK: - Cover Art
    
    @ViewBuilder
    private var sidebarCoverArt: some View {
        if let audiobook = playerManager.currentAudiobook {
            CoverImageView(coverUrl: audiobook.coverUrl, cornerRadius: 12)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 200, maxHeight: 200)
                .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
        } else if let episode = playerManager.currentPodcastEpisode {
            AsyncImage(url: URL(string: episode.artworkUrl ?? playerManager.currentPodcast?.artworkUrl ?? "")) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.surfaceSecondary)
                    .overlay(
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.title2)
                            .foregroundStyle(Color.textTertiary)
                    )
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 200, maxHeight: 200)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
        }
    }
    
    // MARK: - Title
    
    private var titleSection: some View {
        VStack(spacing: 4) {
            if let audiobook = playerManager.currentAudiobook {
                Text(audiobook.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                
                Text(audiobook.author)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            } else if let episode = playerManager.currentPodcastEpisode {
                Text(episode.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                
                Text(playerManager.currentPodcast?.title ?? "")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
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
        }
    }
    
    // MARK: - Controls
    
    private var controlsSection: some View {
        HStack(spacing: 24) {
            Button {
                playerManager.skipBackward(15)
            } label: {
                Image(systemName: "gobackward.15")
                    .font(.body)
                    .foregroundStyle(Color.textPrimary)
            }
            
            Button {
                playerManager.previousChapter()
            } label: {
                Image(systemName: playerManager.hasChapters ? "backward.end.fill" : "gobackward.5")
                    .font(.subheadline)
                    .foregroundStyle(Color.textPrimary)
            }
            
            Button {
                playerManager.togglePlayPause()
            } label: {
                ZStack {
                    if playerManager.isBuffering {
                        ProgressView()
                            .tint(Color.anthropicCoral)
                            .scaleEffect(1.2)
                    } else {
                        Image(systemName: playerManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.anthropicCoral)
                    }
                }
                .frame(width: 48, height: 48)
            }
            .disabled(playerManager.isBuffering)
            
            Button {
                playerManager.nextChapter()
            } label: {
                Image(systemName: playerManager.hasChapters ? "forward.end.fill" : "goforward.5")
                    .font(.subheadline)
                    .foregroundStyle(Color.textPrimary)
            }
            
            Button {
                playerManager.skipForward(30)
            } label: {
                Image(systemName: "goforward.30")
                    .font(.body)
                    .foregroundStyle(Color.textPrimary)
            }
        }
    }
    
    // MARK: - Toolbar
    
    private var toolbarSection: some View {
        HStack {
            // Speed
            Button {
                showSpeedPicker.toggle()
            } label: {
                Text("\(playerManager.playbackSpeed, specifier: "%.1f")x")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
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
            
            // Chapters
            Button {
                showChapterList = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.caption)
                    .foregroundStyle(playerManager.hasChapters ? Color.textPrimary : Color.textTertiary)
            }
            .disabled(!playerManager.hasChapters)
            
            Spacer()
            
            // Bookmark
            Button {
                bookmarkBounce = true
                playerManager.createHighlightManually()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    bookmarkBounce = false
                }
            } label: {
                Image(systemName: playerManager.isCreatingHighlight ? "bookmark.fill" : "bookmark")
                    .font(.caption)
                    .foregroundStyle(playerManager.isCreatingHighlight ? Color.anthropicCoral : Color.textPrimary)
                    .symbolEffect(.bounce, value: bookmarkBounce)
            }
            .disabled(playerManager.isCreatingHighlight || !playerManager.hasActiveSession)
            
            Spacer()
            
            // AirPlay
            AirPlayButton()
                .frame(width: 20, height: 20)
        }
    }
    
    // MARK: - Highlights
    
    @ViewBuilder
    private var highlightsSection: some View {
        if let audiobookId = playerManager.currentAudiobook?.id {
            VStack(alignment: .leading, spacing: 8) {
                Text("AI HIGHLIGHTS")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.textTertiary)
                
                HighlightsListView(
                    audiobookId: audiobookId,
                    isTranscribed: playerManager.currentAudiobook?.transcribed ?? false
                )
                .environmentObject(playerManager)
            }
        } else if let episode = playerManager.currentPodcastEpisode {
            VStack(alignment: .leading, spacing: 8) {
                Text("AI HIGHLIGHTS")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.textTertiary)
                
                PodcastHighlightsListView(
                    episodeId: episode.id,
                    isTranscribed: episode.isTranscribed
                )
                .environmentObject(playerManager)
            }
        }
    }
}
