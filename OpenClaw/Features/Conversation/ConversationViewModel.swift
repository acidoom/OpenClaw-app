//
//  ConversationViewModel.swift
//  OpenClaw
//
//  ViewModel for the main conversation interface
//

import Foundation
import Combine
import UIKit

@MainActor
final class ConversationViewModel: ObservableObject {
    @Published var showSettings = false
    @Published var showTextInput = false
    @Published var textInput = ""
    @Published var errorMessage: String?
    @Published var showError = false

    // Notification-related state
    @Published var showNotificationMessage = false
    @Published var notificationMessageContent: String?
    private var pendingMessageToSend: String?
    private var notificationContext: String?

    private let conversationManager = ConversationManager.shared
    private let networkMonitor = NetworkMonitor.shared
    private let keychainManager = KeychainManager.shared

    private var cancellables = Set<AnyCancellable>()
    private var previousState: AppConversationState = .idle

    // MARK: - User Preferences

    var showTranscript: Bool {
        UserDefaults.standard.object(forKey: "showTranscript") as? Bool ?? true
    }

    var autoStartMic: Bool {
        UserDefaults.standard.bool(forKey: "autoStartMic")
    }

    var hapticFeedbackEnabled: Bool {
        UserDefaults.standard.object(forKey: "hapticFeedback") as? Bool ?? true
    }

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
                self?.handleStateChange()
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

    // MARK: - Haptic Feedback

    private func handleStateChange() {
        let newState = conversationManager.state
        guard newState != previousState else { return }
        defer { previousState = newState }

        guard hapticFeedbackEnabled else { return }

        switch newState {
        case .active:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .ended:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .error:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        default:
            break
        }
    }

    // MARK: - Actions

    func startConversation() async {
        guard isNetworkAvailable else {
            showErrorMessage("No network connection available")
            return
        }

        let hasKey = keychainManager.hasApiKey()
        Log.info("Starting \(hasKey ? "private" : "public") conversation")

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

    func retryConnection() async {
        // Reset error state and try again
        await conversationManager.endConversation()
        await startConversation()
    }

    func endConversation() async {
        await conversationManager.endConversation()
    }

    func toggleMute() async {
        do {
            try await conversationManager.toggleMute()
            if hapticFeedbackEnabled {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        } catch {
            showErrorMessage("Failed to toggle mute: \(error.localizedDescription)")
        }
    }

    func sendMessage(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            try await conversationManager.sendTextMessage(text)
            textInput = ""
            if hapticFeedbackEnabled {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        } catch {
            showErrorMessage("Failed to send message: \(error.localizedDescription)")
        }
    }

    func toggleTextInput() {
        showTextInput.toggle()
    }

    /// Called on view appear — auto-starts if preference is set
    func onAppear() {
        if autoStartMic && state == .idle {
            Task { await startConversation() }
        }
    }

    // MARK: - Helpers

    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
    }

    private func awaitConnection(timeout: TimeInterval = 10) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !isConnected && Date() < deadline {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return isConnected
    }

    // MARK: - Deep Link / Notification Handling

    func handleDeepLinkAction(_ action: DeepLinkAction) {
        switch action {
        case .startConversation(let context):
            notificationContext = context
            Task {
                await startConversation()
                if let ctx = context, !ctx.isEmpty {
                    Log.debug("Started conversation with context: \(ctx)")
                }
            }

        case .showMessage(let message):
            notificationMessageContent = message
            showNotificationMessage = true

        case .sendMessage(let text, let context):
            notificationContext = context
            pendingMessageToSend = text
            Task {
                if !isConnected {
                    await startConversation()
                    let connected = await awaitConnection()
                    guard connected else {
                        Log.error("Timed out waiting for connection to send deep-link message")
                        pendingMessageToSend = nil
                        return
                    }
                }
                if let messageText = pendingMessageToSend {
                    await sendMessage(messageText)
                    pendingMessageToSend = nil
                }
            }

        case .openSettings:
            showSettings = true
        }
    }

    func clearNotificationState() {
        notificationMessageContent = nil
        pendingMessageToSend = nil
        notificationContext = nil
    }
}
