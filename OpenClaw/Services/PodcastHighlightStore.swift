//
//  PodcastHighlightStore.swift
//  OpenClaw
//
//  Local JSON-based persistence for podcast AI highlights
//

import Foundation

actor PodcastHighlightStore {
    static let shared = PodcastHighlightStore()
    
    private let fileManager = FileManager.default
    
    private var highlightsDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("PodcastHighlights", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    private func fileURL(for episodeId: String) -> URL {
        highlightsDirectory.appendingPathComponent("\(episodeId).json")
    }
    
    // In-memory cache per episode
    private var cache: [String: [PodcastHighlight]] = [:]
    
    private lazy var encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = .prettyPrinted
        return e
    }()
    
    private lazy var decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
    
    // MARK: - Read
    
    func loadHighlights(for episodeId: String) -> [PodcastHighlight] {
        if let cached = cache[episodeId] { return cached }
        
        let url = fileURL(for: episodeId)
        guard let data = try? Data(contentsOf: url),
              let highlights = try? decoder.decode([PodcastHighlight].self, from: data) else {
            return []
        }
        cache[episodeId] = highlights
        return highlights
    }
    
    // MARK: - Write
    
    func saveHighlight(_ highlight: PodcastHighlight) {
        var highlights = loadHighlights(for: highlight.episodeId)
        
        // Upsert: replace if exists, append if new
        if let index = highlights.firstIndex(where: { $0.id == highlight.id }) {
            highlights[index] = highlight
        } else {
            highlights.append(highlight)
        }
        
        // Sort by position descending (most recent bookmark first)
        highlights.sort { $0.positionSeconds > $1.positionSeconds }
        
        cache[highlight.episodeId] = highlights
        persist(highlights, for: highlight.episodeId)
    }
    
    // MARK: - Delete
    
    func deleteHighlight(id: String, episodeId: String) {
        var highlights = loadHighlights(for: episodeId)
        highlights.removeAll { $0.id == id }
        cache[episodeId] = highlights
        persist(highlights, for: episodeId)
    }
    
    // MARK: - Queries
    
    func highlightsNeedingSync(for episodeId: String) -> [PodcastHighlight] {
        loadHighlights(for: episodeId).filter { $0.syncedAt == nil && $0.status == .completed }
    }
    
    func highlightsNeedingAI(for episodeId: String) -> [PodcastHighlight] {
        loadHighlights(for: episodeId).filter {
            $0.status == .pending || $0.status == .failed
        }
    }
    
    // MARK: - Persistence
    
    private func persist(_ highlights: [PodcastHighlight], for episodeId: String) {
        let url = fileURL(for: episodeId)
        if let data = try? encoder.encode(highlights) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
