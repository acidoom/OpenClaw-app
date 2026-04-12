//
//  WidgetModels.swift
//  OpenClawWidgets
//
//  Lightweight Codable models shared between the main app and widget extension.
//  IMPORTANT: Keep in sync with OpenClaw/Services/WidgetModels.swift
//

import Foundation

// MARK: - Constants

enum WidgetDataKey {
    static let suiteName = "group.carc.ai.OpenClaw"
    static let todos = "widget_todos"
    static let nowPlaying = "widget_now_playing"
    static let recentHighlights = "widget_recent_highlights"
    static let lastUpdated = "widget_last_updated"
    static let coverImagePath = "widget_cover_image_path"
}

// MARK: - Widget Todo Models

enum WidgetTodoPriority: String, Codable {
    case high
    case medium
    case low
}

struct WidgetTodoItem: Codable, Identifiable {
    let id: UUID
    let title: String
    let priority: WidgetTodoPriority
    let isCompleted: Bool
    let createdAt: Date
}

// MARK: - Widget Now Playing

struct WidgetNowPlaying: Codable {
    let audiobookId: String
    let title: String
    let author: String
    let coverUrl: String?
    let progress: Double
    let currentTime: Double
    let duration: Double
    let isPlaying: Bool
    let chapterTitle: String?
    let updatedAt: Date
    
    var formattedRemaining: String {
        let remaining = max(0, duration - currentTime)
        return formatWidgetTime(remaining)
    }
    
    var progressPercentage: Int {
        guard duration > 0 else { return 0 }
        return Int((currentTime / duration) * 100)
    }
}

// MARK: - Widget Highlight

struct WidgetHighlight: Codable, Identifiable {
    let id: String
    let audiobookTitle: String
    let highlightText: String
    let createdAt: Date
}

// MARK: - Aggregate Dashboard Data

struct WidgetDashboardData {
    let todos: [WidgetTodoItem]
    let nowPlaying: WidgetNowPlaying?
    let recentHighlights: [WidgetHighlight]
    let lastUpdated: Date?
}

// MARK: - Time Formatting

func formatWidgetTime(_ seconds: Double) -> String {
    let totalSeconds = Int(max(0, seconds))
    let hours = totalSeconds / 3600
    let mins = (totalSeconds % 3600) / 60
    if hours > 0 {
        return "\(hours)h \(mins)m"
    }
    return "\(mins)m"
}
