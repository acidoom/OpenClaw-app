//
//  PodcastsViewModel.swift
//  OpenClaw
//
//  Main view model for podcast subscriptions and search
//

import Foundation
import Combine

@MainActor
final class PodcastsViewModel: ObservableObject {
    @Published var subscriptions: [Podcast] = []
    @Published var searchQuery = ""
    @Published var searchResults: [iTunesPodcast] = []
    @Published var isSearching = false
    @Published var isLoading = false
    @Published var isConfigured = false
    @Published var errorMessage: String?
    @Published var sortOrder: PodcastSortOrder = .recentlyUpdated
    @Published var subscribedIds: Set<Int> = [] // iTunes IDs we're subscribed to
    @Published var subscribingIds: Set<Int> = [] // iTunes IDs currently being subscribed
    @Published var latestEpisodes: [PodcastEpisode] = []
    @Published var isLoadingLatest = false
    @Published var viewMode: PodcastViewMode = .shows
    
    private let service = PodcastService.shared
    private var searchTask: Task<Void, Never>?
    
    var filteredSubscriptions: [Podcast] {
        var result = subscriptions
        
        if !searchQuery.isEmpty {
            let query = searchQuery.lowercased()
            result = result.filter {
                $0.title.lowercased().contains(query) ||
                $0.author.lowercased().contains(query)
            }
        }
        
        switch sortOrder {
        case .title:
            result.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .author:
            result.sort { $0.author.localizedCaseInsensitiveCompare($1.author) == .orderedAscending }
        case .recentlyUpdated:
            result.sort { ($0.lastRefreshedAt ?? "") > ($1.lastRefreshedAt ?? "") }
        }
        
        return result
    }
    
    func loadIfNeeded() async {
        isConfigured = service.isConfigured
        guard isConfigured, subscriptions.isEmpty else { return }
        await refresh()
    }
    
    func refresh() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // First refresh all RSS feeds to pick up new episodes
            print("[PodcastsVM] Refreshing all feeds...")
            subscriptions = try await service.refreshAllFeeds()
            updateSubscribedIds()
            print("[PodcastsVM] All feeds refreshed, \(subscriptions.count) podcasts")
        } catch {
            // If refresh-all fails (e.g. not implemented yet), fall back to just fetching
            print("[PodcastsVM] refreshAllFeeds failed: \(error), falling back to fetchSubscriptions")
            do {
                subscriptions = try await service.fetchSubscriptions(forceRefresh: true)
                updateSubscribedIds()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        
        isLoading = false
        
        // Also refresh latest episodes if we have subscriptions
        if !subscriptions.isEmpty {
            await refreshLatestEpisodes()
        }
    }
    
    func refreshLatestEpisodes() async {
        isLoadingLatest = true
        do {
            latestEpisodes = try await service.fetchLatestEpisodes(limit: 50)
        } catch {
            print("[PodcastsVM] Failed to load latest episodes: \(error)")
        }
        isLoadingLatest = false
    }
    
    func podcastForEpisode(_ episode: PodcastEpisode) -> Podcast? {
        subscriptions.first { $0.id == episode.podcastId }
    }
    
    // MARK: - iTunes Search
    
    func search(query: String) {
        searchTask?.cancel()
        
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            isSearching = false
            return
        }
        
        isSearching = true
        
        searchTask = Task {
            // Debounce
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            
            do {
                let results = try await service.searchPodcasts(query: query)
                guard !Task.isCancelled else { return }
                searchResults = results
            } catch {
                guard !Task.isCancelled else { return }
                print("[PodcastsVM] Search error: \(error)")
            }
            
            isSearching = false
        }
    }
    
    // MARK: - Subscribe / Unsubscribe
    
    func subscribe(podcast: iTunesPodcast) async {
        guard let feedUrl = podcast.feedUrl else {
            errorMessage = "This podcast doesn't have a feed URL"
            print("[PodcastsVM] Subscribe failed: no feedUrl for '\(podcast.title)'")
            return
        }
        
        subscribingIds.insert(podcast.collectionId)
        errorMessage = nil
        
        do {
            print("[PodcastsVM] Subscribing to '\(podcast.title)' feedUrl=\(feedUrl)")
            let subscribed = try await service.subscribe(
                feedUrl: feedUrl,
                itunesId: podcast.collectionId,
                title: podcast.title,
                author: podcast.author,
                artworkUrl: podcast.artworkUrl
            )
            subscriptions.append(subscribed)
            subscribedIds.insert(podcast.collectionId)
            print("[PodcastsVM] Successfully subscribed to '\(subscribed.title)' id=\(subscribed.id)")
        } catch {
            errorMessage = error.localizedDescription
            print("[PodcastsVM] Subscribe error: \(error)")
        }
        
        subscribingIds.remove(podcast.collectionId)
    }
    
    func unsubscribe(podcastId: String) async {
        do {
            if let podcast = subscriptions.first(where: { $0.id == podcastId }),
               let itunesId = podcast.itunesId {
                subscribedIds.remove(itunesId)
            }
            try await service.unsubscribe(podcastId: podcastId)
            subscriptions.removeAll { $0.id == podcastId }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func isSubscribed(itunesId: Int) -> Bool {
        subscribedIds.contains(itunesId)
    }
    
    private func updateSubscribedIds() {
        subscribedIds = Set(subscriptions.compactMap { $0.itunesId })
    }
}
