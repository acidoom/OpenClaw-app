//
//  KeychainManager.swift
//  OpenClaw
//
//  Secure storage for API keys and sensitive configuration
//

import Foundation
import Security

enum KeychainError: Error, LocalizedError {
    case itemNotFound
    case duplicateItem
    case unexpectedStatus(OSStatus)
    case invalidData
    
    var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "Item not found in Keychain"
        case .duplicateItem:
            return "Item already exists in Keychain"
        case .unexpectedStatus(let status):
            return "Keychain error: \(status)"
        case .invalidData:
            return "Invalid data format"
        }
    }
}

final class KeychainManager {
    static let shared = KeychainManager()
    
    private let service = "com.openclaw.voice"
    
    enum Key: String {
        case elevenLabsApiKey = "elevenlabs_api_key"
        case agentId = "elevenlabs_agent_id"
        case openClawEndpoint = "openclaw_endpoint"
        case gatewayHookToken = "gateway_hook_token"
        
        // Research Lab - Zotero integration
        case zoteroApiKey = "zotero_api_key"
        case zoteroUserId = "zotero_user_id"
    }
    
    private init() {}
    
    // MARK: - Public Methods
    
    func save(_ value: String, for key: Key) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.invalidData
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data
        ]
        
        // Try to delete existing item first
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
    
    func get(_ key: Key) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.itemNotFound
            }
            throw KeychainError.unexpectedStatus(status)
        }
        
        guard let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        
        return string
    }
    
    func delete(_ key: Key) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
    
    // MARK: - Convenience Methods
    
    func getAgentId() throws -> String {
        try get(.agentId)
    }
    
    func getElevenLabsApiKey() throws -> String {
        try get(.elevenLabsApiKey)
    }
    
    func hasAgentId() -> Bool {
        (try? get(.agentId)) != nil
    }
    
    func hasApiKey() -> Bool {
        (try? get(.elevenLabsApiKey)) != nil
    }
    
    func getOpenClawEndpoint() throws -> String {
        try get(.openClawEndpoint)
    }
    
    func hasOpenClawEndpoint() -> Bool {
        (try? get(.openClawEndpoint)) != nil
    }
    
    func getGatewayHookToken() throws -> String {
        try get(.gatewayHookToken)
    }
    
    func hasGatewayHookToken() -> Bool {
        (try? get(.gatewayHookToken)) != nil
    }
    
    // MARK: - Zotero Methods
    
    func getZoteroApiKey() throws -> String {
        try get(.zoteroApiKey)
    }
    
    func getZoteroUserId() throws -> String {
        try get(.zoteroUserId)
    }
    
    func hasZoteroCredentials() -> Bool {
        (try? get(.zoteroApiKey)) != nil && (try? get(.zoteroUserId)) != nil
    }
    
    func saveZoteroCredentials(apiKey: String, userId: String) throws {
        try save(apiKey, for: .zoteroApiKey)
        try save(userId, for: .zoteroUserId)
    }
    
    func clearZoteroCredentials() throws {
        try delete(.zoteroApiKey)
        try delete(.zoteroUserId)
    }
}
