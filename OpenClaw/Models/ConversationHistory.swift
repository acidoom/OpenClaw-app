//
//  ConversationHistory.swift
//  OpenClaw
//
//  SwiftData models for persisting conversation sessions and messages
//

import Foundation
import SwiftData

@Model
final class ConversationSession {
    var id: String
    var startedAt: Date
    var endedAt: Date?
    var messageCount: Int
    var isPrivateAgent: Bool

    @Relationship(deleteRule: .cascade)
    var messages: [PersistedMessage]

    init(isPrivateAgent: Bool = false) {
        self.id = UUID().uuidString
        self.startedAt = Date()
        self.endedAt = nil
        self.messageCount = 0
        self.isPrivateAgent = isPrivateAgent
        self.messages = []
    }

    var duration: TimeInterval? {
        guard let endedAt else { return nil }
        return endedAt.timeIntervalSince(startedAt)
    }

    var durationText: String {
        guard let duration else { return "In progress" }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    var preview: String {
        messages.first(where: { $0.source == "ai" })?.content ?? "No messages"
    }
}

@Model
final class PersistedMessage {
    var id: String
    var source: String // "user", "ai", "system"
    var content: String
    var timestamp: Date

    init(source: MessageSource, content: String) {
        self.id = UUID().uuidString
        self.source = source.rawValue
        self.content = content
        self.timestamp = Date()
    }
}
