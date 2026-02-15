//
//  TokenService.swift
//  OpenClaw
//
//  Fetches conversation tokens from ElevenLabs for private agent authentication
//

import Foundation

enum TokenServiceError: Error, LocalizedError {
    case invalidURL
    case apiError(statusCode: Int)
    case decodingError
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .apiError(let statusCode):
            return "API error: HTTP \(statusCode)"
        case .decodingError:
            return "Failed to decode token response"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }

    var isRetryable: Bool {
        switch self {
        case .networkError:
            return true
        case .apiError(let statusCode):
            return statusCode >= 500 || statusCode == 429
        case .invalidURL, .decodingError:
            return false
        }
    }
}

private struct TokenResponse: Codable, Sendable {
    let token: String
}

actor TokenService {
    static let shared = TokenService()

    private let baseURL = "https://api.elevenlabs.io/v1/convai/conversation/token"
    private let maxRetries = 3

    private init() {}

    func fetchToken(agentId: String, apiKey: String) async throws -> String {
        var lastError: Error?

        for attempt in 0..<maxRetries {
            do {
                return try await performFetch(agentId: agentId, apiKey: apiKey)
            } catch let error as TokenServiceError where error.isRetryable {
                lastError = error
                if attempt < maxRetries - 1 {
                    let delay = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
                    Log.debug("Token fetch attempt \(attempt + 1) failed, retrying in \(1 << attempt)s")
                    try await Task.sleep(nanoseconds: delay)
                }
            } catch {
                throw error
            }
        }

        throw lastError ?? TokenServiceError.networkError(
            NSError(domain: "TokenService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Max retries exceeded"])
        )
    }

    private func performFetch(agentId: String, apiKey: String) async throws -> String {
        guard var urlComponents = URLComponents(string: baseURL) else {
            throw TokenServiceError.invalidURL
        }

        urlComponents.queryItems = [
            URLQueryItem(name: "agent_id", value: agentId)
        ]

        guard let url = urlComponents.url else {
            throw TokenServiceError.invalidURL
        }

        Log.debug("Fetching token for agent: \(agentId.prefix(8))...")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw TokenServiceError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TokenServiceError.apiError(statusCode: 0)
        }

        Log.debug("Token API response: \(httpResponse.statusCode)")

        guard httpResponse.statusCode == 200 else {
            throw TokenServiceError.apiError(statusCode: httpResponse.statusCode)
        }

        return try Self.parseToken(from: data)
    }

    private nonisolated static func parseToken(from data: Data) throws -> String {
        do {
            let response = try JSONDecoder().decode(TokenResponse.self, from: data)
            Log.debug("Token fetched successfully")
            return response.token
        } catch {
            Log.error("Failed to decode token response")
            throw TokenServiceError.decodingError
        }
    }
}
