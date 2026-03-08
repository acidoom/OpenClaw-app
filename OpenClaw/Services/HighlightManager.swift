//
//  HighlightManager.swift
//  OpenClaw
//
//  Orchestrates AI highlight creation: bookmark capture, transcript fetch,
//  AI summarization, local persistence, and server sync.
//

import Foundation

actor HighlightManager {
    static let shared = HighlightManager()
    
    private let store = HighlightStore.shared
    private let libroService = LibroAIService.shared
    private let chatService = GatewayChatService.shared
    
    private let transcriptWindowSeconds: Double = 300 // 5 minutes
    
    // MARK: - Create Highlight
    
    /// Called when bookmark command fires. Saves locally immediately, then processes AI + syncs.
    /// Returns the highlight ID.
    func createHighlight(
        audiobookId: String,
        positionSeconds: Double,
        chapterTitle: String?,
        isTranscribed: Bool
    ) async -> String {
        let highlightId = UUID().uuidString
        let startSeconds = max(0, positionSeconds - transcriptWindowSeconds)
        
        var highlight = AudiobookHighlight(
            id: highlightId,
            audiobookId: audiobookId,
            positionSeconds: positionSeconds,
            startSeconds: startSeconds,
            chapterTitle: chapterTitle,
            highlightText: nil,
            transcriptExcerpt: nil,
            createdAt: Date(),
            syncedAt: nil,
            status: isTranscribed ? .processing : .pending
        )
        
        // Save locally immediately (before any network calls)
        await store.saveHighlight(highlight)
        print("[HighlightManager] Created highlight \(highlightId) at \(formatTime(positionSeconds))")
        
        // If not transcribed, save as pending — AI will run when transcript becomes available
        guard isTranscribed else {
            print("[HighlightManager] Book not transcribed, saved as pending")
            return highlightId
        }
        
        // Process AI and sync
        highlight = await processHighlightAI(highlight)
        await syncHighlight(highlight)
        
        return highlightId
    }
    
    // MARK: - AI Processing
    
    private func processHighlightAI(_ highlight: AudiobookHighlight) async -> AudiobookHighlight {
        var updated = highlight
        
        do {
            // Fetch transcript for the time window
            let transcript = try await libroService.fetchTranscript(
                audiobookId: highlight.audiobookId,
                startSeconds: highlight.startSeconds,
                endSeconds: highlight.positionSeconds
            )
            
            updated.transcriptExcerpt = transcript.fullText
            
            // Handle empty transcript
            guard !transcript.fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                updated.highlightText = "Bookmarked at \(formatTime(highlight.positionSeconds))"
                updated.status = .completed
                await store.saveHighlight(updated)
                return updated
            }
            
            // Send to AI for summarization
            let prompt = """
            You are summarizing an audiobook excerpt that the listener just bookmarked. \
            Identify the key narrative thread, topic, or moment in this passage. \
            Be concise: 2-3 sentences maximum. Focus on what makes this passage noteworthy. \
            Do not start with "This passage" or "The excerpt" — just state what happens or what the key idea is.
            
            Transcript excerpt:
            \(transcript.fullText)
            """
            
            let aiResponse = try await chatService.sendMessage(prompt)
            
            updated.highlightText = aiResponse.content
            updated.status = .completed
            
            print("[HighlightManager] AI summary generated for \(highlight.id)")
            
        } catch let error as LibroAIServiceError {
            // If transcript not available yet (book not transcribed), revert to pending
            if case .httpError(404, _) = error {
                print("[HighlightManager] Transcript not available for \(highlight.id), reverting to pending")
                updated.status = .pending
            } else {
                print("[HighlightManager] AI processing failed for \(highlight.id): \(error)")
                updated.status = .failed
            }
        } catch {
            print("[HighlightManager] AI processing failed for \(highlight.id): \(error)")
            updated.status = .failed
        }
        
        await store.saveHighlight(updated)
        return updated
    }
    
    // MARK: - Server Sync
    
    private func syncHighlight(_ highlight: AudiobookHighlight) async {
        guard highlight.status == .completed else { return }
        
        do {
            try await libroService.saveHighlight(highlight)
            var synced = highlight
            synced.syncedAt = Date()
            await store.saveHighlight(synced)
            print("[HighlightManager] Synced highlight \(highlight.id) to server")
        } catch {
            print("[HighlightManager] Server sync failed for \(highlight.id): \(error)")
        }
    }
    
    // MARK: - Bulk Operations
    
    func syncPendingHighlights(for audiobookId: String) async {
        let unsynced = await store.highlightsNeedingSync(for: audiobookId)
        for highlight in unsynced {
            await syncHighlight(highlight)
        }
    }
    
    func retryFailedHighlights(for audiobookId: String, isTranscribed: Bool = false) async {
        let candidates = await store.highlightsNeedingAI(for: audiobookId)
        for highlight in candidates {
            // Skip .pending highlights unless the book is now transcribed
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
    
    func loadHighlights(for audiobookId: String) async -> [AudiobookHighlight] {
        await store.loadHighlights(for: audiobookId)
    }
    
    func deleteHighlight(id: String, audiobookId: String) async {
        await store.deleteHighlight(id: id, audiobookId: audiobookId)
        try? await libroService.deleteHighlight(id: id)
    }
    
    /// Fetch highlights from server and merge with local (server wins for conflicts by ID)
    func fetchAndMergeHighlights(for audiobookId: String) async -> [AudiobookHighlight] {
        let localHighlights = await store.loadHighlights(for: audiobookId)
        
        do {
            let serverHighlights = try await libroService.fetchHighlights(audiobookId: audiobookId)
            
            // Merge: server highlights override local by ID, local-only highlights are kept
            var merged: [String: AudiobookHighlight] = [:]
            for h in localHighlights { merged[h.id] = h }
            for h in serverHighlights { merged[h.id] = h }
            
            let result = Array(merged.values).sorted { $0.positionSeconds > $1.positionSeconds }
            
            // Persist merged result locally
            for h in result {
                await store.saveHighlight(h)
            }
            
            // Sync any local-only completed highlights to server
            await syncPendingHighlights(for: audiobookId)
            
            return result
        } catch {
            print("[HighlightManager] Fetch from server failed: \(error)")
            return localHighlights
        }
    }
}
