//
//  LibroFmBooksView.swift
//  OpenClaw
//
//  Browse and download Libro.fm audiobooks
//

import SwiftUI

struct LibroFmBooksView: View {
    @ObservedObject var viewModel: AudiobooksViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var searchQuery = ""
    
    var filteredBooks: [LibroFmBook] {
        if searchQuery.isEmpty {
            return viewModel.libroFmBooks
        }
        let query = searchQuery.lowercased()
        return viewModel.libroFmBooks.filter { book in
            book.title.lowercased().contains(query) ||
            book.author.lowercased().contains(query)
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundDark.ignoresSafeArea()
                
                if viewModel.isLoadingLibroFm && viewModel.libroFmBooks.isEmpty {
                    loadingView
                } else if viewModel.libroFmBooks.isEmpty {
                    emptyView
                } else {
                    bookListContent
                }
            }
            .navigationTitle("Libro.fm Books")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.backgroundDark, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.anthropicCoral)
                }
                
                ToolbarItem(placement: .topBarLeading) {
                    if !viewModel.libroFmBooks.isEmpty {
                        Button {
                            Task { await downloadAllAvailable() }
                        } label: {
                            Label("Download All", systemImage: "arrow.down.circle")
                                .foregroundStyle(Color.anthropicCoral)
                        }
                        .disabled(viewModel.hasActiveDownloads)
                    }
                }
            }
            .task {
                await viewModel.loadLibroFmBooks()
                await viewModel.refreshDownloadJobs()
                if viewModel.hasActiveDownloads {
                    viewModel.startDownloadPolling()
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Book List
    
    private var bookListContent: some View {
        VStack(spacing: 0) {
            // Search bar
            searchBar
            
            // Download status banner
            if viewModel.hasActiveDownloads {
                downloadBanner
            }
            
            // Book list
            List {
                ForEach(filteredBooks) { book in
                    LibroFmBookRow(
                        book: book,
                        downloadJob: viewModel.downloadJob(for: book.id),
                        onDownload: {
                            Task { await viewModel.startDownload(bookId: book.id) }
                        }
                    )
                    .listRowBackground(Color.surfaceSecondary)
                }
            }
            .listStyle(.plain)
            .refreshable {
                await viewModel.loadLibroFmBooks()
                await viewModel.refreshDownloadJobs()
            }
        }
    }
    
    // MARK: - Search Bar
    
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.textTertiary)
            
            TextField("Search books...", text: $searchQuery)
                .foregroundStyle(Color.textPrimary)
                .autocorrectionDisabled()
            
            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.textTertiary)
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    
    // MARK: - Download Banner
    
    private var downloadBanner: some View {
        let activeJobs = viewModel.downloadJobs.filter { $0.status == .queued || $0.status == .downloading }
        return HStack(spacing: 8) {
            ProgressView()
                .tint(Color.anthropicCoral)
                .scaleEffect(0.8)
            
            Text("Downloading \(activeJobs.count) book\(activeJobs.count == 1 ? "" : "s")...")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.surfaceSecondary)
    }
    
    // MARK: - Loading
    
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
    
    // MARK: - Empty
    
    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "books.vertical")
                .font(.system(size: 48))
                .foregroundStyle(Color.textTertiary)
            
            Text("No Books Found")
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
            
            Text("Your Libro.fm library appears to be empty.")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
            
            Button {
                Task { await viewModel.loadLibroFmBooks() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                    Text("Refresh")
                }
                .fontWeight(.semibold)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.anthropicCoral)
                .foregroundStyle(.white)
                .clipShape(Capsule())
            }
        }
    }
    
    // MARK: - Actions
    
    private func downloadAllAvailable() async {
        let available = viewModel.libroFmBooks.filter { !$0.inLibrary }
        for book in available {
            if viewModel.downloadJob(for: book.id) == nil {
                await viewModel.startDownload(bookId: book.id)
            }
        }
    }
}

// MARK: - Book Row

struct LibroFmBookRow: View {
    let book: LibroFmBook
    let downloadJob: DownloadJob?
    let onDownload: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Cover thumbnail
            coverImage
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                
                Text(book.author)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Status / Action
            statusView
        }
        .padding(.vertical, 4)
    }
    
    private var coverImage: some View {
        CoverImageView(coverUrl: book.coverUrl, cornerRadius: 8)
    }
    
    @ViewBuilder
    private var statusView: some View {
        if book.inLibrary {
            // Already in library
            Label("In Library", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        } else if let job = downloadJob {
            switch job.status {
            case .queued:
                Label("Queued", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            case .downloading:
                HStack(spacing: 6) {
                    if let progress = job.progress {
                        ProgressView(value: progress)
                            .tint(Color.anthropicCoral)
                            .frame(width: 40)
                        Text("\(Int(progress * 100))%")
                            .font(.caption2)
                            .foregroundStyle(Color.textSecondary)
                    } else {
                        ProgressView()
                            .tint(Color.anthropicCoral)
                            .scaleEffect(0.7)
                    }
                }
            case .completed:
                Label("Done", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            case .failed:
                VStack(spacing: 2) {
                    Label("Failed", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                    Button("Retry", action: onDownload)
                        .font(.caption2)
                        .foregroundStyle(Color.anthropicCoral)
                }
            }
        } else {
            // Available for download
            Button(action: onDownload) {
                Label("Download", systemImage: "arrow.down.circle")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.anthropicCoral)
            }
        }
    }
}
