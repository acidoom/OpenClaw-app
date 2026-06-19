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

            // Extract any books referenced in the passage and match them to Libro.fm
            updated.references = await extractBookReferences(from: transcript.fullText)

            updated.status = .completed

            print("[PodcastHighlight] AI summary generated for \(highlight.id), \(updated.references?.count ?? 0) book reference(s)")
            
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

    // MARK: - Episode-Level Book Scan

    /// In-session cache of books found per episode, keyed by episodeId.
    private var episodeBookCache: [String: [PodcastReference]] = [:]

    /// Scans an episode's full transcript for referenced books and matches them to
    /// Libro.fm. Returns the books found (possibly empty). Cached per session.
    /// Throws if the transcript can't be fetched, so callers can distinguish
    /// "no books" from "couldn't analyze".
    func scanEpisodeForBooks(episodeId: String, durationSeconds: Double?) async throws -> [PodcastReference] {
        if let cached = episodeBookCache[episodeId] {
            return cached
        }

        // Fetch the whole transcript (start at 0, end at duration or a generous cap).
        let endSeconds = (durationSeconds.map { $0 + 60 }) ?? 86_400
        let transcript = try await podcastService.fetchTranscript(
            episodeId: episodeId,
            startSeconds: 0,
            endSeconds: endSeconds
        )

        let text = transcript.fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            episodeBookCache[episodeId] = []
            return []
        }

        let books = await extractBookReferences(from: text) ?? []
        episodeBookCache[episodeId] = books
        print("[PodcastHighlight] Episode \(episodeId) scan found \(books.count) book(s)")
        return books
    }

    // MARK: - Book Reference Extraction

    private struct ExtractedBook: Codable {
        let title: String
        let authors: String?
        let context: String?
    }

    /// Asks the AI to identify any books mentioned in the transcript excerpt, then
    /// enriches each one with a Libro.fm catalog match (cover, price, product link).
    private func extractBookReferences(from transcript: String) async -> [PodcastReference]? {
        let extractPrompt = """
        Identify books that are explicitly mentioned or recommended in the following \
        podcast transcript excerpt. Only include real, published books — not articles, \
        papers, websites, or offhand phrases. For each book provide its title, the \
        author(s) if stated, and a brief one-sentence note on how it came up.

        Respond with ONLY a JSON array (no markdown, no commentary). Use this exact shape:
        [{"title": "Book Title", "authors": "Author Name", "context": "why it was mentioned"}]
        If no books are mentioned, respond with an empty array: []

        Transcript excerpt:
        \(transcript)
        """

        let extracted: [ExtractedBook]
        do {
            let response = try await chatService.sendMessage(extractPrompt)
            extracted = parseExtractedBooks(from: response.content)
        } catch {
            print("[PodcastHighlight] Book extraction failed: \(error)")
            return nil
        }

        guard !extracted.isEmpty else { return nil }

        var references: [PodcastReference] = []
        for book in extracted {
            references.append(await makeReference(for: book))
        }
        return references.isEmpty ? nil : references
    }

    /// Builds a PodcastReference for an extracted book, attaching Libro.fm match data when found.
    private func makeReference(for book: ExtractedBook) async -> PodcastReference {
        let query = [book.title, book.authors].compactMap { $0 }.joined(separator: " ")
        var match: LibroFmSearchResult?
        do {
            let results = try await LibroAIService.shared.searchLibroFm(query: query)
            match = bestMatch(for: book, in: results)
        } catch {
            print("[PodcastHighlight] Libro.fm search failed for \"\(book.title)\": \(error)")
        }

        return PodcastReference(
            type: .book,
            title: match?.title ?? book.title,
            authors: match?.author ?? book.authors,
            url: match?.url ?? libroFmSearchURL(for: query),
            description: book.context,
            coverUrl: match?.coverUrl,
            price: match?.price
        )
    }

    /// Picks the best Libro.fm result, preferring a case-insensitive title match.
    private func bestMatch(for book: ExtractedBook, in results: [LibroFmSearchResult]) -> LibroFmSearchResult? {
        guard !results.isEmpty else { return nil }
        let target = book.title.lowercased()
        if let exact = results.first(where: { $0.title.lowercased() == target }) {
            return exact
        }
        if let partial = results.first(where: {
            $0.title.lowercased().contains(target) || target.contains($0.title.lowercased())
        }) {
            return partial
        }
        return results.first
    }

    /// Fallback Libro.fm search deep link used when no catalog match is found.
    private func libroFmSearchURL(for query: String) -> String? {
        guard var components = URLComponents(string: "https://libro.fm/search") else { return nil }
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        return components.string
    }

    /// Robustly parses a JSON array of books from an AI response that may be wrapped
    /// in markdown code fences or include surrounding prose.
    private func parseExtractedBooks(from content: String) -> [ExtractedBook] {
        var text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip markdown code fences if present
        if text.hasPrefix("```") {
            text = text.replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Isolate the JSON array
        guard let start = text.firstIndex(of: "["),
              let end = text.lastIndex(of: "]"), start <= end else {
            return []
        }
        let jsonString = String(text[start...end])
        guard let data = jsonString.data(using: .utf8) else { return [] }
        do {
            return try JSONDecoder().decode([ExtractedBook].self, from: data)
                .filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        } catch {
            print("[PodcastHighlight] Failed to parse extracted books JSON: \(error)")
            return []
        }
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
