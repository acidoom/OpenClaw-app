//
//  LibroAIService.swift
//  OpenClaw
//
//  API client for the LibroAI audiobook backend
//

import Foundation

// MARK: - Error Types

enum LibroAIServiceError: Error, LocalizedError {
    case notConfigured
    case invalidURL
    case invalidResponse
    case httpError(Int, String?)
    case decodingError(Error)
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "LibroAI not configured. Set OpenClaw endpoint and hook token in Settings."
        case .invalidURL:
            return "Invalid LibroAI URL"
        case .invalidResponse:
            return "Invalid response from LibroAI"
        case .httpError(let code, let message):
            // Try to extract "detail" or "message" from JSON error body
            if let message, let data = message.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let detail = json["detail"] as? String {
                    return detail
                }
                if let msg = json["message"] as? String {
                    return msg
                }
            }
            return "Server error (HTTP \(code)): \(message ?? "Unknown")"
        case .decodingError(let error):
            return "Failed to parse LibroAI response: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Service

actor LibroAIService {
    static let shared = LibroAIService()
    
    private let keychain = KeychainManager.shared
    private let session: URLSession
    
    // Cache
    private var cachedLibrary: [Audiobook] = []
    private var cachedChapters: [String: [AudiobookChapter]] = [:]
    private var lastLibraryFetch: Date?
    private let cacheValidity: TimeInterval = 300 // 5 minutes
    
    private lazy var decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()
    
    private init() {
        let delegate = TailscaleTrustDelegate()
        session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
    }
    
    var isConfigured: Bool {
        keychain.hasLibroAICredentials()
    }
    
    // MARK: - Base Request Builder
    
    private func makeRequest(
        method: String = "GET",
        path: String,
        body: Data? = nil,
        queryItems: [URLQueryItem] = []
    ) async throws -> (Data, HTTPURLResponse) {
        guard let endpoint = try? keychain.get(.openClawEndpoint), !endpoint.isEmpty,
              let token = try? keychain.get(.gatewayHookToken), !token.isEmpty else {
            throw LibroAIServiceError.notConfigured
        }
        
        // Use only the scheme + host + port from the endpoint (strip any path like /todo)
        let base: String
        if let components = URLComponents(string: endpoint),
           let scheme = components.scheme,
           let host = components.host {
            let port = components.port.map { ":\($0)" } ?? ""
            base = "\(scheme)://\(host)\(port)"
        } else {
            base = endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        var urlString = "\(base)\(path)"
        
        if !queryItems.isEmpty {
            var components = URLComponents(string: urlString)
            components?.queryItems = queryItems
            urlString = components?.string ?? urlString
        }
        
        guard let url = URL(string: urlString) else {
            throw LibroAIServiceError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 60
        
        if let body = body {
            request.httpBody = body
        }
        
        print("[LibroAI] \(method) \(urlString)")
        
        // Retry once on connection lost
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError where urlError.code == .networkConnectionLost {
            print("[LibroAI] Connection lost, retrying...")
            try await Task.sleep(nanoseconds: 500_000_000)
            (data, response) = try await session.data(for: request)
        } catch {
            throw LibroAIServiceError.networkError(error)
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LibroAIServiceError.invalidResponse
        }
        
        print("[LibroAI] HTTP \(httpResponse.statusCode)")
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8)
            print("[LibroAI] Error body: \(errorBody ?? "nil")")
            throw LibroAIServiceError.httpError(httpResponse.statusCode, errorBody)
        }
        
        return (data, httpResponse)
    }
    
    // MARK: - Library
    
    func fetchLibrary(forceRefresh: Bool = false) async throws -> [Audiobook] {
        if !forceRefresh,
           let lastFetch = lastLibraryFetch,
           Date().timeIntervalSince(lastFetch) < cacheValidity,
           !cachedLibrary.isEmpty {
            return cachedLibrary
        }
        
        let (data, _) = try await makeRequest(path: "/api/library")
        
        do {
            // Debug: print raw JSON keys for first book
            if let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
               let first = json.first {
                let keys = first.keys.sorted()
                print("[LibroAI] API keys: \(keys)")
                print("[LibroAI] cover_url: \(first["cover_url"] ?? "nil")")
                print("[LibroAI] coverUrl: \(first["coverUrl"] ?? "nil")")
                print("[LibroAI] cover_image: \(first["cover_image"] ?? "nil")")
                print("[LibroAI] cover: \(first["cover"] ?? "nil")")
                print("[LibroAI] image_url: \(first["image_url"] ?? "nil")")
                print("[LibroAI] thumbnail: \(first["thumbnail"] ?? "nil")")
            }
            let books = try decoder.decode([Audiobook].self, from: data)
            cachedLibrary = books
            lastLibraryFetch = Date()
            print("[LibroAI] Fetched \(books.count) audiobooks, first coverUrl: \(books.first?.coverUrl ?? "nil")")
            return books
        } catch {
            print("[LibroAI] Decode error: \(error)")
            if let decodingError = error as? DecodingError {
                printDecodingError(decodingError)
            }
            throw LibroAIServiceError.decodingError(error)
        }
    }
    
    func fetchAudiobook(id: String) async throws -> Audiobook {
        let (data, _) = try await makeRequest(path: "/api/library/\(id)")
        
        do {
            return try decoder.decode(Audiobook.self, from: data)
        } catch {
            throw LibroAIServiceError.decodingError(error)
        }
    }
    
    func syncLibrary() async throws -> LibrarySyncResponse {
        let (data, _) = try await makeRequest(method: "POST", path: "/api/library/sync")
        
        do {
            return try decoder.decode(LibrarySyncResponse.self, from: data)
        } catch {
            throw LibroAIServiceError.decodingError(error)
        }
    }
    
    // MARK: - Chapters
    
    func fetchChapters(audiobookId: String, forceRefresh: Bool = false) async throws -> [AudiobookChapter] {
        if !forceRefresh, let cached = cachedChapters[audiobookId] {
            return cached
        }
        
        let (data, _) = try await makeRequest(path: "/api/chapters/\(audiobookId)")
        
        do {
            let chapters = try decoder.decode([AudiobookChapter].self, from: data)
            cachedChapters[audiobookId] = chapters
            print("[LibroAI] Fetched \(chapters.count) chapters for \(audiobookId)")
            return chapters
        } catch {
            print("[LibroAI] Chapter decode error: \(error)")
            throw LibroAIServiceError.decodingError(error)
        }
    }
    
    // MARK: - Playback State
    
    func fetchPlaybackState(audiobookId: String) async throws -> PlaybackState {
        let (data, _) = try await makeRequest(path: "/api/playback/\(audiobookId)")
        
        do {
            return try decoder.decode(PlaybackState.self, from: data)
        } catch {
            throw LibroAIServiceError.decodingError(error)
        }
    }
    
    func updatePlaybackState(audiobookId: String, position: Double, speed: Double) async throws {
        let body: [String: Any] = [
            "position_seconds": position,
            "playback_speed": speed
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        
        _ = try await makeRequest(
            method: "PUT",
            path: "/api/playback/\(audiobookId)",
            body: bodyData
        )
        
        print("[LibroAI] Synced position \(String(format: "%.1f", position))s for \(audiobookId)")
    }
    
    // MARK: - Streaming URL Builder
    
    /// Returns a full URL for audio streaming. Does NOT make a network call.
    func streamURL(audiobookId: String) throws -> URL {
        guard let endpoint = try? keychain.get(.openClawEndpoint), !endpoint.isEmpty else {
            throw LibroAIServiceError.notConfigured
        }
        
        // Use only the scheme + host + port from the endpoint (strip any path like /todo)
        let base: String
        if let components = URLComponents(string: endpoint),
           let scheme = components.scheme,
           let host = components.host {
            let port = components.port.map { ":\($0)" } ?? ""
            base = "\(scheme)://\(host)\(port)"
        } else {
            base = endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        
        guard let url = URL(string: "\(base)/api/stream/\(audiobookId)") else {
            throw LibroAIServiceError.invalidURL
        }
        
        return url
    }
    
    /// Returns auth headers for AVURLAsset
    func authHeaders() throws -> [String: String] {
        guard let token = try? keychain.get(.gatewayHookToken), !token.isEmpty else {
            throw LibroAIServiceError.notConfigured
        }
        
        return ["Authorization": "Bearer \(token.trimmingCharacters(in: .whitespacesAndNewlines))"]
    }
    
    // MARK: - Cover Images
    
    /// Fetches a cover image with authentication. Returns image data.
    func fetchCoverImageData(coverPath: String) async throws -> Data {
        let (data, _) = try await makeRequest(path: coverPath)
        return data
    }
    
    // MARK: - Libro.fm Integration
    
    func fetchLibroFmStatus() async throws -> LibroFmStatus {
        let (data, _) = try await makeRequest(path: "/api/libro/status")
        do {
            return try decoder.decode(LibroFmStatus.self, from: data)
        } catch {
            throw LibroAIServiceError.decodingError(error)
        }
    }
    
    func libroFmLogin(email: String, password: String) async throws -> LibroFmAuthResponse {
        let body = try JSONEncoder().encode(LibroFmAuthRequest(email: email, password: password))
        let (data, _) = try await makeRequest(method: "POST", path: "/api/libro/auth", body: body)
        do {
            return try decoder.decode(LibroFmAuthResponse.self, from: data)
        } catch {
            throw LibroAIServiceError.decodingError(error)
        }
    }
    
    func libroFmLogout() async throws {
        _ = try await makeRequest(method: "DELETE", path: "/api/libro/auth")
    }
    
    func fetchLibroFmBooks() async throws -> [LibroFmBook] {
        let (data, _) = try await makeRequest(path: "/api/libro/books")
        do {
            return try decoder.decode([LibroFmBook].self, from: data)
        } catch {
            throw LibroAIServiceError.decodingError(error)
        }
    }
    
    func startDownload(libroFmBookId: String) async throws -> DownloadStartResponse {
        let (data, _) = try await makeRequest(method: "POST", path: "/api/libro/download/\(libroFmBookId)")
        do {
            return try decoder.decode(DownloadStartResponse.self, from: data)
        } catch {
            throw LibroAIServiceError.decodingError(error)
        }
    }
    
    func fetchDownloadJobs() async throws -> [DownloadJob] {
        let (data, _) = try await makeRequest(path: "/api/libro/downloads")
        do {
            return try decoder.decode([DownloadJob].self, from: data)
        } catch {
            throw LibroAIServiceError.decodingError(error)
        }
    }
    
    // MARK: - Transcript
    
    func fetchTranscript(
        audiobookId: String,
        startSeconds: Double,
        endSeconds: Double
    ) async throws -> TranscriptResponse {
        let (data, _) = try await makeRequest(
            path: "/api/transcript/\(audiobookId)",
            queryItems: [
                URLQueryItem(name: "start_seconds", value: String(startSeconds)),
                URLQueryItem(name: "end_seconds", value: String(endSeconds))
            ]
        )
        do {
            return try decoder.decode(TranscriptResponse.self, from: data)
        } catch {
            throw LibroAIServiceError.decodingError(error)
        }
    }
    
    // MARK: - Highlights
    
    func fetchHighlights(audiobookId: String) async throws -> [AudiobookHighlight] {
        let (data, _) = try await makeRequest(path: "/api/highlights/\(audiobookId)")
        do {
            return try decoder.decode([AudiobookHighlight].self, from: data)
        } catch {
            throw LibroAIServiceError.decodingError(error)
        }
    }
    
    func saveHighlight(_ highlight: AudiobookHighlight) async throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        let bodyData = try encoder.encode(highlight)
        _ = try await makeRequest(
            method: "POST",
            path: "/api/highlights",
            body: bodyData
        )
        print("[LibroAI] Saved highlight \(highlight.id) to server")
    }
    
    func deleteHighlight(id: String) async throws {
        _ = try await makeRequest(
            method: "DELETE",
            path: "/api/highlights/\(id)"
        )
        print("[LibroAI] Deleted highlight \(id) from server")
    }
    
    // MARK: - Local Audio Download
    
    /// Directory for locally downloaded audiobook files
    static var localAudiobooksDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Audiobooks", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    /// Returns the local file URL for a downloaded audiobook, or nil if not downloaded
    func localFileURL(for audiobook: Audiobook) -> URL? {
        let ext = audiobook.format == .m4b ? "m4b" : "mp3"
        let fileURL = Self.localAudiobooksDirectory.appendingPathComponent("\(audiobook.id).\(ext)")
        return FileManager.default.fileExists(atPath: fileURL.path) ? fileURL : nil
    }
    
    /// Downloads the audiobook audio file to local device storage.
    /// Returns the local file URL. Reports progress via the callback.
    func downloadToDevice(
        audiobook: Audiobook,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        guard let endpoint = try? keychain.get(.openClawEndpoint), !endpoint.isEmpty,
              let token = try? keychain.get(.gatewayHookToken), !token.isEmpty else {
            throw LibroAIServiceError.notConfigured
        }
        
        // Build URL using same logic as makeRequest
        let base: String
        if let components = URLComponents(string: endpoint),
           let scheme = components.scheme,
           let host = components.host {
            let port = components.port.map { ":\($0)" } ?? ""
            base = "\(scheme)://\(host)\(port)"
        } else {
            base = endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        
        let urlString = "\(base)/api/stream/\(audiobook.id)"
        guard let url = URL(string: urlString) else {
            throw LibroAIServiceError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 600 // 10 minutes for large files
        
        let ext = audiobook.format == .m4b ? "m4b" : "mp3"
        let destinationURL = Self.localAudiobooksDirectory.appendingPathComponent("\(audiobook.id).\(ext)")
        
        // Remove existing partial file
        try? FileManager.default.removeItem(at: destinationURL)
        
        print("[LibroAI] Starting local download: GET \(urlString)")
        
        let (asyncBytes, response) = try await session.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LibroAIServiceError.invalidResponse
        }
        
        print("[LibroAI] Download HTTP \(httpResponse.statusCode)")
        
        guard (200...299).contains(httpResponse.statusCode) else {
            // Try to read error body
            var errorData = Data()
            for try await byte in asyncBytes {
                errorData.append(byte)
                if errorData.count > 1024 { break }
            }
            let errorBody = String(data: errorData, encoding: .utf8)
            print("[LibroAI] Download error body: \(errorBody ?? "nil")")
            throw LibroAIServiceError.httpError(httpResponse.statusCode, errorBody)
        }
        
        let totalBytes = httpResponse.expectedContentLength
        var receivedBytes: Int64 = 0
        
        FileManager.default.createFile(atPath: destinationURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destinationURL)
        defer { try? handle.close() }
        
        // Buffer writes in 64KB chunks
        var buffer = Data()
        let bufferSize = 65536
        
        for try await byte in asyncBytes {
            buffer.append(byte)
            receivedBytes += 1
            
            if buffer.count >= bufferSize {
                handle.write(buffer)
                buffer.removeAll(keepingCapacity: true)
                
                if totalBytes > 0 {
                    let progress = Double(receivedBytes) / Double(totalBytes)
                    onProgress(min(progress, 1.0))
                }
            }
        }
        
        // Write remaining buffer
        if !buffer.isEmpty {
            handle.write(buffer)
        }
        
        onProgress(1.0)
        print("[LibroAI] Download complete: \(receivedBytes) bytes → \(destinationURL.lastPathComponent)")
        
        return destinationURL
    }
    
    /// Removes a locally downloaded audiobook file
    func removeLocalFile(for audiobook: Audiobook) {
        let ext = audiobook.format == .m4b ? "m4b" : "mp3"
        let fileURL = Self.localAudiobooksDirectory.appendingPathComponent("\(audiobook.id).\(ext)")
        try? FileManager.default.removeItem(at: fileURL)
        print("[LibroAI] Removed local file for \(audiobook.id)")
    }
    
    /// Total size of locally downloaded audiobooks
    func localStorageUsed() -> Int64 {
        let dir = Self.localAudiobooksDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        return files.reduce(0) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return total + Int64(size)
        }
    }
    
    // MARK: - Cache
    
    func clearCache() {
        cachedLibrary = []
        cachedChapters = [:]
        lastLibraryFetch = nil
    }
    
    // MARK: - Debug Helpers
    
    private func printDecodingError(_ error: DecodingError) {
        switch error {
        case .keyNotFound(let key, let context):
            print("[LibroAI] Missing key '\(key.stringValue)' at \(context.codingPath.map(\.stringValue).joined(separator: "."))")
        case .typeMismatch(let type, let context):
            print("[LibroAI] Type mismatch for \(type) at \(context.codingPath.map(\.stringValue).joined(separator: ".")): \(context.debugDescription)")
        case .valueNotFound(let type, let context):
            print("[LibroAI] Value not found for \(type) at \(context.codingPath.map(\.stringValue).joined(separator: "."))")
        case .dataCorrupted(let context):
            print("[LibroAI] Data corrupted: \(context.debugDescription)")
        @unknown default:
            print("[LibroAI] Unknown decoding error: \(error)")
        }
    }
}
