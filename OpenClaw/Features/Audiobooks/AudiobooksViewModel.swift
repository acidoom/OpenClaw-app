//
//  AudiobooksViewModel.swift
//  OpenClaw
//
//  ViewModel for managing audiobook library state and operations
//

import Foundation
import Combine

@MainActor
final class AudiobooksViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var audiobooks: [Audiobook] = []
    @Published var searchQuery = ""
    @Published var isLoading = false
    @Published var isConfigured = false
    @Published var errorMessage: String?
    @Published var isSyncing = false
    @Published var syncMessage: String?
    @Published var sortOrder: AudiobookSortOrder = .title
    
    // Libro.fm state
    @Published var isLibroFmConnected = false
    @Published var libroFmEmail: String?
    @Published var libroFmBooks: [LibroFmBook] = []
    @Published var downloadJobs: [DownloadJob] = []
    @Published var isLoadingLibroFm = false
    
    // Local download state
    @Published var localDownloadStates: [String: LocalDownloadState] = [:]
    
    // MARK: - Private Properties
    
    private let service = LibroAIService.shared
    private let keychain = KeychainManager.shared
    private var cancellables = Set<AnyCancellable>()
    private var hasLoaded = false
    private var downloadPollTask: Task<Void, Never>?
    private var localDownloadTasks: [String: Task<Void, Never>] = [:]
    
    // MARK: - Computed Properties
    
    var filteredAudiobooks: [Audiobook] {
        var result = audiobooks
        
        // Filter by search query
        if !searchQuery.isEmpty {
            let query = searchQuery.lowercased()
            result = result.filter { book in
                book.title.lowercased().contains(query) ||
                book.author.lowercased().contains(query) ||
                (book.narrator?.lowercased().contains(query) ?? false)
            }
        }
        
        // Sort
        switch sortOrder {
        case .title:
            result.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .author:
            result.sort { $0.author.localizedCaseInsensitiveCompare($1.author) == .orderedAscending }
        case .duration:
            result.sort { $0.durationSeconds > $1.durationSeconds }
        }
        
        return result
    }
    
    // MARK: - Initialization
    
    init() {
        checkConfiguration()
        setupSearchDebounce()
        Task { await checkLibroFmStatus() }
    }
    
    // MARK: - Configuration
    
    func checkConfiguration() {
        isConfigured = keychain.hasLibroAICredentials()
    }
    
    // MARK: - Data Loading
    
    func loadIfNeeded() async {
        guard isConfigured, !hasLoaded else { return }
        await refresh()
        await refreshLocalDownloadStates()
    }
    
    func refresh() async {
        guard isConfigured, !isLoading else { return }
        
        isLoading = true
        errorMessage = nil
        
        do {
            var books = try await service.fetchLibrary(forceRefresh: true)
            
            // Fill in missing cover URLs from Libro.fm books
            let missingCovers = books.contains { $0.coverUrl == nil }
            if missingCovers && isLibroFmConnected {
                let libroBooks = try? await service.fetchLibroFmBooks()
                if let libroBooks {
                    // Build lookup: Libro.fm book ID → cover URL
                    let coverLookup = Dictionary(
                        libroBooks.compactMap { book in
                            book.coverUrl.map { (book.id, $0) }
                        },
                        uniquingKeysWith: { first, _ in first }
                    )
                    
                    // Patch audiobooks that are missing covers
                    for i in books.indices where books[i].coverUrl == nil {
                        if let coverUrl = coverLookup[books[i].id] {
                            books[i].coverUrl = coverUrl
                        }
                    }
                }
            }
            
            audiobooks = books
            hasLoaded = true
        } catch let urlError as URLError where urlError.code == .cancelled {
            // Ignore cancelled requests (race condition between concurrent loads)
            print("[AudiobooksVM] Request cancelled, ignoring")
        } catch {
            print("[AudiobooksVM] Error: \(error)")
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func syncFromLibroFM() async {
        guard isConfigured else { return }
        
        isSyncing = true
        syncMessage = nil
        
        do {
            let response = try await service.syncLibrary()
            if let added = response.booksAdded, added > 0 {
                syncMessage = "Added \(added) new audiobook\(added == 1 ? "" : "s")"
            } else {
                syncMessage = response.message ?? "Library is up to date"
            }
            
            // Refresh library after sync
            await refresh()
        } catch {
            print("[AudiobooksVM] Sync error: \(error)")
            syncMessage = "Sync failed: \(error.localizedDescription)"
        }
        
        isSyncing = false
        
        // Clear sync message after delay
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            syncMessage = nil
        }
    }
    
    // MARK: - Libro.fm
    
    func checkLibroFmStatus() async {
        guard isConfigured else {
            isLibroFmConnected = false
            libroFmEmail = nil
            return
        }
        
        do {
            let status = try await service.fetchLibroFmStatus()
            isLibroFmConnected = status.connected
            libroFmEmail = status.email
        } catch {
            print("[AudiobooksVM] Libro.fm status check failed: \(error)")
            isLibroFmConnected = false
            libroFmEmail = nil
        }
    }
    
    func loadLibroFmBooks() async {
        guard isConfigured, isLibroFmConnected else { return }
        
        isLoadingLibroFm = true
        
        do {
            libroFmBooks = try await service.fetchLibroFmBooks()
        } catch {
            print("[AudiobooksVM] Failed to load Libro.fm books: \(error)")
        }
        
        isLoadingLibroFm = false
    }
    
    func startDownload(bookId: String) async {
        guard isConfigured else { return }
        
        do {
            let response = try await service.startDownload(libroFmBookId: bookId)
            print("[AudiobooksVM] Download started: \(response.jobId)")
            await refreshDownloadJobs()
            startDownloadPolling()
        } catch {
            print("[AudiobooksVM] Download start failed: \(error)")
        }
    }
    
    /// Start a server-side download and return the response message
    func startServerDownload(bookId: String) async throws -> String {
        let response = try await service.startDownload(libroFmBookId: bookId)
        print("[AudiobooksVM] Server download started: \(response.jobId)")
        await refreshDownloadJobs()
        startDownloadPolling()
        return response.message ?? "Download queued"
    }
    
    func refreshDownloadJobs() async {
        guard isConfigured else { return }
        
        do {
            downloadJobs = try await service.fetchDownloadJobs()
        } catch {
            print("[AudiobooksVM] Failed to fetch download jobs: \(error)")
        }
    }
    
    func startDownloadPolling() {
        guard downloadPollTask == nil else { return }
        
        downloadPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { break }
                
                await self?.refreshDownloadJobs()
                
                let activeJobs = self?.downloadJobs.filter { $0.status == .queued || $0.status == .downloading } ?? []
                
                if activeJobs.isEmpty {
                    // All done — refresh library and stop polling
                    await self?.refresh()
                    await self?.loadLibroFmBooks()
                    break
                }
            }
            
            await MainActor.run {
                self?.downloadPollTask = nil
            }
        }
    }
    
    func stopDownloadPolling() {
        downloadPollTask?.cancel()
        downloadPollTask = nil
    }
    
    /// Returns the download job for a given book ID, if any
    func downloadJob(for bookId: String) -> DownloadJob? {
        downloadJobs.first { $0.bookId == bookId }
    }
    
    /// Whether there are active (queued or downloading) jobs
    var hasActiveDownloads: Bool {
        downloadJobs.contains { $0.status == .queued || $0.status == .downloading }
    }
    
    // MARK: - Local Downloads (to device)
    
    /// Check which audiobooks have local files on device
    func refreshLocalDownloadStates() async {
        for audiobook in audiobooks {
            // Don't overwrite in-progress downloads
            if case .downloading = localDownloadStates[audiobook.id] { continue }
            
            if let _ = await service.localFileURL(for: audiobook) {
                localDownloadStates[audiobook.id] = .downloaded(localURL: LibroAIService.localAudiobooksDirectory.appendingPathComponent("\(audiobook.id).\(audiobook.format.rawValue)"))
            } else if localDownloadStates[audiobook.id]?.isDownloaded != true {
                localDownloadStates[audiobook.id] = .notDownloaded
            }
        }
    }
    
    /// Download an audiobook's audio file to the device
    func downloadToDevice(audiobook: Audiobook) {
        guard localDownloadTasks[audiobook.id] == nil else { return }
        
        localDownloadStates[audiobook.id] = .downloading(progress: 0)
        
        localDownloadTasks[audiobook.id] = Task { [weak self] in
            do {
                let localURL = try await self?.service.downloadToDevice(
                    audiobook: audiobook,
                    onProgress: { progress in
                        Task { @MainActor in
                            self?.localDownloadStates[audiobook.id] = .downloading(progress: progress)
                        }
                    }
                )
                
                await MainActor.run {
                    if let localURL {
                        self?.localDownloadStates[audiobook.id] = .downloaded(localURL: localURL)
                    }
                    self?.localDownloadTasks.removeValue(forKey: audiobook.id)
                }
            } catch {
                await MainActor.run {
                    if Task.isCancelled {
                        self?.localDownloadStates[audiobook.id] = .notDownloaded
                    } else {
                        self?.localDownloadStates[audiobook.id] = .failed(error: error.localizedDescription)
                        print("[AudiobooksVM] Local download failed for \(audiobook.id): \(error)")
                    }
                    self?.localDownloadTasks.removeValue(forKey: audiobook.id)
                }
            }
        }
    }
    
    /// Cancel an in-progress local download
    func cancelLocalDownload(audiobook: Audiobook) {
        localDownloadTasks[audiobook.id]?.cancel()
        localDownloadTasks.removeValue(forKey: audiobook.id)
        localDownloadStates[audiobook.id] = .notDownloaded
    }
    
    /// Remove a locally downloaded audiobook file
    func removeLocalFile(audiobook: Audiobook) async {
        await service.removeLocalFile(for: audiobook)
        localDownloadStates[audiobook.id] = .notDownloaded
    }
    
    /// Get the local download state for an audiobook
    func localDownloadState(for audiobookId: String) -> LocalDownloadState {
        localDownloadStates[audiobookId] ?? .notDownloaded
    }
    
    /// Formatted local storage usage
    var localStorageUsedFormatted: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        // Synchronous call since it's just file system stats
        let dir = LibroAIService.localAudiobooksDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else {
            return formatter.string(fromByteCount: 0)
        }
        let total = files.reduce(Int64(0)) { sum, url in
            sum + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return formatter.string(fromByteCount: total)
    }
    
    // MARK: - Search
    
    private func setupSearchDebounce() {
        $searchQuery
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Cache Management
    
    func clearData() {
        audiobooks = []
        searchQuery = ""
        hasLoaded = false
        errorMessage = nil
        syncMessage = nil
        
        stopDownloadPolling()
        for (_, task) in localDownloadTasks { task.cancel() }
        localDownloadTasks.removeAll()
        localDownloadStates.removeAll()
        isLibroFmConnected = false
        libroFmEmail = nil
        libroFmBooks = []
        downloadJobs = []
        
        Task {
            await service.clearCache()
        }
    }
}
