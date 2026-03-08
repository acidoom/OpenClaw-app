//
//  HighlightStore.swift
//  OpenClaw
//
//  Local JSON-based persistence for audiobook AI highlights
//

import Foundation

actor HighlightStore {
    static let shared = HighlightStore()
    
    private let fileManager = FileManager.default
    
    private var highlightsDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Highlights", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    private func fileURL(for audiobookId: String) -> URL {
        highlightsDirectory.appendingPathComponent("\(audiobookId).json")
    }
    
    // In-memory cache per audiobook
    private var cache: [String: [AudiobookHighlight]] = [:]
    
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
    
    func loadHighlights(for audiobookId: String) -> [AudiobookHighlight] {
        if let cached = cache[audiobookId] { return cached }
        
        let url = fileURL(for: audiobookId)
        guard let data = try? Data(contentsOf: url),
              let highlights = try? decoder.decode([AudiobookHighlight].self, from: data) else {
            return []
        }
        cache[audiobookId] = highlights
        return highlights
    }
    
    // MARK: - Write
    
    func saveHighlight(_ highlight: AudiobookHighlight) {
        var highlights = loadHighlights(for: highlight.audiobookId)
        
        // Upsert: replace if exists, append if new
        if let index = highlights.firstIndex(where: { $0.id == highlight.id }) {
            highlights[index] = highlight
        } else {
            highlights.append(highlight)
        }
        
        // Sort by position descending (most recent bookmark first)
        highlights.sort { $0.positionSeconds > $1.positionSeconds }
        
        cache[highlight.audiobookId] = highlights
        persist(highlights, for: highlight.audiobookId)
    }
    
    // MARK: - Delete
    
    func deleteHighlight(id: String, audiobookId: String) {
        var highlights = loadHighlights(for: audiobookId)
        highlights.removeAll { $0.id == id }
        cache[audiobookId] = highlights
        persist(highlights, for: audiobookId)
    }
    
    // MARK: - Queries
    
    func highlightsNeedingSync(for audiobookId: String) -> [AudiobookHighlight] {
        loadHighlights(for: audiobookId).filter { $0.syncedAt == nil && $0.status == .completed }
    }
    
    func highlightsNeedingAI(for audiobookId: String) -> [AudiobookHighlight] {
        loadHighlights(for: audiobookId).filter {
            $0.status == .pending || $0.status == .failed
        }
    }
    
    // MARK: - Persistence
    
    private func persist(_ highlights: [AudiobookHighlight], for audiobookId: String) {
        let url = fileURL(for: audiobookId)
        if let data = try? encoder.encode(highlights) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
