//
//  AudiobooksView.swift
//  OpenClaw
//
//  Main audiobook library tab view
//

import SwiftUI

struct AudiobooksView: View {
    @StateObject private var viewModel = AudiobooksViewModel()
    @EnvironmentObject private var playerManager: AudioPlayerManager
    @State private var selectedAudiobook: Audiobook?
    @State private var showingSettings = false
    @State private var showingLibroFmSettings = false
    @State private var showingLibroFmBooks = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundDark.ignoresSafeArea()
                
                if !viewModel.isConfigured {
                    notConfiguredView
                } else if viewModel.isLoading && viewModel.audiobooks.isEmpty {
                    loadingView
                } else if let error = viewModel.errorMessage, viewModel.audiobooks.isEmpty {
                    errorView(error)
                } else {
                    libraryContent
                }
                
                // Mini player overlay
                if playerManager.hasActiveSession {
                    VStack {
                        Spacer()
                        MiniPlayerView()
                    }
                }
            }
            .navigationTitle("Audiobooks")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.backgroundDark, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            Task { await viewModel.refresh() }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        
                        Button {
                            Task { await viewModel.syncFromLibroFM() }
                        } label: {
                            Label("Sync from Libro.fm", systemImage: "arrow.triangle.2.circlepath")
                        }
                        
                        Divider()
                        
                        if viewModel.isLibroFmConnected {
                            Button {
                                showingLibroFmBooks = true
                            } label: {
                                Label("Browse Libro.fm", systemImage: "books.vertical")
                            }
                            
                            Button {
                                showingLibroFmSettings = true
                            } label: {
                                Label("Libro.fm Account", systemImage: "person.circle")
                            }
                        } else {
                            Button {
                                showingLibroFmSettings = true
                            } label: {
                                Label("Sign In to Libro.fm", systemImage: "person.badge.plus")
                            }
                        }
                        
                        Divider()
                        
                        Menu("Sort By") {
                            ForEach(AudiobookSortOrder.allCases, id: \.self) { order in
                                Button {
                                    viewModel.sortOrder = order
                                } label: {
                                    HStack {
                                        Text(order.displayName)
                                        if viewModel.sortOrder == order {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(Color.anthropicCoral)
                    }
                }
            }
            .sheet(item: $selectedAudiobook) { audiobook in
                AudiobookDetailView(audiobook: audiobook, libraryViewModel: viewModel)
                    .environmentObject(playerManager)
            }
            .sheet(isPresented: $showingLibroFmSettings) {
                LibroFmSettingsSheet(viewModel: viewModel)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showingLibroFmBooks) {
                LibroFmBooksView(viewModel: viewModel)
            }
            .task {
                await viewModel.loadIfNeeded()
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Library Content
    
    private var libraryContent: some View {
        VStack(spacing: 0) {
            // Search bar
            searchBar
            
            // Download status
            if viewModel.hasActiveDownloads {
                let activeCount = viewModel.downloadJobs.filter { $0.status == .queued || $0.status == .downloading }.count
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(Color.anthropicCoral)
                        .scaleEffect(0.7)
                    Text("Downloading \(activeCount) book\(activeCount == 1 ? "" : "s")...")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Button {
                        showingLibroFmBooks = true
                    } label: {
                        Text("View")
                            .font(.caption)
                            .foregroundStyle(Color.anthropicCoral)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.surfaceSecondary)
            }
            
            // Sync status
            if let syncMsg = viewModel.syncMessage {
                HStack {
                    if viewModel.isSyncing {
                        ProgressView()
                            .tint(Color.anthropicCoral)
                            .scaleEffect(0.8)
                    }
                    Text(syncMsg)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            
            // Grid
            ScrollView {
                if viewModel.filteredAudiobooks.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.textTertiary)
                        Text(viewModel.searchQuery.isEmpty ? "No audiobooks yet" : "No results")
                            .font(.headline)
                            .foregroundStyle(Color.textSecondary)
                        if viewModel.searchQuery.isEmpty {
                            Text("Sync your Libro.fm library to get started")
                                .font(.subheadline)
                                .foregroundStyle(Color.textTertiary)
                        }
                    }
                    .padding(.top, 80)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 16
                    ) {
                        ForEach(viewModel.filteredAudiobooks) { audiobook in
                            AudiobookGridCell(
                                audiobook: audiobook,
                                localState: viewModel.localDownloadState(for: audiobook.id)
                            )
                            .onTapGesture {
                                selectedAudiobook = audiobook
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, playerManager.hasActiveSession ? 80 : 16)
                }
            }
            .refreshable {
                await viewModel.refresh()
            }
        }
    }
    
    // MARK: - Search Bar
    
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.textTertiary)
            
            TextField("Search audiobooks...", text: $viewModel.searchQuery)
                .foregroundStyle(Color.textPrimary)
                .autocorrectionDisabled()
            
            if !viewModel.searchQuery.isEmpty {
                Button {
                    viewModel.searchQuery = ""
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
    
    // MARK: - Not Configured
    
    private var notConfiguredView: some View {
        VStack(spacing: 24) {
            Image(systemName: "headphones")
                .font(.system(size: 60))
                .foregroundStyle(Color.textSecondary)
            
            Text("Configure Audiobooks")
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
            
            Text("Audiobooks use your OpenClaw Gateway connection.\nSet up your endpoint and hook token in Settings.")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Button {
                NotificationCenter.default.post(name: NSNotification.Name("OpenSettings"), object: nil)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "gear")
                    Text("Open Settings")
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
    
    // MARK: - Loading
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(Color.anthropicCoral)
                .scaleEffect(1.2)
            Text("Loading library...")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
        }
    }
    
    // MARK: - Error
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(Color.statusDisconnected)
            
            Text("Error")
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
            
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Button {
                Task { await viewModel.refresh() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                    Text("Retry")
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
}

// MARK: - Grid Cell

struct AudiobookGridCell: View {
    let audiobook: Audiobook
    var localState: LocalDownloadState = .notDownloaded
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Cover art with status overlays
            ZStack {
                coverImage
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                
                // Not on server indicator (top-left)
                if !audiobook.downloaded {
                    VStack {
                        HStack {
                            Image(systemName: "icloud.and.arrow.down")
                                .font(.caption2)
                                .foregroundStyle(.white)
                                .padding(5)
                                .background(.black.opacity(0.6))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .padding(6)
                            Spacer()
                        }
                        Spacer()
                    }
                }
                
                // Local download indicator (bottom-right)
                if localState.isDownloaded {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.white)
                                .padding(6)
                                .background(.black.opacity(0.5))
                                .clipShape(Circle())
                                .padding(6)
                        }
                    }
                } else if localState.isDownloading {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.6)
                                .padding(6)
                                .background(.black.opacity(0.5))
                                .clipShape(Circle())
                                .padding(6)
                        }
                    }
                }
            }
            
            // Title
            Text(audiobook.title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(2)
            
            // Author
            Text(audiobook.author)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
            
            // Duration
            Text(audiobook.formattedDuration)
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
        }
    }
    
    private var coverImage: some View {
        CoverImageView(coverUrl: audiobook.coverUrl)
    }
}

// MARK: - Audiobook Identifiable for sheet

extension Audiobook: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
