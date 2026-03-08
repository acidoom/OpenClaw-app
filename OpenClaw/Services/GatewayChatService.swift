//
//  GatewayChatService.swift
//  OpenClaw
//
//  Sends text messages directly to the OpenClaw Gateway /v1/chat/completions endpoint
//

import Foundation

actor GatewayChatService {
    static let shared = GatewayChatService()
    
    private let keychainManager = KeychainManager.shared
    private let session: URLSession
    
    private init() {
        let delegate = TailscaleTrustDelegate()
        session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
    }
    
    struct ChatResponse {
        let content: String
    }
    
    /// Send a text message to the OpenClaw Gateway and get a text response
    func sendMessage(_ text: String, conversationHistory: [ChatMessage] = []) async throws -> ChatResponse {
        // Use dedicated chat endpoint if set, otherwise fall back to base endpoint
        let chatEndpoint: String
        if let dedicated = try? keychainManager.get(.gatewayChatEndpoint), !dedicated.isEmpty {
            chatEndpoint = dedicated
        } else if let baseURL = try? keychainManager.get(.openClawEndpoint), !baseURL.isEmpty {
            chatEndpoint = baseURL
        } else {
            throw GatewayChatError.endpointNotConfigured
        }
        
        guard let hookToken = try? keychainManager.get(.gatewayHookToken), !hookToken.isEmpty else {
            throw GatewayChatError.tokenNotConfigured
        }
        
        // Build the full URL — append /v1/chat/completions if not already present
        let cleanBase = chatEndpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let urlString = cleanBase.hasSuffix("/v1/chat/completions")
            ? cleanBase
            : "\(cleanBase)/v1/chat/completions"
        
        guard let url = URL(string: urlString) else {
            throw GatewayChatError.invalidURL
        }
        
        print("[OpenClaw] GatewayChatService: URL = \(urlString)")
        let trimmedToken = hookToken.trimmingCharacters(in: .whitespacesAndNewlines)
        print("[OpenClaw] GatewayChatService: token length=\(trimmedToken.count) prefix=\(trimmedToken.prefix(12))... suffix=...\(trimmedToken.suffix(6))")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(trimmedToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        
        // Build messages array with conversation history
        var messages: [[String: String]] = conversationHistory.map { msg in
            ["role": msg.role, "content": msg.content]
        }
        messages.append(["role": "user", "content": text])
        
        let body: [String: Any] = [
            "model": "openclaw:main",
            "user": "antares",
            "messages": messages
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        if let bodyData = request.httpBody, let bodyStr = String(data: bodyData, encoding: .utf8) {
            print("[OpenClaw] GatewayChatService: body = \(bodyStr)")
        }
        print("[OpenClaw] GatewayChatService: sending to \(urlString)")
        
        // Retry once on -1005 (connection lost) — common transient iOS networking issue
        let (data, response) = try await performRequestWithRetry(request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GatewayChatError.invalidResponse
        }
        
        print("[OpenClaw] GatewayChatService: HTTP \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
            print("[OpenClaw] GatewayChatService error: \(errorBody)")
            throw GatewayChatError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }
        
        // Parse OpenAI-compatible chat completion response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            print("[OpenClaw] GatewayChatService: failed to parse response: \(String(data: data, encoding: .utf8) ?? "nil")")
            throw GatewayChatError.decodingError
        }
        
        print("[OpenClaw] GatewayChatService: got response (\(content.count) chars)")
        return ChatResponse(content: content)
    }
    
    private func performRequestWithRetry(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let urlError as URLError where urlError.code == .networkConnectionLost {
            print("[OpenClaw] GatewayChatService: attempt 1 connection lost, retrying...")
            if let underlying = (urlError as NSError).userInfo[NSUnderlyingErrorKey] as? Error {
                print("[OpenClaw] GatewayChatService: underlying = \(underlying)")
            }
            try await Task.sleep(nanoseconds: 500_000_000)
            do {
                return try await session.data(for: request)
            } catch let retryError as URLError {
                print("[OpenClaw] GatewayChatService: attempt 2 URLError code=\(retryError.code.rawValue) — \(retryError.localizedDescription)")
                throw GatewayChatError.networkError(retryError)
            }
        } catch let urlError as URLError {
            print("[OpenClaw] GatewayChatService: URLError code=\(urlError.code.rawValue) — \(urlError.localizedDescription)")
            if let underlying = (urlError as NSError).userInfo[NSUnderlyingErrorKey] as? Error {
                print("[OpenClaw] GatewayChatService: underlying = \(underlying)")
            }
            throw GatewayChatError.networkError(urlError)
        }
    }
}

/// Simple message struct for building conversation history
struct ChatMessage {
    let role: String
    let content: String
}

// MARK: - URLSession delegate that trusts Tailscale Funnel certificates

final class TailscaleTrustDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let host = challenge.protectionSpace.host
        print("[OpenClaw] TLS challenge for host: \(host), method: \(challenge.protectionSpace.authenticationMethod)")
        
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        
        // Trust Tailscale Funnel domains and Tailscale internal IPs (100.64.0.0/10)
        if host.hasSuffix(".ts.net") || Self.isTailscaleIP(host) {
            print("[OpenClaw] Trusting certificate for \(host)")
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
            return
        }
        
        completionHandler(.performDefaultHandling, nil)
    }
    
    /// Check if host is a Tailscale internal IP (100.64.0.0/10 = 100.64.x.x – 100.127.x.x)
    private static func isTailscaleIP(_ host: String) -> Bool {
        let parts = host.split(separator: ".").compactMap { UInt8($0) }
        guard parts.count == 4, parts[0] == 100 else { return false }
        return parts[1] >= 64 && parts[1] <= 127
    }
}

enum GatewayChatError: Error, LocalizedError {
    case endpointNotConfigured
    case tokenNotConfigured
    case invalidURL
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case networkError(URLError)
    case decodingError
    
    var errorDescription: String? {
        switch self {
        case .endpointNotConfigured:
            return "OpenClaw endpoint not configured. Set it in Settings."
        case .tokenNotConfigured:
            return "Gateway hook token not configured. Set it in Settings."
        case .invalidURL:
            return "Invalid Gateway URL"
        case .invalidResponse:
            return "Invalid response from Gateway"
        case .apiError(let statusCode, let message):
            return "Gateway error (HTTP \(statusCode)): \(message)"
        case .networkError(let urlError):
            return "Network error (\(urlError.code.rawValue)): \(urlError.localizedDescription)"
        case .decodingError:
            return "Failed to parse Gateway response"
        }
    }
}
