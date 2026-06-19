//
//  PodcastBooksView.swift
//  OpenClaw
//
//  Digest of books mentioned across podcast transcripts within a recent window.
//

import SwiftUI
import Combine

// MARK: - ViewModel

@MainActor
final class PodcastBooksViewModel: ObservableObject {
    @Published var books: [CollectedPodcastBook] = []
    @Published var isLoading = false

    /// Rolling window for "recently mentioned" books.
    let windowDays: Int

    init(windowDays: Int = 90) {
        self.windowDays = windowDays
    }

    func load() async {
        isLoading = true

        let cutoff = Date().addingTimeInterval(-Double(windowDays) * 86_400)

        // Source 1: the dedicated book store (episode scans + highlight extraction).
        let stored = await PodcastBookStore.shared.recentBooks(withinDays: windowDays)

        // Source 2: books surfaced by previously-saved highlights (durable, pre-dates
        // the book store), so books discovered before this feature still appear.
        let highlightBooks: [CollectedPodcastBook] = await PodcastHighlightStore.shared
            .loadAllHighlights()
            .filter { $0.status == .completed && $0.createdAt >= cutoff }
            .flatMap { highlight in
                (highlight.references ?? [])
                    .filter { $0.type == .book }
                    .map {
                        CollectedPodcastBook(
                            reference: $0,
                            episodeId: highlight.episodeId,
                            episodeTitle: highlight.episodeTitle,
                            podcastId: highlight.podcastId,
                            podcastTitle: nil,
                            collectedAt: highlight.createdAt
                        )
                    }
            }

        // Merge, de-duplicate by book identity (keep the most recent mention).
        var byBook: [String: CollectedPodcastBook] = [:]
        for book in stored + highlightBooks {
            let key = book.reference.id
            if let existing = byBook[key], existing.collectedAt >= book.collectedAt {
                continue
            }
            byBook[key] = book
        }
        books = byBook.values.sorted { $0.collectedAt > $1.collectedAt }

        isLoading = false
    }
}

// MARK: - View

struct PodcastBooksView: View {
    @StateObject private var viewModel = PodcastBooksViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundDark.ignoresSafeArea()

                if viewModel.isLoading && viewModel.books.isEmpty {
                    loadingView
                } else if viewModel.books.isEmpty {
                    emptyView
                } else {
                    booksList
                }
            }
            .navigationTitle("Books Mentioned")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.backgroundDark, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.anthropicCoral)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { await viewModel.load() }
    }

    // MARK: - Books List

    private var booksList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Books referenced in podcasts you've listened to over the last \(viewModel.windowDays) days.")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                LazyVStack(spacing: 0) {
                    ForEach(viewModel.books) { book in
                        PodcastBookRow(book: book)

                        if book.id != viewModel.books.last?.id {
                            Divider().padding(.leading, 76)
                        }
                    }
                }
            }
            .padding(.bottom, 16)
        }
        .refreshable { await viewModel.load() }
    }

    // MARK: - Loading / Empty

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(Color.anthropicCoral)
                .scaleEffect(1.2)
            Text("Loading books...")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
        }
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "books.vertical")
                .font(.system(size: 44))
                .foregroundStyle(Color.textTertiary)
            Text("No books yet")
                .font(.headline)
                .foregroundStyle(Color.textSecondary)
            Text("Books mentioned in episodes you transcribe and bookmark will appear here.")
                .font(.subheadline)
                .foregroundStyle(Color.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}

// MARK: - Book Row

struct PodcastBookRow: View {
    let book: CollectedPodcastBook
    @Environment(\.openURL) private var openURL

    private var reference: PodcastReference { book.reference }

    var body: some View {
        Button {
            if let urlString = reference.url, let url = URL(string: urlString) {
                openURL(url)
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                // Cover
                if let coverString = reference.coverUrl, let coverURL = URL(string: coverString) {
                    AsyncImage(url: coverURL) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 6).fill(Color.surfaceSecondary)
                    }
                    .frame(width: 44, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.surfaceSecondary)
                        .frame(width: 44, height: 64)
                        .overlay(
                            Image(systemName: "book.closed")
                                .foregroundStyle(Color.textTertiary)
                        )
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(reference.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(2)

                    if let authors = reference.authors, !authors.isEmpty {
                        Text(authors)
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                    }

                    if let podcastTitle = book.podcastTitle ?? book.episodeTitle {
                        Text("From \(podcastTitle)")
                            .font(.caption2)
                            .foregroundStyle(Color.textTertiary)
                            .lineLimit(1)
                    }

                    HStack(spacing: 6) {
                        if let price = reference.price, !price.isEmpty {
                            Text("Libro.fm · \(price)")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundStyle(Color.anthropicCoral)
                        }

                        Text(book.collectedAt, format: .relative(presentation: .named))
                            .font(.caption2)
                            .foregroundStyle(Color.textTertiary)
                    }
                    .padding(.top, 1)
                }

                Spacer(minLength: 0)

                if reference.url != nil {
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption)
                        .foregroundStyle(Color.anthropicCoral)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
