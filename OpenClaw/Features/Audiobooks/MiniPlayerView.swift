//
//  MiniPlayerView.swift
//  OpenClaw
//
//  Compact now-playing bar for the audiobooks tab
//

import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject private var playerManager: AudioPlayerManager
    @State private var showFullPlayer = false
    
    var body: some View {
        if let audiobook = playerManager.currentAudiobook {
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
                    coverImage(for: audiobook)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    
                    // Title + chapter/status
                    VStack(alignment: .leading, spacing: 2) {
                        Text(audiobook.title)
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
                        } else if let chapter = playerManager.currentChapter {
                            Text(chapter.title)
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
                showFullPlayer = true
            }
            .fullScreenCover(isPresented: $showFullPlayer) {
                AudioPlayerView()
                    .environmentObject(playerManager)
            }
        }
    }
    
    private func coverImage(for audiobook: Audiobook) -> some View {
        CoverImageView(coverUrl: audiobook.coverUrl, cornerRadius: 6)
    }
}
