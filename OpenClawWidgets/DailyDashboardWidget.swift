//
//  DailyDashboardWidget.swift
//  OpenClawWidgets
//
//  Combined dashboard widget showing tasks and now-playing audiobook.
//

import WidgetKit
import SwiftUI

// MARK: - Timeline Provider

struct DashboardTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> DashboardWidgetEntry {
        DashboardWidgetEntry(
            date: Date(),
            data: WidgetDashboardData(
                todos: [
                    WidgetTodoItem(id: UUID(), title: "Review PR", priority: .high, isCompleted: false, createdAt: Date()),
                    WidgetTodoItem(id: UUID(), title: "Write tests", priority: .medium, isCompleted: false, createdAt: Date()),
                ],
                nowPlaying: WidgetNowPlaying(
                    audiobookId: "sample",
                    title: "The Art of Programming",
                    author: "Jane Smith",
                    coverUrl: nil,
                    progress: 0.45,
                    currentTime: 5400,
                    duration: 12000,
                    isPlaying: true,
                    chapterTitle: "Chapter 5",
                    updatedAt: Date()
                ),
                recentHighlights: [],
                lastUpdated: Date()
            ),
            coverImageData: nil
        )
    }
    
    func getSnapshot(in context: Context, completion: @escaping (DashboardWidgetEntry) -> Void) {
        let data = WidgetDataManager.shared.loadDashboardData()
        let coverData = WidgetDataManager.shared.loadCoverImage()
        completion(DashboardWidgetEntry(date: Date(), data: data, coverImageData: coverData))
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<DashboardWidgetEntry>) -> Void) {
        let data = WidgetDataManager.shared.loadDashboardData()
        let coverData = WidgetDataManager.shared.loadCoverImage()
        let entry = DashboardWidgetEntry(date: Date(), data: data, coverImageData: coverData)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Timeline Entry

struct DashboardWidgetEntry: TimelineEntry {
    let date: Date
    let data: WidgetDashboardData
    let coverImageData: Data?
}

// MARK: - Widget View

struct DashboardWidgetEntryView: View {
    var entry: DashboardWidgetEntry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            headerView
                .padding(.bottom, 8)
            
            if family == .systemMedium {
                mediumLayout
            } else {
                largeLayout
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetBackground()
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack(spacing: 6) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Color(red: 0.85, green: 0.45, blue: 0.40))
            Text("OpenClaw")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color(red: 0.95, green: 0.93, blue: 0.90))
            Spacer()
            Text(entry.date, style: .time)
                .font(.system(size: 9))
                .foregroundStyle(Color(red: 0.50, green: 0.47, blue: 0.44))
        }
    }
    
    // MARK: - Medium Layout (two columns)
    
    private var mediumLayout: some View {
        HStack(alignment: .top, spacing: 12) {
            // Left: Tasks
            Link(destination: URL(string: "openclaw://todo")!) {
                tasksColumn
            }
            
            // Divider
            Rectangle()
                .fill(Color(red: 0.22, green: 0.20, blue: 0.18))
                .frame(width: 1)
            
            // Right: Now Playing
            if let nowPlaying = entry.data.nowPlaying {
                Link(destination: URL(string: "openclaw://audiobook/\(nowPlaying.audiobookId)")!) {
                    nowPlayingColumn(nowPlaying)
                }
            } else {
                nowPlayingEmptyColumn
            }
        }
    }
    
    // MARK: - Large Layout (two columns + highlights below)
    
    private var largeLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                // Left: Tasks
                Link(destination: URL(string: "openclaw://todo")!) {
                    tasksColumn
                }
                
                // Divider
                Rectangle()
                    .fill(Color(red: 0.22, green: 0.20, blue: 0.18))
                    .frame(width: 1)
                
                // Right: Now Playing
                if let nowPlaying = entry.data.nowPlaying {
                    Link(destination: URL(string: "openclaw://audiobook/\(nowPlaying.audiobookId)")!) {
                        nowPlayingColumn(nowPlaying)
                    }
                } else {
                    nowPlayingEmptyColumn
                }
            }
            
            // Highlights section
            if !entry.data.recentHighlights.isEmpty {
                Divider()
                    .background(Color(red: 0.22, green: 0.20, blue: 0.18))
                
                highlightsSection
            }
        }
    }
    
    // MARK: - Tasks Column
    
    private var tasksColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 3) {
                Image(systemName: "checklist")
                    .font(.system(size: 9))
                Text("Tasks")
                    .font(.system(size: 9, weight: .semibold))
                Spacer()
                if !entry.data.todos.isEmpty {
                    Text("\(entry.data.todos.count)")
                        .font(.system(size: 8))
                        .foregroundStyle(Color(red: 0.50, green: 0.47, blue: 0.44))
                }
            }
            .foregroundStyle(Color(red: 0.85, green: 0.45, blue: 0.40))
            
            if entry.data.todos.isEmpty {
                Spacer(minLength: 4)
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color(red: 0.45, green: 0.75, blue: 0.55))
                        Text("All clear!")
                            .font(.system(size: 10))
                            .foregroundStyle(Color(red: 0.70, green: 0.66, blue: 0.62))
                    }
                    Spacer()
                }
                Spacer(minLength: 4)
            } else {
                ForEach(Array(entry.data.todos.prefix(3))) { todo in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(priorityColor(todo.priority))
                            .frame(width: 5, height: 5)
                        Text(todo.title)
                            .font(.system(size: 10))
                            .foregroundStyle(Color(red: 0.95, green: 0.93, blue: 0.90))
                            .lineLimit(1)
                    }
                }
            }
            
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Now Playing Column
    
    private var dashboardCoverImage: UIImage? {
        guard let data = entry.coverImageData else { return nil }
        return UIImage(data: data)
    }
    
    private func nowPlayingColumn(_ nowPlaying: WidgetNowPlaying) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 3) {
                Image(systemName: nowPlaying.isPlaying ? "play.fill" : "book.fill")
                    .font(.system(size: 8))
                Text(nowPlaying.isPlaying ? "Playing" : "Last Listened")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(Color(red: 0.85, green: 0.45, blue: 0.40))
            
            HStack(alignment: .top, spacing: 6) {
                // Cover art
                if let dashboardCoverImage {
                    Image(uiImage: dashboardCoverImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                } else {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(red: 0.18, green: 0.16, blue: 0.14))
                        .frame(width: 36, height: 36)
                        .overlay(
                            Image(systemName: "headphones")
                                .font(.system(size: 14))
                                .foregroundStyle(Color(red: 0.40, green: 0.37, blue: 0.34))
                        )
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(nowPlaying.title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(red: 0.95, green: 0.93, blue: 0.90))
                        .lineLimit(2)
                    
                    Text(nowPlaying.author)
                        .font(.system(size: 9))
                        .foregroundStyle(Color(red: 0.70, green: 0.66, blue: 0.62))
                        .lineLimit(1)
                }
            }
            
            Spacer(minLength: 2)
            
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color(red: 0.22, green: 0.20, blue: 0.18))
                        .frame(height: 3)
                    
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color(red: 0.85, green: 0.45, blue: 0.40))
                        .frame(width: geo.size.width * nowPlaying.progress, height: 3)
                }
            }
            .frame(height: 3)
            
            HStack {
                Text("\(nowPlaying.progressPercentage)%")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Color(red: 0.85, green: 0.45, blue: 0.40))
                Spacer()
                Text(nowPlaying.formattedRemaining)
                    .font(.system(size: 8))
                    .foregroundStyle(Color(red: 0.50, green: 0.47, blue: 0.44))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var nowPlayingEmptyColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 3) {
                Image(systemName: "headphones")
                    .font(.system(size: 8))
                Text("Playing")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(Color(red: 0.50, green: 0.47, blue: 0.44))
            
            Spacer(minLength: 4)
            HStack {
                Spacer()
                VStack(spacing: 4) {
                    Image(systemName: "headphones")
                        .font(.system(size: 16))
                        .foregroundStyle(Color(red: 0.50, green: 0.47, blue: 0.44))
                    Text("Nothing playing")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(red: 0.70, green: 0.66, blue: 0.62))
                }
                Spacer()
            }
            Spacer(minLength: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Highlights Section (large only)
    
    private var highlightsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 3) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9))
                Text("Recent Highlights")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(Color(red: 0.90, green: 0.55, blue: 0.35))
            
            ForEach(Array(entry.data.recentHighlights.prefix(2))) { highlight in
                VStack(alignment: .leading, spacing: 1) {
                    Text(highlight.highlightText)
                        .font(.system(size: 9))
                        .foregroundStyle(Color(red: 0.95, green: 0.93, blue: 0.90))
                        .lineLimit(2)
                        .italic()
                    Text(highlight.audiobookTitle)
                        .font(.system(size: 8))
                        .foregroundStyle(Color(red: 0.50, green: 0.47, blue: 0.44))
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func priorityColor(_ priority: WidgetTodoPriority) -> Color {
        switch priority {
        case .high: return Color(red: 0.85, green: 0.40, blue: 0.40)
        case .medium: return Color(red: 0.90, green: 0.55, blue: 0.35)
        case .low: return Color(red: 0.45, green: 0.75, blue: 0.55)
        }
    }
}

// MARK: - Widget Configuration

struct DailyDashboardWidget: Widget {
    let kind: String = "DailyDashboardWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DashboardTimelineProvider()) { entry in
            DashboardWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Daily Dashboard")
        .description("Tasks and audiobook progress at a glance.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

#Preview(as: .systemMedium) {
    DailyDashboardWidget()
} timeline: {
    DashboardWidgetEntry(date: .now, data: WidgetDashboardData(
        todos: [
            WidgetTodoItem(id: UUID(), title: "Review PR #42", priority: .high, isCompleted: false, createdAt: Date()),
            WidgetTodoItem(id: UUID(), title: "Update docs", priority: .medium, isCompleted: false, createdAt: Date()),
            WidgetTodoItem(id: UUID(), title: "Write tests", priority: .low, isCompleted: false, createdAt: Date()),
        ],
        nowPlaying: WidgetNowPlaying(
            audiobookId: "123",
            title: "Atomic Habits",
            author: "James Clear",
            coverUrl: nil,
            progress: 0.62,
            currentTime: 7440,
            duration: 12000,
            isPlaying: true,
            chapterTitle: "Chapter 8",
            updatedAt: Date()
        ),
        recentHighlights: [
            WidgetHighlight(id: "h1", audiobookTitle: "Atomic Habits", highlightText: "You do not rise to the level of your goals. You fall to the level of your systems.", createdAt: Date()),
        ],
        lastUpdated: Date()
    ), coverImageData: nil)
}
