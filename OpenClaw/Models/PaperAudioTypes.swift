//
//  PaperAudioTypes.swift
//  OpenClaw
//
//  Models for the Paper-to-Audiobook pipeline (Zotero → Claude → ElevenLabs → Audio)
//

import Foundation

// MARK: - Listening Mode

enum PaperListeningMode: String, Codable, CaseIterable {
    case summary = "summary"       // 2–5 min quick summary
    case runner = "runner"         // 8–15 min clean walkthrough
    case deepDive = "deep_dive"    // Full section-by-section narration
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        switch value {
        case "summary": self = .summary
        case "runner": self = .runner
        case "deep_dive", "deepDive": self = .deepDive
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unknown PaperListeningMode: \(value)")
            )
        }
    }
    
    var displayName: String {
        switch self {
        case .summary: return "Summary"
        case .runner: return "Runner Mode"
        case .deepDive: return "Deep Dive"
        }
    }
    
    var description: String {
        switch self {
        case .summary:
            return "2–5 min spoken summary. Key problem, idea, results, and takeaway."
        case .runner:
            return "8–15 min clean walkthrough. Simplified wording, no citation noise."
        case .deepDive:
            return "Full section-by-section narration. More detail, still cleaned for audio."
        }
    }
    
    var iconName: String {
        switch self {
        case .summary: return "bolt.fill"
        case .runner: return "figure.run"
        case .deepDive: return "book.fill"
        }
    }
    
    var estimatedDuration: String {
        switch self {
        case .summary: return "2–5 min"
        case .runner: return "8–15 min"
        case .deepDive: return "20–45 min"
        }
    }
}

// MARK: - Generation Job Status

enum PaperAudioStatus: String, Codable {
    case queued = "queued"
    case extractingText = "extracting_text"
    case cleaningText = "cleaning_text"
    case generatingScript = "generating_script"
    case synthesizingAudio = "synthesizing_audio"
    case assemblingManifest = "assembling_manifest"
    case completed = "completed"
    case failed = "failed"
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        switch value {
        case "queued": self = .queued
        case "extracting_text", "extractingText": self = .extractingText
        case "cleaning_text", "cleaningText": self = .cleaningText
        case "generating_script", "generatingScript": self = .generatingScript
        case "synthesizing_audio", "synthesizingAudio": self = .synthesizingAudio
        case "assembling_manifest", "assemblingManifest": self = .assemblingManifest
        case "completed": self = .completed
        case "failed": self = .failed
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unknown PaperAudioStatus: \(value)")
            )
        }
    }
    
    var displayName: String {
        switch self {
        case .queued: return "Queued"
        case .extractingText: return "Extracting text"
        case .cleaningText: return "Cleaning text"
        case .generatingScript: return "Generating script"
        case .synthesizingAudio: return "Synthesizing audio"
        case .assemblingManifest: return "Assembling"
        case .completed: return "Ready"
        case .failed: return "Failed"
        }
    }
    
    var isActive: Bool {
        switch self {
        case .queued, .extractingText, .cleaningText,
             .generatingScript, .synthesizingAudio, .assemblingManifest:
            return true
        case .completed, .failed:
            return false
        }
    }
}

// MARK: - Generation Configuration

struct PaperAudioConfig: Codable {
    let zoteroItemKey: String
    let paperTitle: String
    let mode: PaperListeningMode
    let skipEquations: Bool
    let skipTables: Bool
    let skipReferences: Bool
    let summarizeFigures: Bool
    let explainJargon: Bool
    let voiceId: String
    
    /// Default configuration for Runner Mode
    static func runnerDefaults(zoteroItemKey: String, paperTitle: String) -> PaperAudioConfig {
        PaperAudioConfig(
            zoteroItemKey: zoteroItemKey,
            paperTitle: paperTitle,
            mode: .runner,
            skipEquations: true,
            skipTables: true,
            skipReferences: true,
            summarizeFigures: true,
            explainJargon: true,
            voiceId: "default"
        )
    }
}

// MARK: - Generation Job

struct PaperAudioJob: Codable, Identifiable, Equatable {
    let id: String
    let zoteroItemKey: String
    let paperTitle: String
    let mode: PaperListeningMode
    let status: PaperAudioStatus
    let progress: Double?
    let totalDurationSec: Double?
    let errorMessage: String?
    let createdAt: Date
    let completedAt: Date?
    
    var formattedDuration: String? {
        guard let duration = totalDurationSec, duration > 0 else { return nil }
        return formatTime(duration)
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }
    
    var progressPercent: Int {
        Int((progress ?? 0) * 100)
    }
}

// MARK: - Audio Manifest

struct PaperAudioManifest: Codable {
    let jobId: String
    let paperTitle: String
    let mode: PaperListeningMode
    let totalDurationSec: Double
    let sections: [PaperAudioSection]
    
    var formattedDuration: String {
        formatTime(totalDurationSec)
    }
}

struct PaperAudioSection: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let startSec: Double
    let durationSec: Double
    let chunks: [PaperAudioChunk]
    
    var endSec: Double {
        startSec + durationSec
    }
    
    var formattedDuration: String {
        formatTime(durationSec)
    }
}

struct PaperAudioChunk: Codable, Identifiable, Equatable {
    let id: Int
    let index: Int
    let text: String
    let audioUrl: String
    let durationSec: Double
}

// MARK: - API Response Types

struct PaperAudioGenerateResponse: Codable {
    let jobId: String
    let status: String
    let message: String?
}

// MARK: - Error Types

enum PaperAudioServiceError: Error, LocalizedError {
    case notConfigured
    case invalidURL
    case invalidResponse
    case httpError(Int, String?)
    case decodingError(Error)
    case networkError(Error)
    case jobNotFound
    case generationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Paper Audio not configured. Set OpenClaw endpoint and hook token in Settings."
        case .invalidURL:
            return "Invalid Paper Audio URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code, let message):
            if let message, let data = message.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let detail = json["detail"] as? String { return detail }
                if let msg = json["message"] as? String { return msg }
            }
            return "Server error (HTTP \(code)): \(message ?? "Unknown")"
        case .decodingError(let error):
            return "Failed to parse response: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .jobNotFound:
            return "Paper audio job not found"
        case .generationFailed(let reason):
            return "Generation failed: \(reason)"
        }
    }
}
