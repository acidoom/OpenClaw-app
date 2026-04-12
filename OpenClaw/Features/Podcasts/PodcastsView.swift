//
//  PodcastsView.swift
//  OpenClaw
//
//  Main podcast library tab view
//

import SwiftUI

struct PodcastsView: View {
    @StateObject private var viewModel = PodcastsViewModel()
    @EnvironmentObject private var playerManager: AudioPlayerManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedPodcast: Podcast?
    @State private var selectedEpisode: PodcastEpisode?
    @State private var showingSearch = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundDark.ignoresSafeArea()
                
                if !viewModel.isConfigured {
                    notConfiguredView
                } else if viewModel.isLoading && viewModel.subscriptions.isEmpty {
                    loadingView
                } else if let error = viewModel.errorMessage, viewModel.subscriptions.isEmpty {
                    errorView(error)
                } else {
                    libraryContent
                }
                
                // Mini player overlay (iPhone only; iPad handled by AdaptiveRootView)
                if playerManager.hasActiveSession && horizontalSizeClass != .regular {
                    VStack {
                        Spacer()
                        MiniPlayerView()
                    }
                }
            }
            .navigationTitle("Podcasts")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.backgroundDark, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showingSearch = true
                        } label: {
                            Label("Search Podcasts", systemImage: "magnifyingglass")
                        }
                        
                        Button {
                            Task { await viewModel.refresh() }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        
                        Divider()
                        
                        Menu("Sort By") {
                            ForEach(PodcastSortOrder.allCases, id: \.self) { order in
                                Button {
                                    viewModel.sortOrder = order
                                } label: {
                                    HStack {
                                        Text(order.displayName)
                                        if viewModel.sortOrder == order {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(Color.anthropicCoral)
                    }
                }
            }
            .sheet(item: $selectedPodcast) { podcast in
                PodcastDetailView(podcast: podcast, libraryViewModel: viewModel)
                    .environmentObject(playerManager)
            }
            .sheet(isPresented: $showingSearch) {
                PodcastSearchView(viewModel: viewModel)
            }
            .sheet(item: $selectedEpisode) { episode in
                if let podcast = viewModel.podcastForEpisode(episode) {
                    EpisodeDetailView(episode: episode, podcast: podcast)
                        .environmentObject(playerManager)
                }
            }
            .task {
                await viewModel.loadIfNeeded()
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Library Content
    
    private var libraryContent: some View {
        VStack(spacing: 0) {
            // View mode picker
            Picker("View", selection: $viewModel.viewMode) {
                ForEach(PodcastViewMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            
            // Search bar (shows mode only)
            if viewModel.viewMode == .shows {
                searchBar
            }
            
            // Content
            switch viewModel.viewMode {
            case .shows:
                showsContent
            case .latest:
                latestEpisodesContent
            }
        }
    }
    
    // MARK: - Shows Grid
    
    private var showsContent: some View {
        ScrollView {
            if viewModel.filteredSubscriptions.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.textTertiary)
                    Text(viewModel.searchQuery.isEmpty ? "No podcasts yet" : "No results")
                        .font(.headline)
                        .foregroundStyle(Color.textSecondary)
                    if viewModel.searchQuery.isEmpty {
                        Text("Search and subscribe to podcasts to get started")
                            .font(.subheadline)
                            .foregroundStyle(Color.textTertiary)
                        
                        Button {
                            showingSearch = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                Text("Search Podcasts")
                            }
                            .fontWeight(.semibold)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.anthropicCoral)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                        }
                    }
                }
                .padding(.top, 80)
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible()), count: horizontalSizeClass == .regular ? 4 : 2),
                    spacing: 16
                ) {
                    ForEach(viewModel.filteredSubscriptions) { podcast in
                        PodcastGridCell(podcast: podcast)
                            .onTapGesture {
                                selectedPodcast = podcast
                            }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, (playerManager.hasActiveSession && horizontalSizeClass != .regular) ? 80 : 16)
            }
        }
        .refreshable {
            await viewModel.refresh()
        }
    }
    
    // MARK: - Latest Episodes
    
    private var latestEpisodesContent: some View {
        ScrollView {
            if viewModel.isLoadingLatest && viewModel.latestEpisodes.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(Color.anthropicCoral)
                    Text("Loading latest episodes...")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                .padding(.top, 60)
            } else if viewModel.latestEpisodes.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "waveform")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.textTertiary)
                    Text("No episodes yet")
                        .font(.headline)
                        .foregroundStyle(Color.textSecondary)
                    Text("Subscribe to podcasts to see their latest episodes here")
                        .font(.subheadline)
                        .foregroundStyle(Color.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 60)
                .padding(.horizontal, 32)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.latestEpisodes) { episode in
                        LatestEpisodeRow(
                            episode: episode,
                            podcast: viewModel.podcastForEpisode(episode)
                        ) {
                            if viewModel.podcastForEpisode(episode) != nil {
                                selectedEpisode = episode
                            }
                        }
                        
                        if episode.id != viewModel.latestEpisodes.last?.id {
                            Divider()
                                .padding(.leading, 76)
                        }
                    }
                }
                .padding(.bottom, (playerManager.hasActiveSession && horizontalSizeClass != .regular) ? 80 : 16)
            }
        }
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            if viewModel.latestEpisodes.isEmpty {
                await viewModel.refreshLatestEpisodes()
            }
        }
    }
    
    // MARK: - Search Bar
    
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.textTertiary)
            
            TextField("Filter podcasts...", text: $viewModel.searchQuery)
                .foregroundStyle(Color.textPrimary)
                .autocorrectionDisabled()
            
            if !viewModel.searchQuery.isEmpty {
                Button {
                    viewModel.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.textTertiary)
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    
    // MARK: - Not Configured
    
    private var notConfiguredView: some View {
        VStack(spacing: 24) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 60))
                .foregroundStyle(Color.textSecondary)
            
            Text("Configure Podcasts")
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
            
            Text("Podcasts use your OpenClaw Gateway connection.\nSet up your endpoint and hook token in Settings.")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Button {
                NotificationCenter.default.post(name: NSNotification.Name("OpenSettings"), object: nil)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "gear")
                    Text("Open Settings")
                }
                .fontWeight(.semibold)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.anthropicCoral)
                .foregroundStyle(.white)
                .clipShape(Capsule())
            }
        }
    }
    
    // MARK: - Loading
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(Color.anthropicCoral)
                .scaleEffect(1.2)
            Text("Loading podcasts...")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
        }
    }
    
    // MARK: - Error
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(Color.statusDisconnected)
            
            Text("Error")
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
            
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Button {
                Task { await viewModel.refresh() }
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
        }
    }
}

// MARK: - Latest Episode Row

struct LatestEpisodeRow: View {
    let episode: PodcastEpisode
    let podcast: Podcast?
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Artwork
                AsyncImage(url: URL(string: episode.artworkUrl ?? podcast?.artworkUrl ?? "")) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.surfaceSecondary)
                        .overlay(
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.caption2)
                                .foregroundStyle(Color.textTertiary)
                        )
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                
                // Content
                VStack(alignment: .leading, spacing: 3) {
                    Text(episode.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(2)
                    
                    if let podcastTitle = podcast?.title {
                        Text(podcastTitle)
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                    }
                    
                    HStack(spacing: 8) {
                        if !episode.formattedDate.isEmpty {
                            Text(episode.formattedDate)
                                .font(.caption2)
                                .foregroundStyle(Color.textTertiary)
                        }
                        
                        if !episode.formattedDuration.isEmpty {
                            Text(episode.formattedDuration)
                                .font(.caption2)
                                .foregroundStyle(Color.textTertiary)
                        }
                    }
                }
                
                Spacer(minLength: 0)
                
                // Play indicator
                Image(systemName: "play.circle")
                    .font(.title3)
                    .foregroundStyle(Color.anthropicCoral)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
