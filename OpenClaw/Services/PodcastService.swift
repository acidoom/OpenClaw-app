//
//  PodcastService.swift
//  OpenClaw
//
//  API client for podcast subscription management and playback
//

import Foundation

actor PodcastService {
    static let shared = PodcastService()
    
    private let keychain = KeychainManager.shared
    private let session: URLSession
    
    // Cache
    private var cachedSubscriptions: [Podcast] = []
    private var cachedEpisodes: [String: [PodcastEpisode]] = [:]
    private var lastSubscriptionsFetch: Date?
    private let cacheValidity: TimeInterval = 300 // 5 minutes
    
    private lazy var decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            
            if let timestamp = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: timestamp)
            }
            
            let dateString = try container.decode(String.self)
            
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = isoFormatter.date(from: dateString) {
                return date
            }
            
            isoFormatter.formatOptions = [.withInternetDateTime]
            if let date = isoFormatter.date(from: dateString) {
                return date
            }
            
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = isoFormatter.date(from: dateString + "Z") {
                return date
            }
            isoFormatter.formatOptions = [.withInternetDateTime]
            if let date = isoFormatter.date(from: dateString + "Z") {
                return date
            }
            
            let sqlFormatter = DateFormatter()
            sqlFormatter.locale = Locale(identifier: "en_US_POSIX")
            sqlFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            sqlFormatter.timeZone = TimeZone(identifier: "UTC")
            if let date = sqlFormatter.date(from: dateString) {
                return date
            }
            
            sqlFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSS"
            if let date = sqlFormatter.date(from: dateString) {
                return date
            }
            
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Cannot decode date from: \(dateString)")
            )
        }
        return d
    }()
    
    private lazy var encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()
    
    private init() {
        let delegate = TailscaleTrustDelegate()
        session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
    }
    
    nonisolated var isConfigured: Bool {
        keychain.hasLibroAICredentials()
    }
    
    // MARK: - Base Request Builder
    
    private func makeRequest(
        method: String = "GET",
        path: String,
        body: Data? = nil,
        queryItems: [URLQueryItem] = []
    ) async throws -> (Data, HTTPURLResponse) {
        guard let endpoint = try? keychain.get(.openClawEndpoint), !endpoint.isEmpty,
              let token = try? keychain.get(.gatewayHookToken), !token.isEmpty else {
            throw PodcastServiceError.notConfigured
        }
        
        let base: String
        if let components = URLComponents(string: endpoint),
           let scheme = components.scheme,
           let host = components.host {
            let port = components.port.map { ":\($0)" } ?? ""
            base = "\(scheme)://\(host)\(port)"
        } else {
            base = endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        var urlString = "\(base)\(path)"
        
        if !queryItems.isEmpty {
            var components = URLComponents(string: urlString)
            components?.queryItems = queryItems
            urlString = components?.string ?? urlString
        }
        
        guard let url = URL(string: urlString) else {
            throw PodcastServiceError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 120
        
        if let body = body {
            request.httpBody = body
        }
        
        print("[Podcast] \(method) \(urlString)")
        
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError where urlError.code == .networkConnectionLost {
            print("[Podcast] Connection lost, retrying...")
            try await Task.sleep(nanoseconds: 500_000_000)
            (data, response) = try await session.data(for: request)
        } catch {
            throw PodcastServiceError.networkError(error)
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PodcastServiceError.invalidResponse
        }
        
        print("[Podcast] HTTP \(httpResponse.statusCode)")
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8)
            print("[Podcast] Error body: \(errorBody ?? "nil")")
            throw PodcastServiceError.httpError(httpResponse.statusCode, errorBody)
        }
        
        return (data, httpResponse)
    }
    
    // MARK: - iTunes Search (no auth needed)
    
    func searchPodcasts(query: String) async throws -> [iTunesPodcast] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "https://itunes.apple.com/search?term=\(encoded)&media=podcast&limit=30") else {
            throw PodcastServiceError.invalidURL
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(iTunesSearchResponse.self, from: data)
        return response.results
    }
    
    // MARK: - Subscriptions
    
    func fetchSubscriptions(forceRefresh: Bool = false) async throws -> [Podcast] {
        if !forceRefresh,
           let lastFetch = lastSubscriptionsFetch,
           Date().timeIntervalSince(lastFetch) < cacheValidity,
           !cachedSubscriptions.isEmpty {
            return cachedSubscriptions
        }
        
        let (data, _) = try await makeRequest(path: "/api/podcasts")
        let podcasts = try decoder.decode([Podcast].self, from: data)
        cachedSubscriptions = podcasts
        lastSubscriptionsFetch = Date()
        print("[Podcast] Fetched \(podcasts.count) subscriptions")
        return podcasts
    }
    
    func subscribe(feedUrl: String, itunesId: Int?, title: String, author: String, artworkUrl: String?) async throws -> Podcast {
        struct SubscribeRequest: Encodable {
            let feedUrl: String
            let itunesId: Int?
            let title: String
            let author: String
            let artworkUrl: String?
        }
        
        let request = SubscribeRequest(feedUrl: feedUrl, itunesId: itunesId, title: title, author: author, artworkUrl: artworkUrl)
        let bodyData = try encoder.encode(request)
        let (data, _) = try await makeRequest(method: "POST", path: "/api/podcasts/subscribe", body: bodyData)
        let podcast = try decoder.decode(Podcast.self, from: data)
        lastSubscriptionsFetch = nil // Invalidate cache
        print("[Podcast] Subscribed to '\(podcast.title)'")
        return podcast
    }
    
    func unsubscribe(podcastId: String) async throws {
        _ = try await makeRequest(method: "DELETE", path: "/api/podcasts/\(podcastId)")
        cachedSubscriptions.removeAll { $0.id == podcastId }
        cachedEpisodes.removeValue(forKey: podcastId)
        lastSubscriptionsFetch = nil
        print("[Podcast] Unsubscribed from \(podcastId)")
    }
    
    // MARK: - Episodes
    
    func fetchEpisodes(podcastId: String, page: Int = 1, limit: Int = 50) async throws -> [PodcastEpisode] {
        let queryItems = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        let (data, _) = try await makeRequest(path: "/api/podcasts/\(podcastId)/episodes", queryItems: queryItems)
        let episodes = try decoder.decode([PodcastEpisode].self, from: data)
        cachedEpisodes[podcastId] = episodes
        print("[Podcast] Fetched \(episodes.count) episodes for \(podcastId)")
        return episodes
    }
    
    func fetchEpisode(podcastId: String, episodeId: String) async throws -> PodcastEpisode? {
        let episodes = try await fetchEpisodes(podcastId: podcastId)
        return episodes.first { $0.id == episodeId }
    }
    
    func fetchLatestEpisodes(limit: Int = 50) async throws -> [PodcastEpisode] {
        let queryItems = [
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        let (data, _) = try await makeRequest(path: "/api/podcasts/episodes/latest", queryItems: queryItems)
        let episodes = try decoder.decode([PodcastEpisode].self, from: data)
        print("[Podcast] Fetched \(episodes.count) latest episodes")
        return episodes
    }
    
    func refreshFeed(podcastId: String) async throws -> Podcast {
        let (data, _) = try await makeRequest(method: "POST", path: "/api/podcasts/\(podcastId)/refresh")
        let podcast = try decoder.decode(Podcast.self, from: data)
        lastSubscriptionsFetch = nil
        cachedEpisodes.removeValue(forKey: podcastId)
        print("[Podcast] Refreshed feed for '\(podcast.title)'")
        return podcast
    }
    
    func refreshAllFeeds() async throws -> [Podcast] {
        let (data, _) = try await makeRequest(method: "POST", path: "/api/podcasts/refresh-all")
        let podcasts = try decoder.decode([Podcast].self, from: data)
        cachedSubscriptions = podcasts
        lastSubscriptionsFetch = Date()
        cachedEpisodes = [:]
        print("[Podcast] Refreshed all feeds, \(podcasts.count) podcasts updated")
        return podcasts
    }
    
    // MARK: - Playback State
    
    func fetchPlaybackState(episodeId: String) async throws -> EpisodePlaybackState {
        let (data, _) = try await makeRequest(path: "/api/podcasts/episodes/\(episodeId)/playback")
        return try decoder.decode(EpisodePlaybackState.self, from: data)
    }
    
    func updatePlaybackState(episodeId: String, position: Double, speed: Double, completed: Bool = false) async throws {
        struct PlaybackUpdate: Encodable {
            let positionSeconds: Double
            let playbackSpeed: Double
            let completed: Bool
        }
        let update = PlaybackUpdate(positionSeconds: position, playbackSpeed: speed, completed: completed)
        let bodyData = try encoder.encode(update)
        _ = try await makeRequest(method: "PUT", path: "/api/podcasts/episodes/\(episodeId)/playback", body: bodyData)
    }
    
    // MARK: - Transcription
    
    func requestTranscription(episodeId: String, podcastId: String? = nil) async throws {
        _ = try await makeRequest(method: "POST", path: "/api/podcasts/episodes/\(episodeId)/transcribe")
        // Invalidate episode cache so next fetch picks up the new status
        if let podcastId = podcastId {
            cachedEpisodes.removeValue(forKey: podcastId)
        }
        print("[Podcast] Requested transcription for episode \(episodeId)")
    }
    
    func fetchTranscript(episodeId: String, startSeconds: Double, endSeconds: Double) async throws -> EpisodeTranscriptResponse {
        let queryItems = [
            URLQueryItem(name: "start_seconds", value: "\(startSeconds)"),
            URLQueryItem(name: "end_seconds", value: "\(endSeconds)")
        ]
        let (data, _) = try await makeRequest(path: "/api/podcasts/episodes/\(episodeId)/transcript", queryItems: queryItems)
        return try decoder.decode(EpisodeTranscriptResponse.self, from: data)
    }
    
    // MARK: - Highlights
    
    func fetchHighlights(episodeId: String) async throws -> [PodcastHighlight] {
        let (data, _) = try await makeRequest(path: "/api/podcasts/episodes/\(episodeId)/highlights")
        return try decoder.decode([PodcastHighlight].self, from: data)
    }
    
    func saveHighlight(_ highlight: PodcastHighlight) async throws {
        let bodyData = try encoder.encode(highlight)
        _ = try await makeRequest(method: "POST", path: "/api/podcasts/highlights", body: bodyData)
    }
    
    func deleteHighlight(id: String) async throws {
        _ = try await makeRequest(method: "DELETE", path: "/api/podcasts/highlights/\(id)")
    }
    
    // MARK: - Cache
    
    func clearCache() {
        cachedSubscriptions = []
        cachedEpisodes = [:]
        lastSubscriptionsFetch = nil
    }
}
