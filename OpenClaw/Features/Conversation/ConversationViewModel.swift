//
//  ConversationViewModel.swift
//  OpenClaw
//
//  ViewModel for the main conversation interface
//  Routes: voice → ElevenLabs, text → OpenClaw Gateway
//

import Foundation
import Combine

@MainActor
final class ConversationViewModel: ObservableObject {
    @Published var showSettings = false
    @Published var isVoiceModeActive = false
    @Published var textInput = ""
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var isSendingText = false
    
    // Notification-related state
    @Published var showNotificationMessage = false
    @Published var notificationMessageContent: String?
    private var pendingMessageToSend: String?
    private var notificationContext: String?
    
    private let conversationManager = ConversationManager.shared
    private let gatewayChatService = GatewayChatService.shared
    private let networkMonitor = NetworkMonitor.shared
    private let keychainManager = KeychainManager.shared
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Forwarded Properties
    
    var state: AppConversationState {
        conversationManager.state
    }
    
    var messages: [ConversationMessage] {
        conversationManager.messages
    }
    
    var agentState: AgentMode {
        conversationManager.agentState
    }
    
    var isMuted: Bool {
        conversationManager.isMuted
    }
    
    var isConnected: Bool {
        state == .active
    }
    
    var isNetworkAvailable: Bool {
        networkMonitor.isConnected
    }
    
    var connectionStatus: String {
        switch state {
        case .idle:
            return "Ready"
        case .connecting:
            return "Connecting..."
        case .active:
            return "Connected"
        case .ended(let reason):
            return "Ended: \(reason)"
        case .error(let message):
            return "Error: \(message)"
        }
    }
    
    var statusColor: StatusColor {
        switch state {
        case .idle:
            return .neutral
        case .connecting:
            return .connecting
        case .active:
            return .connected
        case .ended, .error:
            return .disconnected
        }
    }
    
    enum StatusColor {
        case neutral, connecting, connected, disconnected
    }
    
    // MARK: - Init
    
    init() {
        setupBindings()
    }
    
    private func setupBindings() {
        conversationManager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        networkMonitor.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Voice Actions (ElevenLabs)
    
    func startConversation() async {
        guard isNetworkAvailable else {
            showErrorMessage("No network connection available")
            return
        }
        
        let hasKey = keychainManager.hasApiKey()
        
        do {
            if hasKey {
                try await conversationManager.startPrivateConversation()
            } else {
                try await conversationManager.startConversation()
            }
        } catch {
            showErrorMessage(error.localizedDescription)
        }
    }
    
    func endConversation() async {
        await conversationManager.endConversation()
    }
    
    func toggleMute() async {
        await conversationManager.toggleMute()
    }
    
    /// Send a text message into the active voice session (type while talking)
    func sendVoiceSessionMessage(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        await conversationManager.sendTextMessage(text)
        textInput = ""
    }
    
    // MARK: - Text Actions (OpenClaw Gateway)
    
    /// Send a text message directly to the OpenClaw Gateway — no ElevenLabs involved
    func sendTextMessage(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        guard isNetworkAvailable else {
            showErrorMessage("No network connection available")
            return
        }
        
        // Add user message to transcript immediately
        conversationManager.appendMessage(ConversationMessage(source: .user, message: trimmed))
        textInput = ""
        isSendingText = true
        
        do {
            // Build conversation history from existing messages for context
            let history = messages.compactMap { msg -> ChatMessage? in
                guard msg.source == .user || msg.source == .ai else { return nil }
                return ChatMessage(
                    role: msg.source == .user ? "user" : "assistant",
                    content: msg.message
                )
            }
            // Drop the last message since we pass it as the new message
            let priorHistory = history.dropLast()
            
            let response = try await gatewayChatService.sendMessage(trimmed, conversationHistory: Array(priorHistory))
            
            // Add agent response to transcript
            conversationManager.appendMessage(ConversationMessage(source: .ai, message: response.content))
        } catch {
            print("[OpenClaw] Text chat error: \(error)")
            showErrorMessage(error.localizedDescription)
        }
        
        isSendingText = false
    }
    
    // MARK: - Helpers
    
    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
    }
    
    // MARK: - Deep Link / Notification Handling
    
    func handleDeepLinkAction(_ action: DeepLinkAction) {
        switch action {
        case .startConversation(let context):
            notificationContext = context
            Task {
                await startConversation()
                if let ctx = context, !ctx.isEmpty {
                    print("[OpenClaw] Started conversation with context: \(ctx)")
                }
            }
            
        case .showMessage(let message):
            notificationMessageContent = message
            showNotificationMessage = true
            
        case .sendMessage(let text, let context):
            notificationContext = context
            pendingMessageToSend = text
            Task {
                if let messageText = pendingMessageToSend {
                    await sendTextMessage(messageText)
                    pendingMessageToSend = nil
                }
            }
            
        case .openSettings:
            showSettings = true
            
        case .openResearchLab, .openResearchProject:
            break
        }
    }
    
    /// Clear any pending notification state
    func clearNotificationState() {
        notificationMessageContent = nil
        pendingMessageToSend = nil
        notificationContext = nil
    }
}
