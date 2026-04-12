//
//  MessageBubbleView.swift
//  OpenClaw
//
//  Chat message bubble component
//

import SwiftUI

struct MessageBubbleView: View {
    let message: ConversationMessage
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    private var isUser: Bool {
        message.source == .user
    }
    
    private var spacerLength: CGFloat {
        horizontalSizeClass == .regular ? 150 : 50
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if isUser { Spacer(minLength: spacerLength) }
            
            // Avatar for AI messages
            if !isUser {
                Circle()
                    .fill(Color.anthropicCoral.opacity(0.15))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "sparkles")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.anthropicCoral)
                    )
            }
            
            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                // Role label
                Text(isUser ? "You" : "OpenClaw")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.textSecondary)
                
                // Message content
                Text(message.message)
                    .font(.body)
                    .foregroundColor(isUser ? .white : .textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(isUser ? Color.messageBubbleUser : Color.messageBubbleAgent)
                    )
                    .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
            }
            
            // Avatar for user messages
            if isUser {
                Circle()
                    .fill(Color.anthropicOrange.opacity(0.15))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.anthropicOrange)
                    )
            }
            
            if !isUser { Spacer(minLength: spacerLength) }
        }
    }
}

#Preview {
    ZStack {
        Color.backgroundDark.ignoresSafeArea()
        
        VStack(spacing: 16) {
            MessageBubbleView(
                message: ConversationMessage(source: .user, message: "Hello, how are you today?")
            )
            
            MessageBubbleView(
                message: ConversationMessage(source: .ai, message: "I'm doing great! How can I help you with your tasks today?")
            )
            
            MessageBubbleView(
                message: ConversationMessage(source: .user, message: "Can you check my calendar?")
            )
        }
        .padding()
    }
}
