//
//  ConversationManager.swift
//  OpenClaw
//
//  Wraps the ElevenLabs SDK Conversation class for voice interactions
//

import Foundation
import Combine
import ElevenLabs

enum AppConversationState: Equatable {
    case idle
    case connecting
    case active
    case ended(String)
    case error(String)
    
    static func == (lhs: AppConversationState, rhs: AppConversationState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.connecting, .connecting), (.active, .active):
            return true
        case (.ended(let a), .ended(let b)):
            return a == b
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }
}

@MainActor
final class ConversationManager: ObservableObject {
    static let shared = ConversationManager()
    
    @Published private(set) var conversation: Conversation?
    
    @Published private(set) var state: AppConversationState = .idle
    @Published private(set) var messages: [ConversationMessage] = []
    @Published private(set) var agentState: AgentMode = .listening
    @Published private(set) var isMuted: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    private let keychainManager = KeychainManager.shared
    private let audioSessionManager = AudioSessionManager.shared
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Start a voice conversation with a public agent
    func startConversation() async throws {
        guard state == .idle || state.isEndedOrError else {
            print("[OpenClaw] Already in state: \(state), skipping")
            return
        }
        
        state = .connecting
        print("[OpenClaw] State: connecting")
        
        let agentId: String
        do {
            agentId = try keychainManager.getAgentId()
            print("[OpenClaw] Got agent ID: \(agentId.prefix(8))...")
        } catch {
            state = .error("Agent ID not configured")
            throw error
        }
        
        do {
            let config = buildConfig()
            conversation = try await ElevenLabs.startConversation(
                agentId: agentId,
                config: config
            )
            setupConversationBindings()
            if state == .connecting {
                state = .active
            }
            print("[OpenClaw] Voice conversation active")
        } catch {
            state = .error("Connection failed: \(error.localizedDescription)")
            print("[OpenClaw] Connection failed: \(error)")
            throw error
        }
    }
    
    /// Start a voice conversation with a private agent (using conversation token)
    func startPrivateConversation() async throws {
        guard state == .idle || state.isEndedOrError else {
            print("[OpenClaw] Already in state: \(state), skipping private")
            return
        }
        
        state = .connecting
        print("[OpenClaw] State: connecting (private)")
        
        let agentId: String
        let apiKey: String
        
        do {
            agentId = try keychainManager.getAgentId()
            apiKey = try keychainManager.getElevenLabsApiKey()
        } catch {
            state = .error("Credentials not configured")
            throw error
        }
        
        do {
            let token = try await TokenService.shared.fetchToken(agentId: agentId, apiKey: apiKey)
            let config = buildConfig()
            conversation = try await ElevenLabs.startConversation(
                conversationToken: token,
                config: config
            )
            setupConversationBindings()
            if state == .connecting {
                state = .active
            }
            print("[OpenClaw] Private voice conversation active")
        } catch {
            state = .error("Connection failed: \(error.localizedDescription)")
            print("[OpenClaw] Private connection failed: \(error)")
            throw error
        }
    }
    
    func endConversation() async {
        await conversation?.endConversation()
        conversation = nil
        cancellables.removeAll()
        messages = []
        agentState = .listening
        isMuted = false
        state = .idle
    }
    
    func toggleMute() async {
        guard let conversation else { return }
        try? await conversation.toggleMute()
        isMuted = conversation.isMuted
    }
    
    func sendTextMessage(_ text: String) async {
        guard let conversation else {
            print("[OpenClaw] sendTextMessage failed: no conversation object")
            return
        }
        do {
            try await conversation.sendMessage(text)
        } catch {
            print("[OpenClaw] sendTextMessage ERROR: \(error)")
        }
    }
    
    /// Append a message to the transcript (used by ViewModel for text chat messages)
    func appendMessage(_ message: ConversationMessage) {
        messages.append(message)
    }
    
    // MARK: - Private Methods
    
    private func buildConfig() -> ConversationConfig {
        ConversationConfig(
            onAgentResponse: { [weak self] text, eventId in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let isDuplicate = self.messages.contains { $0.source == .ai && $0.message == text }
                    if !isDuplicate {
                        self.messages.append(ConversationMessage(source: .ai, message: text))
                    }
                }
            },
            onUserTranscript: { [weak self] text, eventId in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let isDuplicate = self.messages.contains { $0.source == .user && $0.message == text }
                    if !isDuplicate {
                        self.messages.append(ConversationMessage(source: .user, message: text))
                    }
                }
            }
        )
    }
    
    private func setupConversationBindings() {
        guard let conversation else { return }
        
        conversation.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sdkState in
                switch sdkState {
                case .active:
                    self?.state = .active
                case .ended(let reason):
                    self?.state = .ended("\(reason)")
                case .error(let err):
                    self?.state = .error(err.localizedDescription)
                case .idle:
                    self?.state = .idle
                case .connecting:
                    self?.state = .connecting
                @unknown default:
                    break
                }
            }
            .store(in: &cancellables)
        
        // Backup: sync SDK messages we might have missed via callbacks
        conversation.$messages
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sdkMessages in
                guard let self else { return }
                var seen = Set<String>()
                for msg in self.messages {
                    seen.insert("\(msg.source.rawValue)-\(msg.message)")
                }
                for msg in sdkMessages {
                    let key = "\(msg.role == .user ? "user" : "ai")-\(msg.content)"
                    if !seen.contains(key) {
                        seen.insert(key)
                        self.messages.append(ConversationMessage(
                            id: msg.id,
                            source: msg.role == .user ? .user : .ai,
                            message: msg.content
                        ))
                    }
                }
            }
            .store(in: &cancellables)
        
        conversation.$agentState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sdkAgentState in
                switch sdkAgentState {
                case .listening:
                    self?.agentState = .listening
                case .speaking:
                    self?.agentState = .speaking
                case .thinking:
                    self?.agentState = .listening
                @unknown default:
                    break
                }
            }
            .store(in: &cancellables)
        
        conversation.$isMuted
            .receive(on: DispatchQueue.main)
            .sink { [weak self] muted in
                self?.isMuted = muted
            }
            .store(in: &cancellables)
    }
}

// MARK: - State Helpers

extension AppConversationState {
    var isEndedOrError: Bool {
        switch self {
        case .ended, .error:
            return true
        default:
            return false
        }
    }
}
