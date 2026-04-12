//
//  PodcastHighlightsListView.swift
//  OpenClaw
//
//  Displays AI-generated highlights for a podcast episode
//

import SwiftUI
import Combine

// MARK: - ViewModel

@MainActor
final class PodcastHighlightsViewModel: ObservableObject {
    @Published var highlights: [PodcastHighlight] = []
    @Published var isLoading = false
    
    let episodeId: String
    let isTranscribed: Bool
    private let manager = PodcastHighlightManager.shared
    
    init(episodeId: String, isTranscribed: Bool = false) {
        self.episodeId = episodeId
        self.isTranscribed = isTranscribed
    }
    
    func load() async {
        isLoading = true
        highlights = await manager.fetchAndMergeHighlights(for: episodeId)
        print("[PodcastHighlightsVM] Loaded \(highlights.count) highlights for \(episodeId)")
        isLoading = false
    }
    
    func delete(_ highlight: PodcastHighlight) async {
        await manager.deleteHighlight(id: highlight.id, episodeId: episodeId)
        highlights.removeAll { $0.id == highlight.id }
    }
    
    func retryFailed() async {
        isLoading = true
        await manager.retryFailedHighlights(for: episodeId, isTranscribed: isTranscribed)
        highlights = await manager.loadHighlights(for: episodeId)
        isLoading = false
    }
}

// MARK: - View

struct PodcastHighlightsListView: View {
    @ObservedObject private var viewModel: PodcastHighlightsViewModel
    @EnvironmentObject private var playerManager: AudioPlayerManager
    
    /// Create with an existing ViewModel (shared with parent view)
    init(viewModel: PodcastHighlightsViewModel) {
        self._viewModel = ObservedObject(wrappedValue: viewModel)
    }
    
    /// Create with episode ID (standalone usage)
    init(episodeId: String, isTranscribed: Bool = false) {
        self._viewModel = ObservedObject(wrappedValue: PodcastHighlightsViewModel(episodeId: episodeId, isTranscribed: isTranscribed))
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
            Text("Triple-press AirPods or tap the bookmark button while listening")
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
                PodcastHighlightRow(highlight: highlight) {
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

// MARK: - Podcast Highlight Row

struct PodcastHighlightRow: View {
    let highlight: PodcastHighlight
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
                    if let episodeTitle = highlight.episodeTitle {
                        Text(episodeTitle)
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
                        
                        // References extracted from transcript
                        if let references = highlight.references, !references.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(references) { ref in
                                    PodcastReferenceRow(reference: ref)
                                }
                            }
                            .padding(.top, 4)
                        }
                        
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

// MARK: - Reference Row

struct PodcastReferenceRow: View {
    let reference: PodcastReference
    
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: reference.type.icon)
                .font(.caption2)
                .foregroundStyle(Color.anthropicCoral.opacity(0.8))
                .frame(width: 14)
            
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(reference.title)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.textPrimary)
                    
                    if let authors = reference.authors {
                        Text("— \(authors)")
                            .font(.caption2)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
                .lineLimit(1)
                
                if let description = reference.description {
                    Text(description)
                        .font(.caption2)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
        .background(Color.surfaceSecondary, in: RoundedRectangle(cornerRadius: 6))
    }
}
