//
//  SettingsViewModel.swift
//  OpenClaw
//
//  ViewModel for settings and configuration
//

import Foundation
import Combine
import UIKit

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var agentId: String = ""
    @Published var apiKey: String = ""
    @Published var isPrivateAgent: Bool = false
    @Published var openClawEndpoint: String = ""
    
    @Published var isSaved: Bool = false
    @Published var saveError: String?
    @Published var showSaveError: Bool = false
    
    @Published var isTestingConnection: Bool = false
    @Published var connectionTestResult: ConnectionTestResult?
    
    // User Preferences (non-sensitive, stored in UserDefaults)
    @Published var autoStartMic: Bool = false {
        didSet { UserDefaults.standard.set(autoStartMic, forKey: "autoStartMic") }
    }
    @Published var showTranscript: Bool = true {
        didSet { UserDefaults.standard.set(showTranscript, forKey: "showTranscript") }
    }
    @Published var hapticFeedback: Bool = true {
        didSet { UserDefaults.standard.set(hapticFeedback, forKey: "hapticFeedback") }
    }
    
    // Gateway Settings
    @Published var gatewayHookToken: String = ""
    
    // Notification Settings
    @Published var notificationsEnabled: Bool = false {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: "notificationsEnabled") }
    }
    
    private let keychainManager = KeychainManager.shared
    
    enum ConnectionTestResult {
        case success
        case failure(String)
    }
    
    init() {
        // Load Keychain values
        let keychain = KeychainManager.shared
        let loadedAgentId = (try? keychain.get(.agentId)) ?? ""
        let loadedApiKey = (try? keychain.get(.elevenLabsApiKey)) ?? ""
        let loadedEndpoint = (try? keychain.get(.openClawEndpoint)) ?? ""
        
        agentId = loadedAgentId
        apiKey = loadedApiKey
        openClawEndpoint = loadedEndpoint
        isPrivateAgent = !loadedApiKey.isEmpty
        
        // Load gateway hook token
        gatewayHookToken = (try? keychain.get(.gatewayHookToken)) ?? ""
        
        // Load UserDefaults preferences (without triggering didSet)
        _autoStartMic = Published(initialValue: UserDefaults.standard.bool(forKey: "autoStartMic"))
        _showTranscript = Published(initialValue: UserDefaults.standard.object(forKey: "showTranscript") as? Bool ?? true)
        _hapticFeedback = Published(initialValue: UserDefaults.standard.object(forKey: "hapticFeedback") as? Bool ?? true)
        _notificationsEnabled = Published(initialValue: UserDefaults.standard.bool(forKey: "notificationsEnabled"))
    }
    
    var canSave: Bool {
        !agentId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var canSaveBackend: Bool {
        !openClawEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    func saveBackendOnly() {
        let trimmedEndpoint = openClawEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHookToken = gatewayHookToken.trimmingCharacters(in: .whitespacesAndNewlines)
        
        do {
            if !trimmedEndpoint.isEmpty {
                try keychainManager.save(trimmedEndpoint, for: .openClawEndpoint)
                print("[Settings] Saved endpoint: \(trimmedEndpoint)")
            } else {
                try? keychainManager.delete(.openClawEndpoint)
            }
            
            if !trimmedHookToken.isEmpty {
                try keychainManager.save(trimmedHookToken, for: .gatewayHookToken)
                print("[Settings] Saved hook token")
            } else {
                try? keychainManager.delete(.gatewayHookToken)
            }
            
            isSaved = true
            
            // Reset saved indicator after delay
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                isSaved = false
            }
        } catch {
            saveError = error.localizedDescription
            showSaveError = true
        }
    }
    
    func save() {
        let trimmedAgentId = agentId.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedApiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEndpoint = openClawEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedAgentId.isEmpty else {
            saveError = "Agent ID is required"
            showSaveError = true
            return
        }
        
        do {
            try keychainManager.save(trimmedAgentId, for: .agentId)
            
            // Save API key if provided (regardless of toggle - if key is present, use private flow)
            if !trimmedApiKey.isEmpty {
                try keychainManager.save(trimmedApiKey, for: .elevenLabsApiKey)
            } else {
                // Clear API key if empty
                try? keychainManager.delete(.elevenLabsApiKey)
            }
            
            if !trimmedEndpoint.isEmpty {
                try keychainManager.save(trimmedEndpoint, for: .openClawEndpoint)
            } else {
                try? keychainManager.delete(.openClawEndpoint)
            }
            
            // Save gateway hook token
            let trimmedHookToken = gatewayHookToken.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedHookToken.isEmpty {
                try keychainManager.save(trimmedHookToken, for: .gatewayHookToken)
            } else {
                try? keychainManager.delete(.gatewayHookToken)
            }
            
            isSaved = true
            
            // Notify AppState
            AppState.shared.markConfigured()
            
            // Reset saved indicator after delay
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                isSaved = false
            }
        } catch {
            saveError = error.localizedDescription
            showSaveError = true
        }
    }
    
    func testConnection() async {
        isTestingConnection = true
        connectionTestResult = nil
        
        defer {
            isTestingConnection = false
        }
        
        // Simple validation test - check if we can fetch a token (for private agents)
        // or just validate the agent ID format
        let trimmedAgentId = agentId.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedApiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedAgentId.isEmpty else {
            connectionTestResult = .failure("Agent ID is required")
            return
        }
        
        if isPrivateAgent && !trimmedApiKey.isEmpty {
            do {
                _ = try await TokenService.shared.fetchToken(agentId: trimmedAgentId, apiKey: trimmedApiKey)
                connectionTestResult = .success
            } catch {
                connectionTestResult = .failure(error.localizedDescription)
            }
        } else {
            // For public agents, we can't easily test without starting a conversation
            // Just validate the format looks reasonable
            if trimmedAgentId.count > 10 {
                connectionTestResult = .success
            } else {
                connectionTestResult = .failure("Agent ID appears to be invalid")
            }
        }
    }
    
    func clearCredentials() {
        try? keychainManager.delete(.agentId)
        try? keychainManager.delete(.elevenLabsApiKey)
        try? keychainManager.delete(.openClawEndpoint)
        try? keychainManager.delete(.gatewayHookToken)
        agentId = ""
        apiKey = ""
        openClawEndpoint = ""
        gatewayHookToken = ""
        isPrivateAgent = false
        AppState.shared.checkConfiguration()
    }
    
    // MARK: - Notification Helpers
    
    func requestNotificationPermission() async -> Bool {
        let granted = await PushNotificationManager.shared.requestPermission()
        if granted {
            notificationsEnabled = true
        }
        return granted
    }
    
    func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            Task { @MainActor in
                UIApplication.shared.open(url)
            }
        }
    }
}
