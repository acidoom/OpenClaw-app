//
//  PodcastDetailView.swift
//  OpenClaw
//
//  Podcast info with episode list
//

import SwiftUI
import Combine

@MainActor
final class PodcastDetailViewModel: ObservableObject {
    @Published var episodes: [PodcastEpisode] = []
    @Published var isLoading = false
    @Published var isRefreshing = false
    @Published var errorMessage: String?
    @Published var episodeSort: EpisodeSortOrder = .newest
    
    let podcast: Podcast
    private let service = PodcastService.shared
    private var currentPage = 1
    private var hasMore = true
    
    init(podcast: Podcast) {
        self.podcast = podcast
    }
    
    var sortedEpisodes: [PodcastEpisode] {
        switch episodeSort {
        case .newest:
            return episodes.sorted { ($0.publishedAt ?? "") > ($1.publishedAt ?? "") }
        case .oldest:
            return episodes.sorted { ($0.publishedAt ?? "") < ($1.publishedAt ?? "") }
        }
    }
    
    func loadEpisodes() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        currentPage = 1
        
        do {
            episodes = try await service.fetchEpisodes(podcastId: podcast.id, page: 1)
            hasMore = episodes.count >= 50
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func loadMore() async {
        guard hasMore, !isLoading else { return }
        isLoading = true
        currentPage += 1
        
        do {
            let newEpisodes = try await service.fetchEpisodes(podcastId: podcast.id, page: currentPage)
            episodes.append(contentsOf: newEpisodes)
            hasMore = newEpisodes.count >= 50
        } catch {
            currentPage -= 1
            print("[PodcastDetail] Load more failed: \(error)")
        }
        
        isLoading = false
    }
    
    func refreshFeed() async {
        isRefreshing = true
        do {
            _ = try await service.refreshFeed(podcastId: podcast.id)
            await loadEpisodes()
        } catch {
            errorMessage = error.localizedDescription
        }
        isRefreshing = false
    }
}

struct PodcastDetailView: View {
    let podcast: Podcast
    @ObservedObject var libraryViewModel: PodcastsViewModel
    @StateObject private var viewModel: PodcastDetailViewModel
    @EnvironmentObject private var playerManager: AudioPlayerManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedEpisode: PodcastEpisode?
    
    init(podcast: Podcast, libraryViewModel: PodcastsViewModel) {
        self.podcast = podcast
        self.libraryViewModel = libraryViewModel
        self._viewModel = StateObject(wrappedValue: PodcastDetailViewModel(podcast: podcast))
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundDark.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Header
                        headerSection
                        
                        // Actions
                        actionsSection
                        
                        // Episodes
                        episodesSection
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
            .navigationTitle(podcast.title)
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
            .sheet(item: $selectedEpisode) { episode in
                EpisodeDetailView(episode: episode, podcast: podcast)
                    .environmentObject(playerManager)
            }
            .onChange(of: selectedEpisode) { oldValue, newValue in
                // When sheet dismisses, refresh episodes to pick up transcription status changes
                if oldValue != nil && newValue == nil {
                    Task { await viewModel.loadEpisodes() }
                }
            }
            .task {
                await viewModel.loadEpisodes()
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        HStack(spacing: 16) {
            // Artwork
            AsyncImage(url: URL(string: podcast.artworkUrl ?? "")) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.surfaceSecondary)
                    .overlay(
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.title)
                            .foregroundStyle(Color.textTertiary)
                    )
            }
            .frame(width: horizontalSizeClass == .regular ? 160 : 120, height: horizontalSizeClass == .regular ? 160 : 120)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            // Info
            VStack(alignment: .leading, spacing: 6) {
                Text(podcast.title)
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(3)
                
                Text(podcast.author)
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                
                if let count = podcast.episodeCount {
                    Text("\(count) episodes")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }
    
    // MARK: - Actions
    
    private var actionsSection: some View {
        HStack(spacing: 12) {
            Button {
                Task { await viewModel.refreshFeed() }
            } label: {
                HStack(spacing: 6) {
                    if viewModel.isRefreshing {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text("Refresh Feed")
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.surfaceSecondary)
                .foregroundStyle(Color.textPrimary)
                .clipShape(Capsule())
            }
            .disabled(viewModel.isRefreshing)
            
            Button(role: .destructive) {
                Task {
                    await libraryViewModel.unsubscribe(podcastId: podcast.id)
                    dismiss()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "xmark")
                    Text("Unsubscribe")
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.statusDisconnected.opacity(0.2))
                .foregroundStyle(Color.statusDisconnected)
                .clipShape(Capsule())
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
    }
    
    // MARK: - Episodes
    
    private var episodesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                Text("EPISODES")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.textTertiary)
                
                Spacer()
                
                Menu {
                    ForEach(EpisodeSortOrder.allCases, id: \.self) { order in
                        Button {
                            viewModel.episodeSort = order
                        } label: {
                            HStack {
                                Text(order.displayName)
                                if viewModel.episodeSort == order {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(viewModel.episodeSort.displayName)
                            .font(.caption2)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                    }
                    .foregroundStyle(Color.anthropicCoral)
                }
            }
            .padding(.horizontal, 16)
            
            if viewModel.isLoading && viewModel.episodes.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                        .tint(Color.anthropicCoral)
                    Spacer()
                }
                .padding(.vertical, 24)
            } else if let error = viewModel.errorMessage, viewModel.episodes.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Color.statusDisconnected)
                    .padding(.horizontal, 16)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.sortedEpisodes) { episode in
                        EpisodeRow(episode: episode) {
                            selectedEpisode = episode
                        }
                        
                        if episode.id != viewModel.sortedEpisodes.last?.id {
                            Divider()
                                .padding(.leading, 16)
                        }
                    }
                }
                .background(Color.surfaceSecondary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
            }
        }
    }
}

// MARK: - Episode Row

struct EpisodeRow: View {
    let episode: PodcastEpisode
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(episode.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    HStack(spacing: 8) {
                        if let date = episode.formattedDate as String?, !date.isEmpty {
                            Text(date)
                                .font(.caption2)
                                .foregroundStyle(Color.textTertiary)
                        }
                        
                        if !episode.formattedDuration.isEmpty {
                            Text(episode.formattedDuration)
                                .font(.caption2)
                                .foregroundStyle(Color.textTertiary)
                        }
                        
                        if episode.isTranscribed {
                            HStack(spacing: 2) {
                                Image(systemName: "text.quote")
                                    .font(.system(size: 8))
                                Text("Transcribed")
                                    .font(.system(size: 9))
                            }
                            .foregroundStyle(Color.statusConnected)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.statusConnected.opacity(0.15), in: Capsule())
                        }
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
