//
//  WidgetDataManager.swift
//  OpenClawWidgets
//
//  Bridge between the main app and widget extension via shared App Group UserDefaults.
//  IMPORTANT: Keep in sync with OpenClaw/Services/WidgetDataManager.swift
//

import Foundation
import WidgetKit

final class WidgetDataManager {
    static let shared = WidgetDataManager()
    
    private let defaults: UserDefaults?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    private init() {
        defaults = UserDefaults(suiteName: WidgetDataKey.suiteName)
    }
    
    // MARK: - Cover Image (shared file in App Group container)
    
    private var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetDataKey.suiteName)
    }
    
    func saveCoverImage(_ imageData: Data, for audiobookId: String) {
        guard let container = containerURL else { return }
        let filename = "widget_cover_\(audiobookId).jpg"
        let fileURL = container.appendingPathComponent(filename)
        try? imageData.write(to: fileURL)
        // Store filename only — absolute paths differ between app and widget processes
        defaults?.set(filename, forKey: WidgetDataKey.coverImagePath)
    }
    
    func loadCoverImage() -> Data? {
        guard let filename = defaults?.string(forKey: WidgetDataKey.coverImagePath),
              let container = containerURL else { return nil }
        let fileURL = container.appendingPathComponent(filename)
        return try? Data(contentsOf: fileURL)
    }
    
    func clearOldCoverImages(except currentId: String?) {
        guard let container = containerURL else { return }
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: container.path) else { return }
        let keepSuffix = currentId.map { "widget_cover_\($0).jpg" }
        for file in files where file.hasPrefix("widget_cover_") && file != keepSuffix {
            try? fm.removeItem(at: container.appendingPathComponent(file))
        }
    }
    
    // MARK: - Write (called from main app)
    
    func updateTodos(_ items: [WidgetTodoItem]) {
        guard let data = try? encoder.encode(items) else { return }
        defaults?.set(data, forKey: WidgetDataKey.todos)
        defaults?.set(Date().timeIntervalSince1970, forKey: WidgetDataKey.lastUpdated)
    }
    
    func updateNowPlaying(_ nowPlaying: WidgetNowPlaying?) {
        if let nowPlaying = nowPlaying {
            guard let data = try? encoder.encode(nowPlaying) else { return }
            defaults?.set(data, forKey: WidgetDataKey.nowPlaying)
        } else {
            defaults?.removeObject(forKey: WidgetDataKey.nowPlaying)
        }
        defaults?.set(Date().timeIntervalSince1970, forKey: WidgetDataKey.lastUpdated)
    }
    
    func updateRecentHighlights(_ highlights: [WidgetHighlight]) {
        guard let data = try? encoder.encode(highlights) else { return }
        defaults?.set(data, forKey: WidgetDataKey.recentHighlights)
        defaults?.set(Date().timeIntervalSince1970, forKey: WidgetDataKey.lastUpdated)
    }
    
    func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    // MARK: - Read (called from widget extension)
    
    func loadTodos() -> [WidgetTodoItem] {
        guard let data = defaults?.data(forKey: WidgetDataKey.todos),
              let items = try? decoder.decode([WidgetTodoItem].self, from: data) else {
            return []
        }
        return items
    }
    
    func loadNowPlaying() -> WidgetNowPlaying? {
        guard let data = defaults?.data(forKey: WidgetDataKey.nowPlaying),
              let nowPlaying = try? decoder.decode(WidgetNowPlaying.self, from: data) else {
            return nil
        }
        return nowPlaying
    }
    
    func loadRecentHighlights() -> [WidgetHighlight] {
        guard let data = defaults?.data(forKey: WidgetDataKey.recentHighlights),
              let highlights = try? decoder.decode([WidgetHighlight].self, from: data) else {
            return []
        }
        return highlights
    }
    
    func loadDashboardData() -> WidgetDashboardData {
        let lastUpdatedTimestamp = defaults?.double(forKey: WidgetDataKey.lastUpdated)
        let lastUpdated = lastUpdatedTimestamp.map { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil } ?? nil
        
        return WidgetDashboardData(
            todos: loadTodos(),
            nowPlaying: loadNowPlaying(),
            recentHighlights: loadRecentHighlights(),
            lastUpdated: lastUpdated
        )
    }
}
