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
    @Published private(set) var lastError: String?

    private var cancellables = Set<AnyCancellable>()
    private let keychainManager = KeychainManager.shared
    private let audioSessionManager = AudioSessionManager.shared

    private init() {}

    // MARK: - Public Methods

    /// Start a conversation with a public agent (using agent ID only)
    func startConversation() async throws {
        guard state == .idle || state.isEndedOrError else {
            Log.debug("Already in state: \(state), skipping")
            return
        }

        state = .connecting
        Log.info("Connecting to public agent")

        let agentId: String
        do {
            agentId = try keychainManager.getAgentId()
        } catch {
            state = .error("Agent ID not configured")
            Log.error("Agent ID not configured")
            throw error
        }

        do {
            let config = ConversationConfig()
            conversation = try await ElevenLabs.startConversation(
                agentId: agentId,
                config: config
            )
            setupConversationBindings()
            state = .active
            Log.info("Public conversation active")
        } catch {
            state = .error("Connection failed: \(error.localizedDescription)")
            Log.error("Connection failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// Start a conversation with a private agent (using conversation token)
    func startPrivateConversation() async throws {
        guard state == .idle || state.isEndedOrError else {
            Log.debug("Already in state: \(state), skipping private")
            return
        }

        state = .connecting
        Log.info("Connecting to private agent")

        let agentId: String
        let apiKey: String

        do {
            agentId = try keychainManager.getAgentId()
            apiKey = try keychainManager.getElevenLabsApiKey()
        } catch {
            state = .error("Credentials not configured")
            Log.error("Credentials not configured")
            throw error
        }

        do {
            let token = try await TokenService.shared.fetchToken(agentId: agentId, apiKey: apiKey)

            let config = ConversationConfig()
            conversation = try await ElevenLabs.startConversation(
                conversationToken: token,
                config: config
            )
            setupConversationBindings()
            state = .active
            Log.info("Private conversation active")
        } catch {
            state = .error("Connection failed: \(error.localizedDescription)")
            Log.error("Private connection failed: \(error.localizedDescription)")
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

    func toggleMute() async throws {
        guard let conversation else { return }
        try await conversation.toggleMute()
        isMuted = conversation.isMuted
    }

    func sendTextMessage(_ text: String) async throws {
        guard let conversation else { return }
        try await conversation.sendMessage(text)
    }

    // MARK: - Private Methods

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
                    Log.debug("Unknown SDK state")
                    break
                }
            }
            .store(in: &cancellables)

        // Deduplicate by message ID (stable), fall back to content+role for SDK streaming quirks
        conversation.$messages
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sdkMessages in
                var seenIds = Set<String>()
                var seenContent = Set<String>()
                var uniqueMessages: [ConversationMessage] = []

                for msg in sdkMessages {
                    // Primary: skip messages with duplicate IDs
                    guard seenIds.insert(msg.id).inserted else { continue }

                    // Secondary: skip same role+content within one batch (SDK streaming dups)
                    let contentKey = "\(msg.role)-\(msg.content)"
                    guard seenContent.insert(contentKey).inserted else {
                        Log.debug("Skipped duplicate message: \(msg.content.prefix(30))...")
                        continue
                    }

                    uniqueMessages.append(ConversationMessage(
                        id: msg.id,
                        source: msg.role == .user ? .user : .ai,
                        message: msg.content
                    ))
                }

                self?.messages = uniqueMessages
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
