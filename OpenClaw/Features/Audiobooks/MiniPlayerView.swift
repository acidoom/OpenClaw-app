//
//  MiniPlayerView.swift
//  OpenClaw
//
//  Compact now-playing bar for the audiobooks tab
//

import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject private var playerManager: AudioPlayerManager
    @EnvironmentObject private var appState: AppState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showFullPlayer = false
    
    var body: some View {
        if playerManager.hasActiveSession {
            VStack(spacing: 0) {
                // Thin progress bar
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.anthropicCoral)
                        .frame(width: geo.size.width * playerManager.progress)
                }
                .frame(height: 2)
                .background(Color.surfaceSecondary)
                
                // Content
                HStack(spacing: 12) {
                    // Small cover art
                    miniPlayerArtwork
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    
                    // Title + chapter/status
                    VStack(alignment: .leading, spacing: 2) {
                        Text(miniPlayerTitle)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                        
                        if let error = playerManager.playerError {
                            Text(error)
                                .font(.caption2)
                                .foregroundStyle(.red)
                                .lineLimit(1)
                        } else if playerManager.isBuffering {
                            Text("Buffering...")
                                .font(.caption2)
                                .foregroundStyle(Color.anthropicCoral)
                        } else if let subtitle = miniPlayerSubtitle {
                            Text(subtitle)
                                .font(.caption2)
                                .foregroundStyle(Color.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    
                    Spacer()
                    
                    // Play/Pause
                    Button {
                        playerManager.togglePlayPause()
                    } label: {
                        Image(systemName: playerManager.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                            .foregroundStyle(Color.anthropicCoral)
                    }
                    
                    // Skip forward
                    Button {
                        playerManager.skipForward(30)
                    } label: {
                        Image(systemName: "goforward.30")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .background(Color.surfaceElevated)
            .contentShape(Rectangle())
            .onTapGesture {
                if horizontalSizeClass == .regular {
                    withAnimation { appState.isSidebarPlayerExpanded = true }
                } else {
                    showFullPlayer = true
                }
            }
            .fullScreenCover(isPresented: $showFullPlayer) {
                AudioPlayerView()
                    .environmentObject(playerManager)
            }
        }
    }
    
    private var miniPlayerTitle: String {
        if let audiobook = playerManager.currentAudiobook {
            return audiobook.title
        } else if let episode = playerManager.currentPodcastEpisode {
            return episode.title
        }
        return ""
    }
    
    private var miniPlayerSubtitle: String? {
        if let chapter = playerManager.currentChapter {
            return chapter.title
        } else if let podcast = playerManager.currentPodcast {
            return podcast.title
        }
        return nil
    }
    
    @ViewBuilder
    private var miniPlayerArtwork: some View {
        if let audiobook = playerManager.currentAudiobook {
            CoverImageView(coverUrl: audiobook.coverUrl, cornerRadius: 6)
        } else if let episode = playerManager.currentPodcastEpisode {
            AsyncImage(url: URL(string: episode.artworkUrl ?? playerManager.currentPodcast?.artworkUrl ?? "")) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.surfaceSecondary)
                    .overlay(
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.caption2)
                            .foregroundStyle(Color.textTertiary)
                    )
            }
        }
    }
}
