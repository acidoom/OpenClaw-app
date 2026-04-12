//
//  AudiobookDetailView.swift
//  OpenClaw
//
//  Audiobook detail sheet with metadata, chapters, and play button
//

import SwiftUI
import Combine

struct AudiobookDetailView: View {
    let audiobook: Audiobook
    @ObservedObject var libraryViewModel: AudiobooksViewModel
    @EnvironmentObject private var playerManager: AudioPlayerManager
    @StateObject private var viewModel: AudiobookDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    init(audiobook: Audiobook, libraryViewModel: AudiobooksViewModel) {
        self.audiobook = audiobook
        self.libraryViewModel = libraryViewModel
        self._viewModel = StateObject(wrappedValue: AudiobookDetailViewModel(audiobookId: audiobook.id))
    }
    
    private var isCurrentBook: Bool {
        playerManager.currentAudiobook?.id == audiobook.id
    }
    
    @State private var isStartingServerDownload = false
    @State private var serverDownloadMessage: String?
    
    private var downloadState: LocalDownloadState {
        libraryViewModel.localDownloadState(for: audiobook.id)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundDark.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Cover art
                        coverSection
                        
                        // Metadata
                        metadataSection
                        
                        // Play button (always show — stream may work even when downloaded=false)
                        playButton
                        
                        if audiobook.downloaded {
                            // Download to device button
                            downloadSection
                        } else {
                            // Audio may not be on server yet — show download trigger
                            notDownloadedSection
                        }
                        
                        // Processing status
                        processingStatusSection
                        
                        // AI Highlights (only for transcribed books)
                        HighlightsListView(audiobookId: audiobook.id, isTranscribed: audiobook.transcribed)
                        
                        // Chapters
                        chapterListSection
                    }
                    .padding()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.anthropicCoral)
                }
            }
            .task {
                await viewModel.loadChapters()
            }
        }
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Cover
    
    private var coverSection: some View {
        CoverImageView(coverUrl: audiobook.coverUrl)
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: horizontalSizeClass == .regular ? 280 : 200, maxHeight: horizontalSizeClass == .regular ? 280 : 200)
            .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
    }
    
    // MARK: - Metadata
    
    private var metadataSection: some View {
        VStack(spacing: 8) {
            Text(audiobook.title)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.center)
            
            Text(audiobook.author)
                .font(.headline)
                .foregroundStyle(Color.textSecondary)
            
            if let narrator = audiobook.narrator {
                Text("Narrated by \(narrator)")
                    .font(.subheadline)
                    .foregroundStyle(Color.textTertiary)
            }
            
            HStack(spacing: 16) {
                Label(audiobook.formattedDuration, systemImage: "clock")
                Label(audiobook.format.rawValue.uppercased(), systemImage: "waveform")
            }
            .font(.caption)
            .foregroundStyle(Color.textTertiary)
        }
    }
    
    // MARK: - Not Downloaded (server-side)
    
    private var notDownloadedSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "icloud.and.arrow.down")
                    .foregroundStyle(Color.textTertiary)
                Text("Audio file not yet on server")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            }
            
            Button {
                Task {
                    isStartingServerDownload = true
                    serverDownloadMessage = nil
                    do {
                        serverDownloadMessage = try await libraryViewModel.startServerDownload(bookId: audiobook.id)
                    } catch {
                        serverDownloadMessage = "Failed: \(error.localizedDescription)"
                    }
                    isStartingServerDownload = false
                }
            } label: {
                HStack(spacing: 12) {
                    if isStartingServerDownload {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.down.to.line")
                    }
                    Text("Download to Server")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.anthropicCoral)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(isStartingServerDownload)
            
            if let msg = serverDownloadMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            
            // Show active download job if exists
            if let job = libraryViewModel.downloadJob(for: audiobook.id) {
                serverDownloadJobView(job)
            }
        }
    }
    
    @ViewBuilder
    private func serverDownloadJobView(_ job: DownloadJob) -> some View {
        HStack(spacing: 12) {
            switch job.status {
            case .queued:
                Image(systemName: "clock")
                    .foregroundStyle(Color.textTertiary)
                Text("Queued for download...")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            case .downloading:
                ProgressView()
                    .tint(Color.anthropicCoral)
                    .scaleEffect(0.7)
                if let progress = job.progress {
                    ProgressView(value: progress)
                        .tint(Color.anthropicCoral)
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                } else {
                    Text("Downloading...")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Download complete — refresh to play")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(job.errorMessage ?? "Download failed")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
    
    // MARK: - Play Button
    
    private var playButton: some View {
        VStack(spacing: 8) {
            Button {
                Task {
                    await playerManager.play(audiobook: audiobook)
                    // Only dismiss if playback started successfully
                    if playerManager.playerError == nil {
                        dismiss()
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    if playerManager.isBuffering && playerManager.currentAudiobook?.id == audiobook.id {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: isCurrentBook ? "play.fill" : "play.circle.fill")
                    }
                    Text(playerManager.isBuffering && playerManager.currentAudiobook?.id == audiobook.id
                         ? "Loading..."
                         : (isCurrentBook ? "Resume" : "Play"))
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.anthropicCoral)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            
            if let error = playerManager.playerError, playerManager.currentAudiobook?.id == audiobook.id {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.surfaceSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
    
    // MARK: - Download to Device Section
    
    @ViewBuilder
    private var downloadSection: some View {
        switch downloadState {
        case .notDownloaded:
            Button {
                libraryViewModel.downloadToDevice(audiobook: audiobook)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.down.circle")
                    Text("Download to Device")
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.surfaceSecondary)
                .foregroundStyle(Color.anthropicCoral)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            
        case .downloading(let progress):
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(Color.anthropicCoral)
                        .scaleEffect(0.8)
                    Text("Downloading... \(Int(progress * 100))%")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Button {
                        libraryViewModel.cancelLocalDownload(audiobook: audiobook)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.textTertiary)
                    }
                }
                ProgressView(value: progress)
                    .tint(Color.anthropicCoral)
            }
            .padding(12)
            .background(Color.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            
        case .downloaded:
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Downloaded to Device")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Button {
                    Task { await libraryViewModel.removeLocalFile(audiobook: audiobook) }
                } label: {
                    Text("Remove")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(12)
            .background(Color.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            
        case .failed(let error):
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text("Download failed")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                }
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(2)
                Button {
                    libraryViewModel.downloadToDevice(audiobook: audiobook)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                        Text("Retry")
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.anthropicCoral)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(12)
            .background(Color.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
    
    // MARK: - Processing Status
    
    private var processingStatusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("STATUS")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Color.textSecondary)
                .tracking(0.5)
            
            HStack(spacing: 12) {
                statusPill("Downloaded", active: audiobook.downloaded)
                statusPill("Transcribed", active: audiobook.transcribed)
                statusPill("Indexed", active: audiobook.indexed)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func statusPill(_ text: String, active: Bool) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(active ? Color.statusConnected.opacity(0.2) : Color.surfaceSecondary)
            .foregroundStyle(active ? Color.statusConnected : Color.textTertiary)
            .clipShape(Capsule())
    }
    
    // MARK: - Chapter List
    
    private var chapterListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CHAPTERS")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Color.textSecondary)
                .tracking(0.5)
            
            if viewModel.isLoadingChapters {
                HStack {
                    Spacer()
                    ProgressView()
                        .tint(Color.anthropicCoral)
                    Spacer()
                }
                .padding()
            } else if viewModel.chapters.isEmpty {
                Text("No chapters available")
                    .font(.subheadline)
                    .foregroundStyle(Color.textTertiary)
                    .padding()
            } else {
                VStack(spacing: 1) {
                    ForEach(viewModel.chapters) { chapter in
                        Button {
                            Task {
                                await playerManager.play(audiobook: audiobook)
                                playerManager.goToChapter(chapter)
                                dismiss()
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Text("\(chapter.chapterIndex + 1)")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(
                                        playerManager.currentChapter?.id == chapter.id
                                            ? Color.anthropicCoral
                                            : Color.textTertiary
                                    )
                                    .frame(width: 28)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(chapter.title)
                                        .font(.subheadline)
                                        .foregroundStyle(
                                            playerManager.currentChapter?.id == chapter.id
                                                ? Color.anthropicCoral
                                                : Color.textPrimary
                                        )
                                        .lineLimit(1)
                                    
                                    Text(chapter.formattedDuration)
                                        .font(.caption2)
                                        .foregroundStyle(Color.textTertiary)
                                }
                                
                                Spacer()
                                
                                if playerManager.currentChapter?.id == chapter.id {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .font(.caption)
                                        .foregroundStyle(Color.anthropicCoral)
                                }
                            }
                            .padding()
                            .background(Color.surfacePrimary)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

// MARK: - Detail ViewModel

@MainActor
final class AudiobookDetailViewModel: ObservableObject {
    @Published var chapters: [AudiobookChapter] = []
    @Published var isLoadingChapters = false
    
    private let audiobookId: String
    private let service = LibroAIService.shared
    
    init(audiobookId: String) {
        self.audiobookId = audiobookId
    }
    
    func loadChapters() async {
        isLoadingChapters = true
        do {
            chapters = try await service.fetchChapters(audiobookId: audiobookId)
        } catch {
            print("[AudiobookDetail] Error loading chapters: \(error)")
        }
        isLoadingChapters = false
    }
}
