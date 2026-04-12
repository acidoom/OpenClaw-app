//
//  PodcastSearchView.swift
//  OpenClaw
//
//  iTunes podcast search with subscribe functionality
//

import SwiftUI

struct PodcastSearchView: View {
    @ObservedObject var viewModel: PodcastsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundDark.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Search bar
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(Color.textTertiary)
                        
                        TextField("Search Apple Podcasts...", text: $query)
                            .foregroundStyle(Color.textPrimary)
                            .autocorrectionDisabled()
                            .onSubmit {
                                viewModel.search(query: query)
                            }
                        
                        if !query.isEmpty {
                            Button {
                                query = ""
                                viewModel.searchResults = []
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
                    
                    // Results
                    if viewModel.isSearching {
                        Spacer()
                        ProgressView()
                            .tint(Color.anthropicCoral)
                        Text("Searching...")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                            .padding(.top, 8)
                        Spacer()
                    } else if viewModel.searchResults.isEmpty && !query.isEmpty {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 40))
                                .foregroundStyle(Color.textTertiary)
                            Text("No podcasts found")
                                .font(.headline)
                                .foregroundStyle(Color.textSecondary)
                        }
                        Spacer()
                    } else if viewModel.searchResults.isEmpty {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 40))
                                .foregroundStyle(Color.textTertiary)
                            Text("Search for podcasts")
                                .font(.headline)
                                .foregroundStyle(Color.textSecondary)
                            Text("Find and subscribe to your favorite shows")
                                .font(.subheadline)
                                .foregroundStyle(Color.textTertiary)
                        }
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(viewModel.searchResults) { podcast in
                                    SearchResultRow(
                                        podcast: podcast,
                                        isSubscribed: viewModel.isSubscribed(itunesId: podcast.id),
                                        isSubscribing: viewModel.subscribingIds.contains(podcast.id)
                                    ) {
                                        Task { await viewModel.subscribe(podcast: podcast) }
                                    }
                                    
                                    if podcast.id != viewModel.searchResults.last?.id {
                                        Divider()
                                            .padding(.leading, 76)
                                    }
                                }
                            }
                            .padding(.bottom, 16)
                        }
                    }
                }
            }
            .navigationTitle("Search Podcasts")
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
            .onChange(of: query) { _, newValue in
                viewModel.search(query: newValue)
            }
            .alert("Subscribe Error", isPresented: .init(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Search Result Row

struct SearchResultRow: View {
    let podcast: iTunesPodcast
    let isSubscribed: Bool
    var isSubscribing: Bool = false
    let onSubscribe: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Artwork
            AsyncImage(url: URL(string: podcast.artworkUrl ?? "")) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.surfaceSecondary)
                    .overlay(
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                    )
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(podcast.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                
                Text(podcast.author)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                
                if let trackCount = podcast.trackCount {
                    Text("\(trackCount) episodes")
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                }
            }
            
            Spacer()
            
            // Subscribe button
            if isSubscribed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.statusConnected)
            } else if isSubscribing {
                ProgressView()
                    .tint(Color.anthropicCoral)
            } else {
                Button {
                    onSubscribe()
                } label: {
                    Text("Subscribe")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.anthropicCoral)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
