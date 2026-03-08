//
//  HighlightsListView.swift
//  OpenClaw
//
//  Displays AI-generated highlights for an audiobook
//

import SwiftUI
import Combine

// MARK: - ViewModel

@MainActor
final class HighlightsViewModel: ObservableObject {
    @Published var highlights: [AudiobookHighlight] = []
    @Published var isLoading = false
    
    let audiobookId: String
    let isTranscribed: Bool
    private let manager = HighlightManager.shared
    
    init(audiobookId: String, isTranscribed: Bool = false) {
        self.audiobookId = audiobookId
        self.isTranscribed = isTranscribed
    }
    
    func load() async {
        isLoading = true
        highlights = await manager.fetchAndMergeHighlights(for: audiobookId)
        print("[HighlightsVM] Loaded \(highlights.count) highlights for \(audiobookId)")
        for h in highlights {
            print("[HighlightsVM]   - \(h.id.prefix(8))... status=\(h.status.rawValue) pos=\(h.formattedTimestamp)")
        }
        isLoading = false
    }
    
    func delete(_ highlight: AudiobookHighlight) async {
        await manager.deleteHighlight(id: highlight.id, audiobookId: audiobookId)
        highlights.removeAll { $0.id == highlight.id }
    }
    
    func retryFailed() async {
        isLoading = true
        await manager.retryFailedHighlights(for: audiobookId, isTranscribed: isTranscribed)
        highlights = await manager.loadHighlights(for: audiobookId)
        isLoading = false
    }
}

// MARK: - View

struct HighlightsListView: View {
    @StateObject private var viewModel: HighlightsViewModel
    @EnvironmentObject private var playerManager: AudioPlayerManager
    
    init(audiobookId: String, isTranscribed: Bool = false) {
        self._viewModel = StateObject(wrappedValue: HighlightsViewModel(audiobookId: audiobookId, isTranscribed: isTranscribed))
    }
    
    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.highlights.isEmpty {
                loadingView
            } else if viewModel.highlights.isEmpty {
                emptyView
            } else {
                highlightsList
            }
        }
        .task {
            await viewModel.load()
        }
    }
    
    // MARK: - Subviews
    
    private var loadingView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .tint(.anthropicCoral)
            Text("Loading highlights...")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        }
        .padding(.vertical, 12)
    }
    
    private var emptyView: some View {
        VStack(spacing: 6) {
            Image(systemName: "bookmark")
                .font(.title3)
                .foregroundStyle(Color.textTertiary)
            Text("No highlights yet")
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
            Text("Triple-press AirPods or tap the bookmark button to create one")
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 16)
    }
    
    private var highlightsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            HStack {
                Image(systemName: "bookmark.fill")
                    .font(.caption)
                    .foregroundStyle(Color.anthropicCoral)
                
                Text("AI HIGHLIGHTS")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.textTertiary)
                
                Spacer()
                
                if viewModel.highlights.contains(where: { $0.status == .failed || $0.status == .pending }) {
                    Button {
                        Task { await viewModel.retryFailed() }
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                            .font(.caption2)
                            .foregroundStyle(Color.anthropicCoral)
                    }
                }
                
                Text("\(viewModel.highlights.count)")
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.surfaceSecondary, in: Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            
            ForEach(viewModel.highlights) { highlight in
                HighlightRow(highlight: highlight) {
                    playerManager.seek(to: highlight.positionSeconds)
                }
                .contextMenu {
                    Button(role: .destructive) {
                        Task { await viewModel.delete(highlight) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                
                if highlight.id != viewModel.highlights.last?.id {
                    Divider()
                        .padding(.leading, 68)
                }
            }
        }
        .padding(.vertical, 12)
        .background(Color.surfaceSecondary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Highlight Row

struct HighlightRow: View {
    let highlight: AudiobookHighlight
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                // Timestamp column
                VStack(spacing: 2) {
                    Image(systemName: statusIcon)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                    
                    Text(highlight.formattedTimestamp)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Color.textSecondary)
                }
                .frame(width: 52)
                
                // Content
                VStack(alignment: .leading, spacing: 4) {
                    if let chapter = highlight.chapterTitle {
                        Text(chapter)
                            .font(.caption2)
                            .foregroundStyle(Color.textTertiary)
                            .lineLimit(1)
                    }
                    
                    switch highlight.status {
                    case .completed:
                        Text(highlight.highlightText ?? "")
                            .font(.subheadline)
                            .foregroundStyle(Color.textPrimary)
                            .multilineTextAlignment(.leading)
                        
                    case .processing:
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Generating summary...")
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                        
                    case .pending:
                        Text("Bookmark saved — summary available after transcription")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                            .italic()
                        
                    case .failed:
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(Color.statusDisconnected)
                            Text("Summary failed — tap Retry")
                                .font(.caption)
                                .foregroundStyle(Color.statusDisconnected)
                        }
                    }
                    
                    Text(highlight.formattedDate)
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                }
                
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private var statusIcon: String {
        switch highlight.status {
        case .completed: return "bookmark.fill"
        case .processing: return "sparkles"
        case .pending: return "bookmark"
        case .failed: return "exclamationmark.triangle"
        }
    }
    
    private var statusColor: Color {
        switch highlight.status {
        case .completed: return .anthropicCoral
        case .processing: return .anthropicOrange
        case .pending: return .textTertiary
        case .failed: return .statusDisconnected
        }
    }
}
