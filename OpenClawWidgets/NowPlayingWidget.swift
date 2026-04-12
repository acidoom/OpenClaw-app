//
//  NowPlayingWidget.swift
//  OpenClawWidgets
//
//  Now-playing widget showing current audiobook with progress.
//

import WidgetKit
import SwiftUI

// MARK: - Timeline Provider

struct NowPlayingTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> NowPlayingWidgetEntry {
        NowPlayingWidgetEntry(
            date: Date(),
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
            coverImageData: nil
        )
    }
    
    func getSnapshot(in context: Context, completion: @escaping (NowPlayingWidgetEntry) -> Void) {
        let nowPlaying = WidgetDataManager.shared.loadNowPlaying()
        let coverData = WidgetDataManager.shared.loadCoverImage()
        completion(NowPlayingWidgetEntry(date: Date(), nowPlaying: nowPlaying, coverImageData: coverData))
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingWidgetEntry>) -> Void) {
        let nowPlaying = WidgetDataManager.shared.loadNowPlaying()
        let coverData = WidgetDataManager.shared.loadCoverImage()
        let entry = NowPlayingWidgetEntry(date: Date(), nowPlaying: nowPlaying, coverImageData: coverData)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Timeline Entry

struct NowPlayingWidgetEntry: TimelineEntry {
    let date: Date
    let nowPlaying: WidgetNowPlaying?
    let coverImageData: Data?
}

// MARK: - Widget View

struct NowPlayingWidgetEntryView: View {
    var entry: NowPlayingWidgetEntry
    
    var body: some View {
        if let nowPlaying = entry.nowPlaying {
            nowPlayingContent(nowPlaying)
        } else {
            emptyState
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "headphones")
                .font(.system(size: 28))
                .foregroundStyle(Color(red: 0.50, green: 0.47, blue: 0.44))
            Text("Nothing playing")
                .font(.caption)
                .foregroundStyle(Color(red: 0.70, green: 0.66, blue: 0.62))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetBackground()
    }
    
    private var coverImage: UIImage? {
        guard let data = entry.coverImageData else { return nil }
        return UIImage(data: data)
    }
    
    private func nowPlayingContent(_ nowPlaying: WidgetNowPlaying) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 4) {
                Image(systemName: nowPlaying.isPlaying ? "play.fill" : "book.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(Color(red: 0.85, green: 0.45, blue: 0.40))
                Text(nowPlaying.isPlaying ? "Now Playing" : "Last Listened")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color(red: 0.85, green: 0.45, blue: 0.40))
                Spacer()
            }
            .padding(.bottom, 6)
            
            // Cover + text
            HStack(alignment: .top, spacing: 8) {
                // Cover art
                if let coverImage {
                    Image(uiImage: coverImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(red: 0.18, green: 0.16, blue: 0.14))
                        .frame(width: 48, height: 48)
                        .overlay(
                            Image(systemName: "headphones")
                                .font(.system(size: 18))
                                .foregroundStyle(Color(red: 0.40, green: 0.37, blue: 0.34))
                        )
                }
                
                // Title + author
                VStack(alignment: .leading, spacing: 2) {
                    Text(nowPlaying.title)
                        .font(.caption.bold())
                        .foregroundStyle(Color(red: 0.95, green: 0.93, blue: 0.90))
                        .lineLimit(2)
                    
                    Text(nowPlaying.author)
                        .font(.system(size: 10))
                        .foregroundStyle(Color(red: 0.70, green: 0.66, blue: 0.62))
                        .lineLimit(1)
                }
            }
            
            Spacer(minLength: 4)
            
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(red: 0.22, green: 0.20, blue: 0.18))
                        .frame(height: 4)
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(red: 0.85, green: 0.45, blue: 0.40))
                        .frame(width: geo.size.width * nowPlaying.progress, height: 4)
                }
            }
            .frame(height: 4)
            
            // Stats
            HStack {
                Text("\(nowPlaying.progressPercentage)%")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color(red: 0.85, green: 0.45, blue: 0.40))
                Spacer()
                Text("\(nowPlaying.formattedRemaining) left")
                    .font(.system(size: 9))
                    .foregroundStyle(Color(red: 0.70, green: 0.66, blue: 0.62))
            }
            .padding(.top, 3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetBackground()
    }
}

// MARK: - Widget Configuration

struct NowPlayingWidget: Widget {
    let kind: String = "NowPlayingWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NowPlayingTimelineProvider()) { entry in
            NowPlayingWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Now Playing")
        .description("See your current or last listened audiobook.")
        .supportedFamilies([.systemSmall])
    }
}

#Preview(as: .systemSmall) {
    NowPlayingWidget()
} timeline: {
    NowPlayingWidgetEntry(date: .now, nowPlaying: WidgetNowPlaying(
        audiobookId: "123",
        title: "The Art of Programming",
        author: "Jane Smith",
        coverUrl: nil,
        progress: 0.45,
        currentTime: 5400,
        duration: 12000,
        isPlaying: true,
        chapterTitle: "Chapter 5",
        updatedAt: Date()
    ), coverImageData: nil)
    NowPlayingWidgetEntry(date: .now, nowPlaying: WidgetNowPlaying(
        audiobookId: "456",
        title: "Clean Architecture",
        author: "Robert C. Martin",
        coverUrl: nil,
        progress: 0.72,
        currentTime: 8640,
        duration: 12000,
        isPlaying: false,
        chapterTitle: "Chapter 12",
        updatedAt: Date()
    ), coverImageData: nil)
}
