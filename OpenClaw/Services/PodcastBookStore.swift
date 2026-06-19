//
//  PodcastBookStore.swift
//  OpenClaw
//
//  Local JSON persistence for books discovered across podcast transcripts.
//  Aggregates book references from episode-level scans and per-highlight extraction
//  so they can be browsed in one place (e.g. the "Books Mentioned" digest).
//

import Foundation

actor PodcastBookStore {
    static let shared = PodcastBookStore()

    private let fileManager = FileManager.default

    private var directory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("PodcastBooks", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var fileURL: URL { directory.appendingPathComponent("collected.json") }
    private var scannedURL: URL { directory.appendingPathComponent("scanned.json") }

    private var cache: [CollectedPodcastBook]?
    private var scannedCache: Set<String>?

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

    func loadAll() -> [CollectedPodcastBook] {
        if let cache { return cache }
        guard let data = try? Data(contentsOf: fileURL),
              let books = try? decoder.decode([CollectedPodcastBook].self, from: data) else {
            cache = []
            return []
        }
        cache = books
        return books
    }

    /// Books collected within the last `days` days, de-duplicated by book identity
    /// (a book mentioned in multiple episodes appears once, keyed to its most recent
    /// mention), most recent first.
    func recentBooks(withinDays days: Int) -> [CollectedPodcastBook] {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        let recent = loadAll().filter { $0.collectedAt >= cutoff }

        // Keep the most recent collection per unique book.
        var byBook: [String: CollectedPodcastBook] = [:]
        for book in recent {
            let key = book.reference.id
            if let existing = byBook[key], existing.collectedAt >= book.collectedAt {
                continue
            }
            byBook[key] = book
        }
        return byBook.values.sorted { $0.collectedAt > $1.collectedAt }
    }

    // MARK: - Scanned episodes

    /// Episode IDs that have already been scanned for books (regardless of whether any
    /// were found), so backfill doesn't re-run the AI on them.
    func scannedEpisodeIds() -> Set<String> {
        if let scannedCache { return scannedCache }
        guard let data = try? Data(contentsOf: scannedURL),
              let ids = try? decoder.decode([String].self, from: data) else {
            scannedCache = []
            return []
        }
        let set = Set(ids)
        scannedCache = set
        return set
    }

    func markScanned(_ episodeId: String) {
        var set = scannedEpisodeIds()
        guard set.insert(episodeId).inserted else { return }
        scannedCache = set
        if let data = try? encoder.encode(Array(set)) {
            try? data.write(to: scannedURL, options: .atomic)
        }
    }

    // MARK: - Write

    /// Upserts the given books for an episode. Existing entries (same episode + book)
    /// keep their original `collectedAt` so the digest reflects first discovery.
    func add(
        references: [PodcastReference],
        episodeId: String,
        episodeTitle: String?,
        podcastId: String?,
        podcastTitle: String?,
        collectedAt: Date
    ) {
        let books = references
            .filter { $0.type == .book }
            .map {
                CollectedPodcastBook(
                    reference: $0,
                    episodeId: episodeId,
                    episodeTitle: episodeTitle,
                    podcastId: podcastId,
                    podcastTitle: podcastTitle,
                    collectedAt: collectedAt
                )
            }
        guard !books.isEmpty else { return }

        var all = loadAll()
        for book in books {
            if let index = all.firstIndex(where: { $0.id == book.id }) {
                // Preserve the earliest collectedAt, refresh the reference data.
                let earliest = min(all[index].collectedAt, book.collectedAt)
                all[index] = CollectedPodcastBook(
                    reference: book.reference,
                    episodeId: book.episodeId,
                    episodeTitle: book.episodeTitle,
                    podcastId: book.podcastId,
                    podcastTitle: book.podcastTitle,
                    collectedAt: earliest
                )
            } else {
                all.append(book)
            }
        }
        cache = all
        persist(all)
    }

    // MARK: - Persistence

    private func persist(_ books: [CollectedPodcastBook]) {
        if let data = try? encoder.encode(books) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
