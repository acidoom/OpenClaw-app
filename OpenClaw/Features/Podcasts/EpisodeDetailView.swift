//
//  EpisodeDetailView.swift
//  OpenClaw
//
//  Episode info with play button, transcription status, and AI highlights
//

import SwiftUI

struct EpisodeDetailView: View {
    @State private var episode: PodcastEpisode
    let podcast: Podcast
    @EnvironmentObject private var playerManager: AudioPlayerManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var highlightsViewModel: PodcastHighlightsViewModel
    @State private var isRequestingTranscription = false
    @State private var transcriptionError: String?
    @State private var transcriptionPollTask: Task<Void, Never>?
    
    init(episode: PodcastEpisode, podcast: Podcast) {
        self._episode = State(initialValue: episode)
        self.podcast = podcast
        self._highlightsViewModel = StateObject(wrappedValue: PodcastHighlightsViewModel(
            episodeId: episode.id,
            isTranscribed: episode.isTranscribed
        ))
    }
    
    private var isCurrentlyPlaying: Bool {
        playerManager.currentPodcastEpisode?.id == episode.id
    }
    
    /// All unique references aggregated from completed highlights
    private var allReferences: [PodcastReference] {
        var seen = Set<String>()
        return highlightsViewModel.highlights
            .filter { $0.status == .completed }
            .flatMap { $0.references ?? [] }
            .filter { seen.insert($0.id).inserted }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundDark.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Header
                        headerSection
                        
                        // Play button
                        playSection
                        
                        // Transcription status
                        transcriptionSection
                        
                        // References (aggregated from highlights)
                        if !allReferences.isEmpty {
                            referencesSection
                        }
                        
                        // Description
                        if let description = episode.description, !description.isEmpty {
                            descriptionSection(description)
                        }
                        
                        // AI Highlights
                        PodcastHighlightsListView(viewModel: highlightsViewModel)
                            .padding(.horizontal, 16)
                    }
                    .padding(.bottom, (playerManager.hasActiveSession && horizontalSizeClass != .regular) ? 80 : 16)
                }
                
                // Mini player overlay (iPhone only; iPad handled by AdaptiveRootView)
                if playerManager.hasActiveSession && horizontalSizeClass != .regular {
                    VStack {
                        Spacer()
                        MiniPlayerView()
                    }
                }
            }
            .navigationTitle("Episode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.backgroundDark, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.anthropicCoral)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            // Resume polling if transcription is in progress
            if episode.transcriptionStatus == .queued || episode.transcriptionStatus == .processing {
                startTranscriptionPolling()
            }
        }
        .onDisappear {
            transcriptionPollTask?.cancel()
            transcriptionPollTask = nil
        }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        HStack(spacing: 16) {
            // Artwork
            AsyncImage(url: URL(string: episode.artworkUrl ?? podcast.artworkUrl ?? "")) { image in
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
            .frame(width: horizontalSizeClass == .regular ? 140 : 100, height: horizontalSizeClass == .regular ? 140 : 100)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            VStack(alignment: .leading, spacing: 6) {
                Text(episode.title)
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(3)
                
                Text(podcast.title)
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    if !episode.formattedDate.isEmpty {
                        Text(episode.formattedDate)
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                    }
                    
                    if !episode.formattedDuration.isEmpty {
                        Text(episode.formattedDuration)
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
                
                if let epNum = episode.episodeNumber {
                    let seasonText = episode.seasonNumber.map { "S\($0) " } ?? ""
                    Text("\(seasonText)E\(epNum)")
                        .font(.caption2)
                        .foregroundStyle(Color.anthropicCoral)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.anthropicCoral.opacity(0.15), in: Capsule())
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }
    
    // MARK: - Play Section
    
    private var playSection: some View {
        Button {
            Task {
                await playerManager.playPodcastEpisode(episode: episode, podcast: podcast)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isCurrentlyPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                Text(isCurrentlyPlaying ? "Now Playing" : "Play Episode")
                    .font(.headline)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.anthropicCoral, in: RoundedRectangle(cornerRadius: 14))
        }
        .padding(.horizontal, 16)
    }
    
    // MARK: - Transcription
    
    private var transcriptionSection: some View {
        HStack(spacing: 12) {
            // Status indicator
            Group {
                if episode.transcriptionStatus == .completed {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.statusConnected)
                        Text("Transcribed")
                            .font(.caption)
                            .foregroundStyle(Color.statusConnected)
                    }
                } else if episode.transcriptionStatus == .processing || episode.transcriptionStatus == .queued {
                    HStack(spacing: 6) {
                        ProgressView()
                            .tint(Color.anthropicOrange)
                            .scaleEffect(0.7)
                        Text("Transcribing...")
                            .font(.caption)
                            .foregroundStyle(Color.anthropicOrange)
                    }
                } else if episode.transcriptionStatus == .failed {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.statusDisconnected)
                        Text("Transcription failed")
                            .font(.caption)
                            .foregroundStyle(Color.statusDisconnected)
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "text.quote")
                            .foregroundStyle(Color.textTertiary)
                        Text("Not transcribed")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }
            
            Spacer()
            
            // Request transcription button
            if episode.transcriptionStatus == nil || episode.transcriptionStatus == .none || episode.transcriptionStatus == .failed {
                Button {
                    requestTranscription()
                } label: {
                    HStack(spacing: 4) {
                        if isRequestingTranscription {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.6)
                        }
                        Text("Transcribe")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.surfaceSecondary)
                    .foregroundStyle(Color.textPrimary)
                    .clipShape(Capsule())
                }
                .disabled(isRequestingTranscription)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.surfaceSecondary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
    }
    
    // MARK: - Description
    
    private func descriptionSection(_ description: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DESCRIPTION")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Color.textTertiary)
            
            Text(stripHTML(description))
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }
    
    // MARK: - References Section
    
    private var referencesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section header
            HStack(spacing: 6) {
                Image(systemName: "link")
                    .font(.caption)
                    .foregroundStyle(Color.anthropicCoral)
                
                Text("REFERENCES")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.textTertiary)
                
                Spacer()
                
                Text("\(allReferences.count)")
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.surfaceSecondary, in: Capsule())
            }
            
            // Grouped by type
            let grouped = Dictionary(grouping: allReferences, by: { $0.type })
            let sortedTypes: [PodcastReferenceType] = [.paper, .book, .tool, .person]
            
            ForEach(sortedTypes.filter { grouped[$0] != nil }, id: \.self) { type in
                if let refs = grouped[type] {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(type.label.uppercased() + "S")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.textTertiary.opacity(0.7))
                            .padding(.top, 4)
                        
                        ForEach(refs) { ref in
                            EpisodeReferenceCard(reference: ref)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color.surfaceSecondary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }
    
    // MARK: - Actions
    
    private func requestTranscription() {
        isRequestingTranscription = true
        transcriptionError = nil
        
        Task {
            do {
                try await PodcastService.shared.requestTranscription(episodeId: episode.id, podcastId: episode.podcastId)
                // Immediate UI feedback
                episode.transcriptionStatus = .queued
                // Start polling for status updates
                startTranscriptionPolling()
            } catch {
                transcriptionError = error.localizedDescription
            }
            isRequestingTranscription = false
        }
    }
    
    private func startTranscriptionPolling() {
        transcriptionPollTask?.cancel()
        transcriptionPollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                guard !Task.isCancelled else { break }
                
                if let updated = try? await PodcastService.shared.fetchEpisode(
                    podcastId: episode.podcastId,
                    episodeId: episode.id
                ) {
                    episode.transcriptionStatus = updated.transcriptionStatus
                    print("[EpisodeDetail] Polled transcription status: \(updated.transcriptionStatus?.rawValue ?? "nil")")
                    
                    // Stop polling once terminal state
                    if updated.transcriptionStatus == .completed || updated.transcriptionStatus == .failed {
                        break
                    }
                }
            }
        }
    }
    
    /// Strip basic HTML tags from podcast descriptions
    private func stripHTML(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Episode Reference Card

struct EpisodeReferenceCard: View {
    let reference: PodcastReference
    @Environment(\.openURL) private var openURL
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: reference.type.icon)
                .font(.subheadline)
                .foregroundStyle(Color.anthropicCoral)
                .frame(width: 24, height: 24)
                .background(Color.anthropicCoral.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            
            VStack(alignment: .leading, spacing: 3) {
                Text(reference.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.textPrimary)
                
                if let authors = reference.authors, !authors.isEmpty {
                    Text(authors)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                
                if let description = reference.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(3)
                }
            }
            
            Spacer(minLength: 0)
            
            if let urlString = reference.url, let url = URL(string: urlString) {
                Button {
                    openURL(url)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption)
                        .foregroundStyle(Color.anthropicCoral)
                }
            }
        }
        .padding(10)
        .background(Color.backgroundDark.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }
}
