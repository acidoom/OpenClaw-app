//
//  TodoService.swift
//  OpenClaw
//
//  Service for syncing TODO list with Gateway TODO sync server
//

import Foundation

enum TodoServiceError: Error, LocalizedError {
    case noEndpointConfigured
    case networkError(Error)
    case invalidResponse
    case serverError(Int, String?)
    
    var errorDescription: String? {
        switch self {
        case .noEndpointConfigured:
            return "No TODO sync endpoint configured"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message ?? "Unknown")"
        }
    }
}

// MARK: - URLSession Delegate for Self-Signed Certificates

final class InsecureURLSessionDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // Accept self-signed certificates for local development
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let serverTrust = challenge.protectionSpace.serverTrust {
            let credential = URLCredential(trust: serverTrust)
            completionHandler(.useCredential, credential)
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

// MARK: - JSON Request/Response Models

struct TodoSyncRequest: Encodable {
    let content: String
}

struct TodoSyncResponse: Decodable {
    let success: Bool?
    let message: String?
    let content: String?
}

actor TodoService {
    static let shared = TodoService()
    
    private let keychainManager = KeychainManager.shared
    private let localStorageKey = "local_todo_list"
    
    // URLSession that accepts self-signed certificates
    private let urlSession: URLSession
    private let sessionDelegate = InsecureURLSessionDelegate()
    
    // Store the last error for debugging
    private(set) var lastError: String?
    private(set) var lastFetchedMarkdown: String?
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.urlSession = URLSession(configuration: config, delegate: sessionDelegate, delegateQueue: nil)
    }
    
    // MARK: - Endpoint URL
    
    /// Get the TODO sync endpoint URL
    /// Uses the OpenClaw endpoint stored in keychain, expects format like:
    /// http://192.168.1.196:3333/todo
    private func getTodoEndpoint() throws -> URL {
        guard let endpoint = try? keychainManager.getOpenClawEndpoint(), !endpoint.isEmpty else {
            print("[TodoService] No endpoint configured in keychain")
            throw TodoServiceError.noEndpointConfigured
        }
        
        // Sanitize URL - remove invisible Unicode characters (zero-width spaces, etc.)
        let sanitizedEndpoint = endpoint
            .replacingOccurrences(of: "\u{200B}", with: "")  // Zero-width space
            .replacingOccurrences(of: "\u{200C}", with: "")  // Zero-width non-joiner
            .replacingOccurrences(of: "\u{200D}", with: "")  // Zero-width joiner
            .replacingOccurrences(of: "\u{FEFF}", with: "")  // BOM
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        print("[TodoService] Endpoint from keychain: '\(sanitizedEndpoint)'")
        
        // The endpoint should be the full URL to the /todo endpoint
        // e.g., http://192.168.1.196:3333/todo
        guard let url = URL(string: sanitizedEndpoint) else {
            print("[TodoService] Invalid URL format: '\(sanitizedEndpoint)'")
            lastError = "Invalid URL format: \(sanitizedEndpoint)"
            throw TodoServiceError.invalidResponse
        }
        
        return url
    }
    
    // MARK: - Local Storage
    
    func loadLocal() -> TodoList {
        guard let data = UserDefaults.standard.data(forKey: localStorageKey),
              let todoList = try? JSONDecoder().decode(TodoList.self, from: data) else {
            return TodoList()
        }
        return todoList
    }
    
    func saveLocal(_ todoList: TodoList) {
        if let data = try? JSONEncoder().encode(todoList) {
            UserDefaults.standard.set(data, forKey: localStorageKey)
        }
    }
    
    // MARK: - Gateway Sync
    
    /// Fetch TODOs from the sync server
    /// GET /todo returns the markdown content directly
    func fetchFromGateway() async throws -> TodoList {
        let url: URL
        do {
            url = try getTodoEndpoint()
        } catch {
            lastError = "No endpoint configured"
            throw error
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("text/plain, text/markdown, application/json", forHTTPHeaderField: "Accept")
        request.setValue("OpenClaw-iOS/1.0", forHTTPHeaderField: "User-Agent")
        
        print("[TodoService] Fetching from: \(url.absoluteString)")
        
        do {
            let (data, response) = try await urlSession.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                lastError = "Invalid response type"
                throw TodoServiceError.invalidResponse
            }
            
            print("[TodoService] Response status: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode == 404 {
                // File doesn't exist yet, return empty list
                lastError = "File not found (404)"
                return TodoList()
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                let message = String(data: data, encoding: .utf8)
                lastError = "HTTP \(httpResponse.statusCode): \(message ?? "no body")"
                throw TodoServiceError.serverError(httpResponse.statusCode, message)
            }
            
            guard let responseString = String(data: data, encoding: .utf8) else {
                lastError = "Could not decode response as UTF-8"
                throw TodoServiceError.invalidResponse
            }
            
            // Check if response is JSON (Gateway returns {"success":true,"content":"..."})
            let markdown: String
            if responseString.trimmingCharacters(in: .whitespaces).hasPrefix("{") {
                // Parse JSON response
                if let jsonResponse = try? JSONDecoder().decode(TodoSyncResponse.self, from: data),
                   let content = jsonResponse.content {
                    markdown = content
                    print("[TodoService] Extracted markdown from JSON response")
                } else {
                    // Fallback: try to extract content manually
                    lastError = "Could not parse JSON response"
                    print("[TodoService] Failed to parse JSON: \(responseString.prefix(200))")
                    throw TodoServiceError.invalidResponse
                }
            } else {
                // Raw markdown response
                markdown = responseString
            }
            
            lastFetchedMarkdown = markdown
            lastError = nil
            print("[TodoService] Fetched markdown (\(markdown.count) chars):\n\(markdown.prefix(500))")
            
            let todoList = TodoList.fromMarkdown(markdown)
            print("[TodoService] Parsed \(todoList.items.count) items")
            
            return todoList
        } catch let error as TodoServiceError {
            throw error
        } catch {
            lastError = "Network error: \(error.localizedDescription)"
            print("[TodoService] Network error: \(error)")
            throw TodoServiceError.networkError(error)
        }
    }
    
    /// Save TODOs to the sync server
    /// PUT /todo with JSON body: {"content": "markdown content"}
    func saveToGateway(_ todoList: TodoList) async throws {
        let url: URL
        do {
            url = try getTodoEndpoint()
        } catch {
            lastError = "No endpoint configured for save"
            throw error
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("OpenClaw-iOS/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30
        
        // Generate markdown and wrap in JSON
        let markdown = todoList.toMarkdown()
        let syncRequest = TodoSyncRequest(content: markdown)
        
        do {
            request.httpBody = try JSONEncoder().encode(syncRequest)
        } catch {
            lastError = "Failed to encode request body: \(error)"
            print("[TodoService] JSON encode error: \(error)")
            throw TodoServiceError.invalidResponse
        }
        
        print("[TodoService] Saving to: \(url.absoluteString)")
        if let bodyData = request.httpBody, let bodyString = String(data: bodyData, encoding: .utf8) {
            print("[TodoService] Request body JSON: \(bodyString.prefix(500))")
        }
        print("[TodoService] Method: PUT")
        print("[TodoService] Content-Type: application/json")
        print("[TodoService] Body size: \(request.httpBody?.count ?? 0) bytes")
        print("[TodoService] Markdown to save:\n\(markdown)")
        
        do {
            let (data, response) = try await urlSession.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                lastError = "Invalid response type on save"
                throw TodoServiceError.invalidResponse
            }
            
            let responseBody = String(data: data, encoding: .utf8) ?? "(no body)"
            print("[TodoService] Save response status: \(httpResponse.statusCode)")
            print("[TodoService] Save response body: \(responseBody.prefix(500))")
            
            guard (200...299).contains(httpResponse.statusCode) else {
                lastError = "Save failed: HTTP \(httpResponse.statusCode) - \(responseBody.prefix(200))"
                throw TodoServiceError.serverError(httpResponse.statusCode, responseBody)
            }
            
            // Update lastFetchedMarkdown with what we saved
            lastFetchedMarkdown = markdown
            lastError = nil
            print("[TodoService] Save successful!")
        } catch let error as TodoServiceError {
            throw error
        } catch {
            lastError = "Save network error: \(error.localizedDescription)"
            print("[TodoService] Save error: \(error)")
            throw TodoServiceError.networkError(error)
        }
    }
    
    // MARK: - Sync Operations
    
    func sync() async throws -> TodoList {
        // Try to fetch from gateway
        do {
            let remoteTodoList = try await fetchFromGateway()
            saveLocal(remoteTodoList)
            return remoteTodoList
        } catch TodoServiceError.noEndpointConfigured {
            // No gateway configured, just use local
            return loadLocal()
        }
    }
    
    func syncAndSave(_ todoList: TodoList) async throws {
        // Save locally first
        saveLocal(todoList)
        
        // Then try to push to gateway
        try await saveToGateway(todoList)
    }
    
    // MARK: - Health Check
    
    /// Check if the sync server is reachable
    func checkHealth() async -> Bool {
        guard let url = try? getTodoEndpoint(),
              let healthUrl = URL(string: url.absoluteString.replacingOccurrences(of: "/todo", with: "/health")) else {
            return false
        }
        
        var request = URLRequest(url: healthUrl)
        request.httpMethod = "GET"
        request.timeoutInterval = 5
        
        do {
            let (_, response) = try await urlSession.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
            return false
        } catch {
            return false
        }
    }
    
    // MARK: - Debug Info
    
    func getDebugInfo() -> String {
        let endpoint: String
        do {
            endpoint = try keychainManager.getOpenClawEndpoint()
        } catch {
            endpoint = "ERROR: \(error.localizedDescription)"
        }
        
        let hasEndpoint = keychainManager.hasOpenClawEndpoint()
        
        let markdownPreview: String
        if let md = lastFetchedMarkdown {
            markdownPreview = "(\(md.count) chars): \(md.prefix(300))..."
        } else {
            markdownPreview = "none"
        }
        
        return """
        Endpoint: \(hasEndpoint ? endpoint : "NOT SET")
        Error: \(lastError ?? "none")
        Markdown: \(markdownPreview)
        """
    }
    
    // For checking raw content
    func getLastMarkdown() -> String? {
        return lastFetchedMarkdown
    }
}
