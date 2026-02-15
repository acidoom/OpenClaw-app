//
//  ConversationHistoryStore.swift
//  OpenClaw
//
//  Persists conversation sessions and messages to SwiftData
//

import Foundation
import SwiftData

@MainActor
final class ConversationHistoryStore {
    static let shared = ConversationHistoryStore()

    let container: ModelContainer

    private var activeSession: ConversationSession?

    private init() {
        do {
            container = try ModelContainer(for: ConversationSession.self, PersistedMessage.self)
        } catch {
            fatalError("Failed to create SwiftData container: \(error)")
        }
    }

    var context: ModelContext {
        container.mainContext
    }

    // MARK: - Session Lifecycle

    func startSession(isPrivateAgent: Bool) -> ConversationSession {
        let session = ConversationSession(isPrivateAgent: isPrivateAgent)
        context.insert(session)
        activeSession = session
        save()
        Log.debug("History: session started \(session.id.prefix(8))...")
        return session
    }

    func endSession() {
        guard let session = activeSession else { return }
        session.endedAt = Date()
        session.messageCount = session.messages.count
        activeSession = nil
        save()
        Log.debug("History: session ended with \(session.messageCount) messages")
    }

    // MARK: - Messages

    func addMessage(source: MessageSource, content: String) {
        guard let session = activeSession else { return }
        let message = PersistedMessage(source: source, content: content)
        session.messages.append(message)
        session.messageCount = session.messages.count
        save()
    }

    // MARK: - Queries

    func fetchSessions(limit: Int = 50) -> [ConversationSession] {
        let descriptor = FetchDescriptor<ConversationSession>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        do {
            var limited = descriptor
            limited.fetchLimit = limit
            return try context.fetch(limited)
        } catch {
            Log.error("History: failed to fetch sessions: \(error.localizedDescription)")
            return []
        }
    }

    func deleteSession(_ session: ConversationSession) {
        context.delete(session)
        save()
    }

    func deleteAllSessions() {
        do {
            try context.delete(model: ConversationSession.self)
            save()
        } catch {
            Log.error("History: failed to delete all: \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    private func save() {
        do {
            try context.save()
        } catch {
            Log.error("History: save failed: \(error.localizedDescription)")
        }
    }
}
