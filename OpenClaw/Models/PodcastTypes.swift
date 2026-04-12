//
//  PodcastTypes.swift
//  OpenClaw
//
//  Models for Podcast player integration with AI highlights
//

import Foundation

// MARK: - Error Types

enum PodcastServiceError: Error, LocalizedError {
    case notConfigured
    case invalidURL
    case invalidResponse
    case httpError(Int, String?)
    case decodingError(Error)
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Podcasts not configured. Set OpenClaw endpoint and hook token in Settings."
        case .invalidURL:
            return "Invalid Podcast URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code, let message):
            if let message, let data = message.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let detail = json["detail"] as? String {
                    return detail
                }
                if let msg = json["message"] as? String {
                    return msg
                }
            }
            return "Server error (HTTP \(code)): \(message ?? "Unknown")"
        case .decodingError(let error):
            return "Failed to parse response: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

// MARK: - iTunes Search API Response

struct iTunesSearchResponse: Codable {
    let resultCount: Int
    let results: [iTunesPodcast]
}

struct iTunesPodcast: Codable, Identifiable, Equatable {
    let collectionId: Int
    let collectionName: String
    let artistName: String
    let artworkUrl600: String?
    let artworkUrl100: String?
    let feedUrl: String?
    let genres: [String]?
    let trackCount: Int?
    
    var id: Int { collectionId }
    var title: String { collectionName }
    var author: String { artistName }
    var artworkUrl: String? { artworkUrl600 ?? artworkUrl100 }
}

// MARK: - Podcast Subscription (from backend)

struct Podcast: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let itunesId: Int?
    let title: String
    let author: String
    let description: String?
    let artworkUrl: String?
    let feedUrl: String
    let episodeCount: Int?
    let lastRefreshedAt: String?
    let subscribedAt: String
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Episode (from backend-parsed RSS)

struct PodcastEpisode: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let podcastId: String
    let title: String
    let description: String?
    let publishedAt: String?
    let durationSeconds: Double?
    let audioUrl: String
    let artworkUrl: String?
    let episodeNumber: Int?
    let seasonNumber: Int?
    let isExplicit: Bool?
    var transcriptionStatus: TranscriptionStatus?
    
    var formattedDuration: String {
        guard let dur = durationSeconds else { return "" }
        return formatTime(dur)
    }
    
    var formattedDate: String {
        guard let dateStr = publishedAt else { return "" }
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: dateStr) {
            let display = DateFormatter()
            display.dateStyle = .medium
            return display.string(from: date)
        }
        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: dateStr) {
            let display = DateFormatter()
            display.dateStyle = .medium
            return display.string(from: date)
        }
        return dateStr
    }
    
    var isTranscribed: Bool {
        transcriptionStatus == .completed
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Transcription Status

enum TranscriptionStatus: String, Codable {
    case none
    case queued
    case processing
    case completed
    case failed
}

// MARK: - Playback Position (from backend)

struct EpisodePlaybackState: Codable, Equatable {
    let episodeId: String
    var positionSeconds: Double
    var playbackSpeed: Double
    var completed: Bool
    let updatedAt: String?
}

// MARK: - Podcast Reference (extracted from transcript)

struct PodcastReference: Codable, Identifiable, Equatable {
    let type: PodcastReferenceType
    let title: String
    let authors: String?
    let url: String?
    let description: String?
    
    var id: String { "\(type.rawValue):\(title)" }
}

enum PodcastReferenceType: String, Codable {
    case paper
    case book
    case tool
    case person
    
    var icon: String {
        switch self {
        case .paper: return "doc.text"
        case .book: return "book"
        case .tool: return "wrench.and.screwdriver"
        case .person: return "person"
        }
    }
    
    var label: String {
        switch self {
        case .paper: return "Paper"
        case .book: return "Book"
        case .tool: return "Tool"
        case .person: return "Person"
        }
    }
}

// MARK: - Podcast Highlight

struct PodcastHighlight: Codable, Identifiable, Equatable {
    let id: String
    let episodeId: String
    let podcastId: String
    let positionSeconds: Double
    let startSeconds: Double
    let episodeTitle: String?
    var highlightText: String?
    var transcriptExcerpt: String?
    let createdAt: Date
    var syncedAt: Date?
    var status: HighlightStatus
    var references: [PodcastReference]?
    
    var formattedTimestamp: String {
        formatTime(positionSeconds)
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }
}

// MARK: - Episode Transcript (from Whisper pipeline)

struct EpisodeTranscriptResponse: Codable {
    let episodeId: String
    let segments: [TranscriptSegment]
    let fullText: String
}

// MARK: - Sort / Filter

enum PodcastSortOrder: String, CaseIterable {
    case title
    case author
    case recentlyUpdated
    
    var displayName: String {
        switch self {
        case .title: return "Title"
        case .author: return "Author"
        case .recentlyUpdated: return "Recently Updated"
        }
    }
}

enum EpisodeSortOrder: String, CaseIterable {
    case newest
    case oldest
    
    var displayName: String {
        switch self {
        case .newest: return "Newest First"
        case .oldest: return "Oldest First"
        }
    }
}

enum PodcastViewMode: String, CaseIterable {
    case shows
    case latest
    
    var displayName: String {
        switch self {
        case .shows: return "Shows"
        case .latest: return "Latest"
        }
    }
}
