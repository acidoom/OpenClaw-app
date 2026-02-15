//
//  HistoryView.swift
//  OpenClaw
//
//  Displays past conversation sessions with full transcripts
//

import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var sessions: [ConversationSession] = []
    @State private var selectedSession: ConversationSession?

    private let historyStore = ConversationHistoryStore.shared

    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundDark.ignoresSafeArea()

                if sessions.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 48))
                            .foregroundColor(.textTertiary)
                        Text("No conversations yet")
                            .font(.headline)
                            .foregroundColor(.textSecondary)
                        Text("Your past conversations will appear here")
                            .font(.subheadline)
                            .foregroundColor(.textTertiary)
                    }
                } else {
                    List {
                        ForEach(sessions, id: \.id) { session in
                            Button {
                                selectedSession = session
                            } label: {
                                SessionRow(session: session)
                            }
                            .listRowBackground(Color.surfacePrimary)
                        }
                        .onDelete(perform: deleteSessions)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.backgroundDark, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.anthropicCoral)
                }
                if !sessions.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Clear All", role: .destructive) {
                            historyStore.deleteAllSessions()
                            sessions = []
                        }
                        .foregroundStyle(Color.statusDisconnected)
                    }
                }
            }
            .sheet(item: $selectedSession) { session in
                SessionDetailView(session: session)
            }
            .onAppear {
                sessions = historyStore.fetchSessions()
            }
        }
        .preferredColorScheme(.dark)
    }

    private func deleteSessions(at offsets: IndexSet) {
        for index in offsets {
            historyStore.deleteSession(sessions[index])
        }
        sessions.remove(atOffsets: offsets)
    }
}

// MARK: - Session Row

private struct SessionRow: View {
    let session: ConversationSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(session.startedAt, style: .date)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.textPrimary)

                Text(session.startedAt, style: .time)
                    .font(.caption)
                    .foregroundColor(.textSecondary)

                Spacer()

                Text(session.durationText)
                    .font(.caption)
                    .foregroundColor(.textTertiary)
            }

            Text(session.preview)
                .font(.subheadline)
                .foregroundColor(.textSecondary)
                .lineLimit(2)

            HStack(spacing: 12) {
                Label("\(session.messageCount)", systemImage: "bubble.left.fill")
                    .font(.caption)
                    .foregroundColor(.textTertiary)

                if session.isPrivateAgent {
                    Label("Private", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundColor(.anthropicOrange)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Session Detail

struct SessionDetailView: View {
    let session: ConversationSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundDark.ignoresSafeArea()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        // Session info header
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.startedAt, style: .date)
                                .font(.headline)
                                .foregroundColor(.textPrimary)
                            HStack {
                                Text(session.startedAt, style: .time)
                                Text("  \(session.durationText)")
                                Text("  \(session.messageCount) messages")
                            }
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                        }
                        .padding(.bottom, 8)

                        // Messages
                        ForEach(session.messages.sorted(by: { $0.timestamp < $1.timestamp }), id: \.id) { msg in
                            MessageBubbleView(message: ConversationMessage(
                                id: msg.id,
                                source: MessageSource(rawValue: msg.source) ?? .system,
                                message: msg.content,
                                timestamp: msg.timestamp
                            ))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("Conversation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.backgroundDark, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.anthropicCoral)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

