//
//  AudiobookTypes.swift
//  OpenClaw
//
//  Models for LibroAI audiobook integration
//

import Foundation

// MARK: - Audio Format

enum AudioFormat: String, Codable {
    case m4b
    case mp3
}

// MARK: - Audiobook

struct Audiobook: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let author: String
    let narrator: String?
    let durationSeconds: Double
    var coverUrl: String?
    let localPath: String?
    let format: AudioFormat
    let downloaded: Bool
    let transcribed: Bool
    let indexed: Bool
    let summarized: Bool
    let diarized: Bool
    
    var formattedDuration: String {
        let hours = Int(durationSeconds) / 3600
        let minutes = (Int(durationSeconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
    
    /// Builds a full cover image URL from the base endpoint and the relative cover path
    func coverImageURL(baseURL: String) -> URL? {
        guard let coverUrl = coverUrl, !coverUrl.isEmpty else { return nil }
        // Absolute URL — use as-is
        if coverUrl.hasPrefix("http") {
            return URL(string: coverUrl)
        }
        // Relative path — extract scheme+host+port from base
        if let components = URLComponents(string: baseURL),
           let scheme = components.scheme,
           let host = components.host {
            let port = components.port.map { ":\($0)" } ?? ""
            let base = "\(scheme)://\(host)\(port)"
            return URL(string: "\(base)\(coverUrl)")
        }
        let base = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: "\(base)\(coverUrl)")
    }
}

// MARK: - Chapter

struct AudiobookChapter: Codable, Identifiable, Equatable {
    let id: Int
    let audiobookId: String
    let title: String
    let startSeconds: Double
    let endSeconds: Double
    let chapterIndex: Int
    let summary: String?
    
    var formattedStart: String {
        formatTime(startSeconds)
    }
    
    var duration: Double {
        endSeconds - startSeconds
    }
    
    var formattedDuration: String {
        let dur = duration
        let minutes = Int(dur) / 60
        let seconds = Int(dur) % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}

// MARK: - Playback State

struct PlaybackState: Codable, Equatable {
    let audiobookId: String
    var positionSeconds: Double
    var playbackSpeed: Double
    let updatedAt: String?
}

// MARK: - Library Sync Response

struct LibrarySyncResponse: Codable {
    let status: String
    let message: String?
    let booksAdded: Int?
}

// MARK: - Sort Order

enum AudiobookSortOrder: String, CaseIterable {
    case title
    case author
    case duration
    
    var displayName: String {
        switch self {
        case .title: return "Title"
        case .author: return "Author"
        case .duration: return "Duration"
        }
    }
}

// MARK: - Libro.fm Types

struct LibroFmAuthRequest: Codable {
    let email: String
    let password: String
}

struct LibroFmAuthResponse: Codable {
    let status: String
    let message: String?
    let email: String?
}

struct LibroFmStatus: Codable {
    let connected: Bool
    let email: String?
}

struct LibroFmBook: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let author: String
    let coverUrl: String?
    let inLibrary: Bool

    func coverImageURL() -> URL? {
        guard let coverUrl, !coverUrl.isEmpty else { return nil }
        return URL(string: coverUrl)
    }
}

struct DownloadJob: Codable, Identifiable, Equatable {
    let id: String
    let bookId: String
    let title: String
    let status: DownloadJobStatus
    let progress: Double?
    let errorMessage: String?
}

enum DownloadJobStatus: String, Codable {
    case queued
    case downloading
    case completed
    case failed
}

struct DownloadStartResponse: Codable {
    let status: String
    let jobId: String
    let message: String?
}

// MARK: - Local Download State

enum LocalDownloadState: Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case downloaded(localURL: URL)
    case failed(error: String)
    
    var isDownloaded: Bool {
        if case .downloaded = self { return true }
        return false
    }
    
    var isDownloading: Bool {
        if case .downloading = self { return true }
        return false
    }
}

// MARK: - AI Highlights

struct AudiobookHighlight: Codable, Identifiable, Equatable {
    let id: String
    let audiobookId: String
    let positionSeconds: Double
    let startSeconds: Double
    let chapterTitle: String?
    var highlightText: String?
    var transcriptExcerpt: String?
    let createdAt: Date
    var syncedAt: Date?
    var status: HighlightStatus
    
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

enum HighlightStatus: String, Codable, Equatable {
    case pending
    case processing
    case completed
    case failed
}

struct TranscriptResponse: Codable {
    let audiobookId: String
    let segments: [TranscriptSegment]
    let fullText: String
}

struct TranscriptSegment: Codable {
    let text: String
    let startSeconds: Double
    let endSeconds: Double
    let speaker: String?
}

// MARK: - Time Formatting Helper

func formatTime(_ seconds: Double) -> String {
    let totalSeconds = Int(max(0, seconds))
    let hours = totalSeconds / 3600
    let mins = (totalSeconds % 3600) / 60
    let secs = totalSeconds % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, mins, secs)
    }
    return String(format: "%d:%02d", mins, secs)
}
