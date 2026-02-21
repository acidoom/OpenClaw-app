//
//  ZoteroService.swift
//  OpenClaw
//
//  Zotero Web API v3 client for fetching library items and notes
//

import Foundation

// MARK: - Zotero Service Errors

enum ZoteroServiceError: Error, LocalizedError {
    case notConfigured
    case invalidURL
    case invalidResponse
    case httpError(Int, String?)
    case decodingError(Error)
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Zotero credentials not configured"
        case .invalidURL:
            return "Invalid Zotero API URL"
        case .invalidResponse:
            return "Invalid response from Zotero API"
        case .httpError(let code, let message):
            if code == 403 {
                return "Access denied - check your API key permissions"
            }
            return "HTTP error \(code): \(message ?? "Unknown error")"
        case .decodingError(let error):
            return "Failed to parse response: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Zotero Service

actor ZoteroService {
    static let shared = ZoteroService()
    
    private let baseURL = "https://api.zotero.org"
    private let apiVersion = "3"
    private let keychain = KeychainManager.shared
    
    private var cachedItems: [ZoteroItem] = []
    private var cachedCollections: [ZoteroCollection] = []
    private var lastFetchTime: Date?
    private let cacheValidityDuration: TimeInterval = 300 // 5 minutes
    
    private init() {}
    
    // MARK: - Configuration
    
    var isConfigured: Bool {
        keychain.hasZoteroCredentials()
    }
    
    private func getCredentials() throws -> (apiKey: String, userId: String) {
        guard isConfigured else {
            throw ZoteroServiceError.notConfigured
        }
        let apiKey = try keychain.getZoteroApiKey()
        let userId = try keychain.getZoteroUserId()
        return (apiKey, userId)
    }
    
    // MARK: - API Requests
    
    private func makeRequest(
        endpoint: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> (Data, HTTPURLResponse) {
        let credentials = try getCredentials()
        
        var urlComponents = URLComponents(string: "\(baseURL)/users/\(credentials.userId)\(endpoint)")
        if !queryItems.isEmpty {
            urlComponents?.queryItems = queryItems
        }
        
        guard let url = urlComponents?.url else {
            throw ZoteroServiceError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(credentials.apiKey, forHTTPHeaderField: "Zotero-API-Key")
        request.setValue(apiVersion, forHTTPHeaderField: "Zotero-API-Version")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        print("[Zotero] Request: \(url.absoluteString)")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ZoteroServiceError.invalidResponse
            }
            
            print("[Zotero] Response: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode >= 400 {
                let message = String(data: data, encoding: .utf8)
                throw ZoteroServiceError.httpError(httpResponse.statusCode, message)
            }
            
            return (data, httpResponse)
        } catch let error as ZoteroServiceError {
            throw error
        } catch {
            throw ZoteroServiceError.networkError(error)
        }
    }
    
    // MARK: - Fetch Items
    
    func fetchItems(
        collectionKey: String? = nil,
        itemType: ZoteroItemType? = nil,
        query: String? = nil,
        sort: ZoteroSortField = .dateModified,
        direction: ZoteroSortDirection = .desc,
        limit: Int = 100,
        start: Int = 0,
        forceRefresh: Bool = false
    ) async throws -> [ZoteroItem] {
        // Check cache validity
        if !forceRefresh,
           collectionKey == nil,
           itemType == nil,
           query == nil,
           !cachedItems.isEmpty,
           let lastFetch = lastFetchTime,
           Date().timeIntervalSince(lastFetch) < cacheValidityDuration {
            print("[Zotero] Returning cached items (\(cachedItems.count))")
            return cachedItems
        }
        
        var endpoint = "/items"
        if let key = collectionKey {
            endpoint = "/collections/\(key)/items"
        }
        
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "sort", value: sort.rawValue),
            URLQueryItem(name: "direction", value: direction.rawValue),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "start", value: String(start))
        ]
        
        if let itemType = itemType, itemType != .unknown {
            queryItems.append(URLQueryItem(name: "itemType", value: itemType.rawValue))
        }
        
        if let query = query, !query.isEmpty {
            queryItems.append(URLQueryItem(name: "q", value: query))
        }
        
        let (data, _) = try await makeRequest(endpoint: endpoint, queryItems: queryItems)
        
        do {
            // Debug: print raw response
            if let jsonString = String(data: data, encoding: .utf8) {
                print("[Zotero] Raw response (first 500 chars): \(String(jsonString.prefix(500)))")
            }
            
            let decoder = JSONDecoder()
            let items = try decoder.decode([ZoteroItem].self, from: data)
            
            // Filter out attachments and notes for main list
            let filteredItems = items.filter {
                $0.data.itemType != .attachment && $0.data.itemType != .note
            }
            
            // Update cache for main library fetch
            if collectionKey == nil && itemType == nil && query == nil {
                cachedItems = filteredItems
                lastFetchTime = Date()
            }
            
            print("[Zotero] Fetched \(filteredItems.count) items")
            return filteredItems
        } catch let decodingError as DecodingError {
            // Detailed decoding error logging
            switch decodingError {
            case .keyNotFound(let key, let context):
                print("[Zotero] Missing key '\(key.stringValue)' at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
            case .typeMismatch(let type, let context):
                print("[Zotero] Type mismatch for \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
            case .valueNotFound(let type, let context):
                print("[Zotero] Value not found for \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
            case .dataCorrupted(let context):
                print("[Zotero] Data corrupted at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
            @unknown default:
                print("[Zotero] Unknown decoding error: \(decodingError)")
            }
            throw ZoteroServiceError.decodingError(decodingError)
        } catch {
            print("[Zotero] Decoding error: \(error)")
            throw ZoteroServiceError.decodingError(error)
        }
    }
    
    // MARK: - Fetch Single Item
    
    func fetchItem(key: String) async throws -> ZoteroItem {
        let (data, _) = try await makeRequest(endpoint: "/items/\(key)")
        
        do {
            let item = try JSONDecoder().decode(ZoteroItem.self, from: data)
            return item
        } catch {
            throw ZoteroServiceError.decodingError(error)
        }
    }
    
    // MARK: - Fetch Child Items (Notes, Attachments)
    
    func fetchChildItems(parentKey: String) async throws -> [ZoteroItem] {
        let queryItems = [
            URLQueryItem(name: "format", value: "json")
        ]
        
        let (data, _) = try await makeRequest(
            endpoint: "/items/\(parentKey)/children",
            queryItems: queryItems
        )
        
        do {
            let items = try JSONDecoder().decode([ZoteroItem].self, from: data)
            print("[Zotero] Fetched \(items.count) child items for \(parentKey)")
            return items
        } catch {
            throw ZoteroServiceError.decodingError(error)
        }
    }
    
    // MARK: - Fetch Notes
    
    func fetchNotes(parentKey: String) async throws -> [ZoteroNote] {
        let children = try await fetchChildItems(parentKey: parentKey)
        
        let notes = children
            .filter { $0.data.itemType == .note }
            .compactMap { item -> ZoteroNote? in
                guard let noteContent = item.data.note else { return nil }
                return ZoteroNote(
                    key: item.key,
                    note: noteContent,
                    dateModified: item.data.dateModified
                )
            }
        
        print("[Zotero] Found \(notes.count) notes for \(parentKey)")
        return notes
    }
    
    // MARK: - Fetch Collections
    
    func fetchCollections(forceRefresh: Bool = false) async throws -> [ZoteroCollection] {
        // Check cache
        if !forceRefresh,
           !cachedCollections.isEmpty,
           let lastFetch = lastFetchTime,
           Date().timeIntervalSince(lastFetch) < cacheValidityDuration {
            return cachedCollections
        }
        
        let queryItems = [
            URLQueryItem(name: "format", value: "json")
        ]
        
        let (data, _) = try await makeRequest(endpoint: "/collections", queryItems: queryItems)
        
        do {
            let collections = try JSONDecoder().decode([ZoteroCollection].self, from: data)
            cachedCollections = collections
            print("[Zotero] Fetched \(collections.count) collections")
            return collections
        } catch {
            throw ZoteroServiceError.decodingError(error)
        }
    }
    
    // MARK: - Search
    
    func search(query: String) async throws -> [ZoteroItem] {
        return try await fetchItems(query: query, forceRefresh: true)
    }
    
    // MARK: - Cache Management
    
    func clearCache() {
        cachedItems = []
        cachedCollections = []
        lastFetchTime = nil
        print("[Zotero] Cache cleared")
    }
    
    // MARK: - Test Connection
    
    func testConnection() async throws -> Bool {
        _ = try await fetchItems(limit: 1, forceRefresh: true)
        return true
    }
    
    // MARK: - Write Operations
    
    /// Create a new item in the library
    func createItem(_ item: ZoteroNewItem) async throws -> ZoteroItem {
        let credentials = try getCredentials()
        
        guard let url = URL(string: "\(baseURL)/users/\(credentials.userId)/items") else {
            throw ZoteroServiceError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(credentials.apiKey, forHTTPHeaderField: "Zotero-API-Key")
        request.setValue(apiVersion, forHTTPHeaderField: "Zotero-API-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(generateWriteToken(), forHTTPHeaderField: "Zotero-Write-Token")
        
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode([item])
        
        print("[Zotero] Creating item: \(item.title ?? "Untitled")")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ZoteroServiceError.invalidResponse
        }
        
        if httpResponse.statusCode >= 400 {
            let message = String(data: data, encoding: .utf8)
            print("[Zotero] Create error: \(message ?? "Unknown")")
            throw ZoteroServiceError.httpError(httpResponse.statusCode, message)
        }
        
        // Parse the response to get the created item
        let createResponse = try JSONDecoder().decode(ZoteroCreateResponse.self, from: data)
        
        guard let createdItem = createResponse.successful.values.first else {
            throw ZoteroServiceError.invalidResponse
        }
        
        clearCache()
        print("[Zotero] Created item: \(createdItem.key)")
        return createdItem
    }
    
    /// Update an existing item
    func updateItem(key: String, version: Int, updates: ZoteroItemUpdates) async throws -> ZoteroItem {
        let credentials = try getCredentials()
        
        guard let url = URL(string: "\(baseURL)/users/\(credentials.userId)/items/\(key)") else {
            throw ZoteroServiceError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue(credentials.apiKey, forHTTPHeaderField: "Zotero-API-Key")
        request.setValue(apiVersion, forHTTPHeaderField: "Zotero-API-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(String(version), forHTTPHeaderField: "If-Unmodified-Since-Version")
        
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(updates)
        
        print("[Zotero] Updating item: \(key)")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ZoteroServiceError.invalidResponse
        }
        
        if httpResponse.statusCode >= 400 {
            let message = String(data: data, encoding: .utf8)
            print("[Zotero] Update error: \(message ?? "Unknown")")
            throw ZoteroServiceError.httpError(httpResponse.statusCode, message)
        }
        
        // Fetch the updated item
        let updatedItem = try await fetchItem(key: key)
        clearCache()
        print("[Zotero] Updated item: \(key)")
        return updatedItem
    }
    
    /// Create a note for an item
    func createNote(parentKey: String, content: String) async throws -> ZoteroItem {
        let noteItem = ZoteroNewItem(
            itemType: "note",
            note: content,
            parentItem: parentKey
        )
        return try await createItem(noteItem)
    }
    
    /// Update an existing note
    func updateNote(key: String, version: Int, content: String) async throws -> ZoteroItem {
        let updates = ZoteroItemUpdates(note: content)
        return try await updateItem(key: key, version: version, updates: updates)
    }
    
    /// Delete an item
    func deleteItem(key: String, version: Int) async throws {
        let credentials = try getCredentials()
        
        guard let url = URL(string: "\(baseURL)/users/\(credentials.userId)/items/\(key)") else {
            throw ZoteroServiceError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(credentials.apiKey, forHTTPHeaderField: "Zotero-API-Key")
        request.setValue(apiVersion, forHTTPHeaderField: "Zotero-API-Version")
        request.setValue(String(version), forHTTPHeaderField: "If-Unmodified-Since-Version")
        
        print("[Zotero] Deleting item: \(key)")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ZoteroServiceError.invalidResponse
        }
        
        if httpResponse.statusCode >= 400 {
            let message = String(data: data, encoding: .utf8)
            print("[Zotero] Delete error: \(message ?? "Unknown")")
            throw ZoteroServiceError.httpError(httpResponse.statusCode, message)
        }
        
        clearCache()
        print("[Zotero] Deleted item: \(key)")
    }
    
    private func generateWriteToken() -> String {
        let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<32).map { _ in characters.randomElement()! })
    }
}

// MARK: - Write Request Types

struct ZoteroNewItem: Encodable {
    let itemType: String
    var title: String?
    var creators: [ZoteroNewCreator]?
    var abstractNote: String?
    var date: String?
    var url: String?
    var DOI: String?
    var publicationTitle: String?
    var volume: String?
    var issue: String?
    var pages: String?
    var publisher: String?
    var place: String?
    var tags: [ZoteroNewTag]?
    var collections: [String]?
    var note: String?
    var parentItem: String?
    
    init(itemType: String, title: String? = nil, creators: [ZoteroNewCreator]? = nil,
         abstractNote: String? = nil, date: String? = nil, url: String? = nil,
         DOI: String? = nil, publicationTitle: String? = nil, volume: String? = nil,
         issue: String? = nil, pages: String? = nil, publisher: String? = nil,
         place: String? = nil, tags: [ZoteroNewTag]? = nil, collections: [String]? = nil,
         note: String? = nil, parentItem: String? = nil) {
        self.itemType = itemType
        self.title = title
        self.creators = creators
        self.abstractNote = abstractNote
        self.date = date
        self.url = url
        self.DOI = DOI
        self.publicationTitle = publicationTitle
        self.volume = volume
        self.issue = issue
        self.pages = pages
        self.publisher = publisher
        self.place = place
        self.tags = tags
        self.collections = collections
        self.note = note
        self.parentItem = parentItem
    }
}

struct ZoteroNewCreator: Encodable {
    let creatorType: String
    var firstName: String?
    var lastName: String?
    var name: String?
}

struct ZoteroNewTag: Encodable {
    let tag: String
}

struct ZoteroItemUpdates: Encodable {
    var title: String?
    var creators: [ZoteroNewCreator]?
    var abstractNote: String?
    var date: String?
    var url: String?
    var DOI: String?
    var publicationTitle: String?
    var volume: String?
    var issue: String?
    var pages: String?
    var publisher: String?
    var place: String?
    var tags: [ZoteroNewTag]?
    var note: String?
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let title = title { try container.encode(title, forKey: .title) }
        if let creators = creators { try container.encode(creators, forKey: .creators) }
        if let abstractNote = abstractNote { try container.encode(abstractNote, forKey: .abstractNote) }
        if let date = date { try container.encode(date, forKey: .date) }
        if let url = url { try container.encode(url, forKey: .url) }
        if let DOI = DOI { try container.encode(DOI, forKey: .DOI) }
        if let publicationTitle = publicationTitle { try container.encode(publicationTitle, forKey: .publicationTitle) }
        if let volume = volume { try container.encode(volume, forKey: .volume) }
        if let issue = issue { try container.encode(issue, forKey: .issue) }
        if let pages = pages { try container.encode(pages, forKey: .pages) }
        if let publisher = publisher { try container.encode(publisher, forKey: .publisher) }
        if let place = place { try container.encode(place, forKey: .place) }
        if let tags = tags { try container.encode(tags, forKey: .tags) }
        if let note = note { try container.encode(note, forKey: .note) }
    }
    
    private enum CodingKeys: String, CodingKey {
        case title, creators, abstractNote, date, url, DOI, publicationTitle
        case volume, issue, pages, publisher, place, tags, note
    }
}

struct ZoteroCreateResponse: Decodable {
    let successful: [String: ZoteroItem]
    let success: [String: String]?
    let unchanged: [String: String]?
    let failed: [String: ZoteroFailedItem]?
}

struct ZoteroFailedItem: Decodable {
    let key: String?
    let code: Int
    let message: String
}
