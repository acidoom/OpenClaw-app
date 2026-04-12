//
//  PaperAudioService.swift
//  OpenClaw
//
//  API client for the Paper-to-Audiobook backend pipeline
//

import Foundation

actor PaperAudioService {
    static let shared = PaperAudioService()
    
    private let keychain = KeychainManager.shared
    private let session: URLSession
    
    // Cache
    private var cachedJobs: [PaperAudioJob] = []
    private var cachedManifests: [String: PaperAudioManifest] = [:]
    private var lastJobsFetch: Date?
    private let cacheValidity: TimeInterval = 30 // 30 seconds (jobs change frequently)
    
    private lazy var decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            
            // Try unix timestamp first (number)
            if let timestamp = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: timestamp)
            }
            
            let dateString = try container.decode(String.self)
            
            // Try ISO 8601 with fractional seconds
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = isoFormatter.date(from: dateString) {
                return date
            }
            
            // Try ISO 8601 without fractional seconds
            isoFormatter.formatOptions = [.withInternetDateTime]
            if let date = isoFormatter.date(from: dateString) {
                return date
            }
            
            // Try without timezone (append Z) — handles both "...T10:00:00" and "...T10:00:00.123456"
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = isoFormatter.date(from: dateString + "Z") {
                return date
            }
            isoFormatter.formatOptions = [.withInternetDateTime]
            if let date = isoFormatter.date(from: dateString + "Z") {
                return date
            }
            
            // Try SQLite-style "YYYY-MM-DD HH:MM:SS"
            let sqlFormatter = DateFormatter()
            sqlFormatter.locale = Locale(identifier: "en_US_POSIX")
            sqlFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            sqlFormatter.timeZone = TimeZone(identifier: "UTC")
            if let date = sqlFormatter.date(from: dateString) {
                return date
            }
            
            // Try SQLite with fractional seconds
            sqlFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSS"
            if let date = sqlFormatter.date(from: dateString) {
                return date
            }
            
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Cannot decode date from: \(dateString)")
            )
        }
        return d
    }()
    
    private lazy var encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()
    
    private init() {
        let delegate = TailscaleTrustDelegate()
        session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
    }
    
    nonisolated var isConfigured: Bool {
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
            throw PaperAudioServiceError.notConfigured
        }
        
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
            throw PaperAudioServiceError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 120
        
        if let body = body {
            request.httpBody = body
        }
        
        print("[PaperAudio] \(method) \(urlString)")
        
        // Retry once on connection lost
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError where urlError.code == .networkConnectionLost {
            print("[PaperAudio] Connection lost, retrying...")
            try await Task.sleep(nanoseconds: 500_000_000)
            (data, response) = try await session.data(for: request)
        } catch {
            throw PaperAudioServiceError.networkError(error)
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PaperAudioServiceError.invalidResponse
        }
        
        print("[PaperAudio] HTTP \(httpResponse.statusCode)")
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8)
            print("[PaperAudio] Error body: \(errorBody ?? "nil")")
            throw PaperAudioServiceError.httpError(httpResponse.statusCode, errorBody)
        }
        
        return (data, httpResponse)
    }
    
    // MARK: - Generate
    
    /// Start a paper audio generation job
    func startGeneration(config: PaperAudioConfig) async throws -> PaperAudioJob {
        let bodyData = try encoder.encode(config)
        let (data, _) = try await makeRequest(method: "POST", path: "/api/paper-audio/generate", body: bodyData)
        
        let rawString = String(data: data, encoding: .utf8) ?? "<non-utf8>"
        print("[PaperAudio] Generate response: \(rawString.prefix(1000))")
        
        // Try decoding directly as a PaperAudioJob
        if let job = try? decoder.decode(PaperAudioJob.self, from: data) {
            lastJobsFetch = nil
            print("[PaperAudio] Started generation job \(job.id) for '\(job.paperTitle)' in \(job.mode.displayName) mode")
            return job
        }
        
        // Try unwrapping from common wrappers: {"job": {...}}, {"data": {...}}
        if let wrapper = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let possibleKeys = ["job", "data", "result"]
            for key in possibleKeys {
                if let jobData = wrapper[key] {
                    let reEncoded = try JSONSerialization.data(withJSONObject: jobData)
                    if let job = try? decoder.decode(PaperAudioJob.self, from: reEncoded) {
                        lastJobsFetch = nil
                        print("[PaperAudio] Started generation job \(job.id) (unwrapped from '\(key)')")
                        return job
                    }
                }
            }
            let keys = wrapper.keys.sorted().joined(separator: ", ")
            throw PaperAudioServiceError.generationFailed("Response keys: [\(keys)]. Preview: \(String(rawString.prefix(500)))")
        }
        
        throw PaperAudioServiceError.generationFailed("Unexpected generate response: \(String(rawString.prefix(500)))")
    }
    
    // MARK: - Jobs
    
    /// Fetch all paper audio jobs
    func fetchJobs(forceRefresh: Bool = false) async throws -> [PaperAudioJob] {
        if !forceRefresh,
           let lastFetch = lastJobsFetch,
           Date().timeIntervalSince(lastFetch) < cacheValidity,
           !cachedJobs.isEmpty {
            return cachedJobs
        }
        
        let (data, _) = try await makeRequest(path: "/api/paper-audio/jobs")
        
        let rawString = String(data: data, encoding: .utf8) ?? "<non-utf8>"
        print("[PaperAudio] Raw jobs response (\(data.count) bytes): \(rawString.prefix(2000))")
        
        // Decode as bare array — use do/catch to get the actual error
        do {
            let jobs = try decoder.decode([PaperAudioJob].self, from: data)
            cachedJobs = jobs
            lastJobsFetch = Date()
            print("[PaperAudio] Fetched \(jobs.count) jobs")
            return jobs
        } catch let decodingError as DecodingError {
            // Build a detailed error message showing exactly what field failed
            let detail: String
            switch decodingError {
            case .keyNotFound(let key, let context):
                let path = context.codingPath.map(\.stringValue).joined(separator: ".")
                detail = "Missing field '\(key.stringValue)' at \(path.isEmpty ? "root" : path)"
            case .typeMismatch(let type, let context):
                let path = context.codingPath.map(\.stringValue).joined(separator: ".")
                detail = "Wrong type for '\(path)' — expected \(type). \(context.debugDescription)"
            case .valueNotFound(let type, let context):
                let path = context.codingPath.map(\.stringValue).joined(separator: ".")
                detail = "Null value at '\(path)' — expected \(type)"
            case .dataCorrupted(let context):
                let path = context.codingPath.map(\.stringValue).joined(separator: ".")
                detail = "Corrupted data at '\(path.isEmpty ? "root" : path)': \(context.debugDescription)"
            @unknown default:
                detail = decodingError.localizedDescription
            }
            
            // Also try to print what keys the first object actually has
            var keysInfo = ""
            if let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
               let first = json.first {
                keysInfo = " Server fields: [\(first.keys.sorted().joined(separator: ", "))]"
            }
            
            print("[PaperAudio] DECODE ERROR: \(detail)\(keysInfo)")
            throw PaperAudioServiceError.generationFailed("\(detail)\(keysInfo)")
        }
    }
    
    /// Fetch a single job's status
    func fetchJob(jobId: String) async throws -> PaperAudioJob {
        let (data, _) = try await makeRequest(path: "/api/paper-audio/jobs/\(jobId)")
        
        do {
            return try decoder.decode(PaperAudioJob.self, from: data)
        } catch {
            throw PaperAudioServiceError.decodingError(error)
        }
    }
    
    /// Fetch jobs for a specific Zotero item
    func fetchJobs(forZoteroKey: String) async throws -> [PaperAudioJob] {
        let allJobs = try await fetchJobs()
        return allJobs.filter { $0.zoteroItemKey == forZoteroKey }
    }
    
    // MARK: - Manifest
    
    /// Fetch the playback manifest for a completed job
    func fetchManifest(jobId: String) async throws -> PaperAudioManifest {
        if let cached = cachedManifests[jobId] {
            return cached
        }
        
        let (data, _) = try await makeRequest(path: "/api/paper-audio/\(jobId)/manifest")
        
        do {
            let manifest = try decoder.decode(PaperAudioManifest.self, from: data)
            cachedManifests[jobId] = manifest
            print("[PaperAudio] Fetched manifest for \(jobId): \(manifest.sections.count) sections, \(manifest.formattedDuration)")
            return manifest
        } catch {
            throw PaperAudioServiceError.decodingError(error)
        }
    }
    
    // MARK: - Streaming
    
    /// Returns a URL for audio streaming. Does NOT make a network call.
    nonisolated func streamURL(jobId: String) throws -> URL {
        guard let endpoint = try? keychain.get(.openClawEndpoint), !endpoint.isEmpty else {
            throw PaperAudioServiceError.notConfigured
        }
        
        let base: String
        if let components = URLComponents(string: endpoint),
           let scheme = components.scheme,
           let host = components.host {
            let port = components.port.map { ":\($0)" } ?? ""
            base = "\(scheme)://\(host)\(port)"
        } else {
            base = endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        
        guard let url = URL(string: "\(base)/api/paper-audio/\(jobId)/stream") else {
            throw PaperAudioServiceError.invalidURL
        }
        
        return url
    }
    
    /// Returns auth headers for AVURLAsset
    nonisolated func authHeaders() throws -> [String: String] {
        guard let token = try? keychain.get(.gatewayHookToken), !token.isEmpty else {
            throw PaperAudioServiceError.notConfigured
        }
        
        return ["Authorization": "Bearer \(token.trimmingCharacters(in: .whitespacesAndNewlines))"]
    }
    
    // MARK: - Job Management
    
    /// Cancel an in-progress job
    func cancelJob(jobId: String) async throws {
        _ = try await makeRequest(method: "POST", path: "/api/paper-audio/jobs/\(jobId)/cancel")
        lastJobsFetch = nil
        print("[PaperAudio] Cancelled job \(jobId)")
    }
    
    /// Delete a job and its audio
    func deleteJob(jobId: String) async throws {
        _ = try await makeRequest(method: "DELETE", path: "/api/paper-audio/jobs/\(jobId)")
        cachedManifests.removeValue(forKey: jobId)
        lastJobsFetch = nil
        print("[PaperAudio] Deleted job \(jobId)")
    }
    
    // MARK: - Cache
    
    func clearCache() {
        cachedJobs = []
        cachedManifests = [:]
        lastJobsFetch = nil
    }
}
