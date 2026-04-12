//
//  PaperAudioViewModel.swift
//  OpenClaw
//
//  ViewModel for managing paper-to-audiobook generation and playback
//

import Foundation
import Combine

@MainActor
final class PaperAudioViewModel: ObservableObject {
    
    // MARK: - Published State
    
    @Published var jobs: [PaperAudioJob] = []
    @Published var isLoading = false
    @Published var isGenerating = false
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var activeManifest: PaperAudioManifest?
    
    // Configuration state (for the generation sheet)
    @Published var selectedMode: PaperListeningMode = .runner
    @Published var skipEquations = true
    @Published var skipTables = true
    @Published var skipReferences = true
    @Published var summarizeFigures = true
    @Published var explainJargon = true
    @Published var selectedVoiceId = "default"
    
    // MARK: - Computed Properties
    
    var activeJobs: [PaperAudioJob] {
        jobs.filter { $0.status.isActive }
    }
    
    var completedJobs: [PaperAudioJob] {
        jobs.filter { $0.status == .completed }
    }
    
    var failedJobs: [PaperAudioJob] {
        jobs.filter { $0.status == .failed }
    }
    
    var hasActiveJobs: Bool {
        !activeJobs.isEmpty
    }
    
    @Published var isConfigured = false
    
    func checkConfiguration() {
        isConfigured = KeychainManager.shared.hasLibroAICredentials()
    }
    
    // MARK: - Private
    
    private let service = PaperAudioService.shared
    private var pollTask: Task<Void, Never>?
    
    // MARK: - Generation
    
    /// Start audio generation for a Zotero paper
    func startGeneration(from item: ZoteroItem) async {
        isGenerating = true
        errorMessage = nil
        
        let config = PaperAudioConfig(
            zoteroItemKey: item.key,
            paperTitle: item.data.displayTitle,
            mode: selectedMode,
            skipEquations: skipEquations,
            skipTables: skipTables,
            skipReferences: skipReferences,
            summarizeFigures: summarizeFigures,
            explainJargon: explainJargon,
            voiceId: selectedVoiceId
        )
        
        do {
            let job = try await service.startGeneration(config: config)
            // Add to local list immediately
            if !jobs.contains(where: { $0.id == job.id }) {
                jobs.insert(job, at: 0)
            }
            // Start polling for updates
            startPolling()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            print("[PaperAudioVM] Generation error: \(error)")
        }
        
        isGenerating = false
    }
    
    // MARK: - Loading
    
    /// Load all jobs from the server
    func loadJobs() async {
        print("[PaperAudioVM] loadJobs() called")
        isLoading = true
        errorMessage = nil
        
        do {
            jobs = try await service.fetchJobs(forceRefresh: true)
            print("[PaperAudioVM] Loaded \(jobs.count) jobs: \(jobs.map { "\($0.id): \($0.status.rawValue)" }.joined(separator: ", "))")
            // Start polling if there are active jobs
            if hasActiveJobs {
                startPolling()
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            print("[PaperAudioVM] Failed to load jobs: \(error)")
        }
        
        isLoading = false
    }
    
    /// Load jobs for a specific Zotero item
    func loadJobs(forZoteroKey: String) async -> [PaperAudioJob] {
        do {
            let allJobs = try await service.fetchJobs(forceRefresh: true)
            jobs = allJobs
            return allJobs.filter { $0.zoteroItemKey == forZoteroKey }
        } catch {
            print("[PaperAudioVM] Failed to load jobs for key \(forZoteroKey): \(error)")
            return []
        }
    }
    
    /// Load the playback manifest for a completed job
    func loadManifest(for job: PaperAudioJob) async -> PaperAudioManifest? {
        guard job.status == .completed else { return nil }
        
        do {
            let manifest = try await service.fetchManifest(jobId: job.id)
            activeManifest = manifest
            return manifest
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            print("[PaperAudioVM] Failed to load manifest: \(error)")
            return nil
        }
    }
    
    // MARK: - Job Management
    
    func cancelJob(_ job: PaperAudioJob) async {
        do {
            try await service.cancelJob(jobId: job.id)
            // Refresh to get updated status
            await loadJobs()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
    
    func deleteJob(_ job: PaperAudioJob) async {
        do {
            try await service.deleteJob(jobId: job.id)
            jobs.removeAll { $0.id == job.id }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
    
    /// Retry a failed job by starting a new generation with the same parameters
    func retryJob(_ job: PaperAudioJob) async {
        isGenerating = true
        errorMessage = nil
        
        let config = PaperAudioConfig(
            zoteroItemKey: job.zoteroItemKey,
            paperTitle: job.paperTitle,
            mode: job.mode,
            skipEquations: skipEquations,
            skipTables: skipTables,
            skipReferences: skipReferences,
            summarizeFigures: summarizeFigures,
            explainJargon: explainJargon,
            voiceId: selectedVoiceId
        )
        
        do {
            let newJob = try await service.startGeneration(config: config)
            // Remove old failed job, add new one
            jobs.removeAll { $0.id == job.id }
            jobs.insert(newJob, at: 0)
            startPolling()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        
        isGenerating = false
    }
    
    // MARK: - Polling
    
    func startPolling() {
        // Don't start duplicate polling
        guard pollTask == nil else { return }
        
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                guard !Task.isCancelled else { break }
                
                do {
                    let updatedJobs = try await service.fetchJobs(forceRefresh: true)
                    self.jobs = updatedJobs
                    
                    // Stop polling if no active jobs
                    if !self.hasActiveJobs {
                        self.stopPolling()
                        break
                    }
                } catch {
                    print("[PaperAudioVM] Polling error: \(error)")
                }
            }
        }
    }
    
    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }
    
    // MARK: - Configuration Defaults
    
    /// Apply recommended defaults for the selected mode
    func applyDefaults(for mode: PaperListeningMode) {
        selectedMode = mode
        
        switch mode {
        case .summary:
            skipEquations = true
            skipTables = true
            skipReferences = true
            summarizeFigures = true
            explainJargon = true
        case .runner:
            skipEquations = true
            skipTables = true
            skipReferences = true
            summarizeFigures = true
            explainJargon = true
        case .deepDive:
            skipEquations = false
            skipTables = false
            skipReferences = true
            summarizeFigures = false
            explainJargon = true
        }
    }
    
    deinit {
        pollTask?.cancel()
    }
}
