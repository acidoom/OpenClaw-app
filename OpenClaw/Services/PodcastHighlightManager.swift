//
//  PodcastHighlightManager.swift
//  OpenClaw
//
//  Orchestrates AI highlight creation for podcast episodes: bookmark capture,
//  transcript fetch, AI summarization, local persistence, and server sync.
//

import Foundation

actor PodcastHighlightManager {
    static let shared = PodcastHighlightManager()
    
    private let store = PodcastHighlightStore.shared
    private let podcastService = PodcastService.shared
    private let chatService = GatewayChatService.shared
    
    private let transcriptWindowSeconds: Double = 300 // 5 minutes
    
    // MARK: - Create Highlight
    
    /// Called when bookmark command fires. Saves locally immediately, then processes AI + syncs.
    /// Returns the highlight ID.
    func createHighlight(
        episodeId: String,
        podcastId: String,
        positionSeconds: Double,
        episodeTitle: String?,
        isTranscribed: Bool
    ) async -> String {
        let highlightId = UUID().uuidString
        let startSeconds = max(0, positionSeconds - transcriptWindowSeconds)
        
        var highlight = PodcastHighlight(
            id: highlightId,
            episodeId: episodeId,
            podcastId: podcastId,
            positionSeconds: positionSeconds,
            startSeconds: startSeconds,
            episodeTitle: episodeTitle,
            highlightText: nil,
            transcriptExcerpt: nil,
            createdAt: Date(),
            syncedAt: nil,
            status: isTranscribed ? .processing : .pending
        )
        
        // Save locally immediately (before any network calls)
        await store.saveHighlight(highlight)
        print("[PodcastHighlight] Created highlight \(highlightId) at \(formatTime(positionSeconds))")
        
        // If not transcribed, save as pending
        guard isTranscribed else {
            print("[PodcastHighlight] Episode not transcribed, saved as pending")
            return highlightId
        }
        
        // Process AI and sync
        highlight = await processHighlightAI(highlight)
        await syncHighlight(highlight)
        
        return highlightId
    }
    
    // MARK: - AI Processing
    
    private func processHighlightAI(_ highlight: PodcastHighlight) async -> PodcastHighlight {
        var updated = highlight
        
        do {
            let transcript = try await podcastService.fetchTranscript(
                episodeId: highlight.episodeId,
                startSeconds: highlight.startSeconds,
                endSeconds: highlight.positionSeconds
            )
            
            updated.transcriptExcerpt = transcript.fullText
            
            guard !transcript.fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                updated.highlightText = "Bookmarked at \(formatTime(highlight.positionSeconds))"
                updated.status = .completed
                await store.saveHighlight(updated)
                return updated
            }
            
            let prompt = """
            You are summarizing a podcast excerpt that the listener just bookmarked. \
            Identify the key topic, insight, or moment in this passage. \
            Be concise: 2-3 sentences maximum. Focus on what makes this passage noteworthy. \
            Do not start with "This passage" or "The excerpt" — just state what happens or what the key idea is.
            
            Transcript excerpt:
            \(transcript.fullText)
            """
            
            let aiResponse = try await chatService.sendMessage(prompt)
            
            updated.highlightText = aiResponse.content
            updated.status = .completed
            
            print("[PodcastHighlight] AI summary generated for \(highlight.id)")
            
        } catch let error as PodcastServiceError {
            if case .httpError(404, _) = error {
                print("[PodcastHighlight] Transcript not available for \(highlight.id), reverting to pending")
                updated.status = .pending
            } else {
                print("[PodcastHighlight] AI processing failed for \(highlight.id): \(error)")
                updated.status = .failed
            }
        } catch {
            print("[PodcastHighlight] AI processing failed for \(highlight.id): \(error)")
            updated.status = .failed
        }
        
        await store.saveHighlight(updated)
        return updated
    }
    
    // MARK: - Server Sync
    
    private func syncHighlight(_ highlight: PodcastHighlight) async {
        guard highlight.status == .completed else { return }
        
        do {
            try await podcastService.saveHighlight(highlight)
            var synced = highlight
            synced.syncedAt = Date()
            await store.saveHighlight(synced)
            print("[PodcastHighlight] Synced highlight \(highlight.id) to server")
        } catch {
            print("[PodcastHighlight] Server sync failed for \(highlight.id): \(error)")
        }
    }
    
    // MARK: - Bulk Operations
    
    func syncPendingHighlights(for episodeId: String) async {
        let unsynced = await store.highlightsNeedingSync(for: episodeId)
        for highlight in unsynced {
            await syncHighlight(highlight)
        }
    }
    
    func retryFailedHighlights(for episodeId: String, isTranscribed: Bool = false) async {
        let candidates = await store.highlightsNeedingAI(for: episodeId)
        for highlight in candidates {
            if highlight.status == .pending && !isTranscribed {
                continue
            }
            var toProcess = highlight
            toProcess.status = .processing
            await store.saveHighlight(toProcess)
            
            let updated = await processHighlightAI(toProcess)
            if updated.status == .completed {
                await syncHighlight(updated)
            }
        }
    }
    
    // MARK: - Read Operations
    
    func loadHighlights(for episodeId: String) async -> [PodcastHighlight] {
        await store.loadHighlights(for: episodeId)
    }
    
    func deleteHighlight(id: String, episodeId: String) async {
        await store.deleteHighlight(id: id, episodeId: episodeId)
        try? await podcastService.deleteHighlight(id: id)
    }
    
    /// Fetch highlights from server and merge with local (server wins for conflicts by ID)
    func fetchAndMergeHighlights(for episodeId: String) async -> [PodcastHighlight] {
        let localHighlights = await store.loadHighlights(for: episodeId)
        
        do {
            let serverHighlights = try await podcastService.fetchHighlights(episodeId: episodeId)
            
            var merged: [String: PodcastHighlight] = [:]
            for h in localHighlights { merged[h.id] = h }
            for h in serverHighlights { merged[h.id] = h }
            
            let result = Array(merged.values).sorted { $0.positionSeconds > $1.positionSeconds }
            
            for h in result {
                await store.saveHighlight(h)
            }
            
            await syncPendingHighlights(for: episodeId)
            
            return result
        } catch {
            print("[PodcastHighlight] Fetch from server failed: \(error)")
            return localHighlights
        }
    }
}
