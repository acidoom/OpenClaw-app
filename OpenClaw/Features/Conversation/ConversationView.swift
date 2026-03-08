//
//  ConversationView.swift
//  OpenClaw
//
//  Text-first conversation interface with voice on demand - Claude iOS inspired
//

import SwiftUI

struct ConversationView: View {
    @StateObject private var viewModel = ConversationViewModel()
    @EnvironmentObject private var appState: AppState
    @FocusState private var isTextFieldFocused: Bool
    
    private var sendButtonDisabled: Bool {
        viewModel.textInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSendingText
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Clean warm dark background
                Color.backgroundDark
                    .ignoresSafeArea()
                
                // Subtle gradient overlay
                LinearGradient(
                    colors: [
                        Color.anthropicCoral.opacity(0.05),
                        Color.clear,
                        Color.anthropicOrange.opacity(0.03)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Message transcript - main content area
                    messageListView
                    
                    // Voice mode overlay when active
                    if viewModel.isVoiceModeActive {
                        voiceModeView
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    
                    // Text input bar - always visible at bottom (Claude iOS style)
                    inputBarView
                }
            }
            .navigationTitle("OpenClaw")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.backgroundDark, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(.textSecondary)
                            .font(.system(size: 18, weight: .medium))
                    }
                }
            }
            .sheet(isPresented: $viewModel.showSettings) {
                SettingsView()
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "An unknown error occurred")
            }
            .alert("Message from OpenClaw", isPresented: $viewModel.showNotificationMessage) {
                Button("Start Chat") {
                    Task { await viewModel.startConversation() }
                }
                Button("Dismiss", role: .cancel) {}
            } message: {
                Text(viewModel.notificationMessageContent ?? "")
            }
            .onChange(of: appState.pendingAction) { _, newAction in
                if let action = newAction {
                    viewModel.handleDeepLinkAction(action)
                    appState.clearPendingAction()
                }
            }
            .onAppear {
                if let action = appState.pendingAction {
                    viewModel.handleDeepLinkAction(action)
                    appState.clearPendingAction()
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Message List View
    
    private var messageListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if viewModel.messages.isEmpty {
                    // Empty state with logo
                    VStack(spacing: 24) {
                        Spacer()
                        Image("OpenClawLogo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 200)
                            .opacity(0.4)
                        Text("Start a conversation")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(.textSecondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 100)
                } else {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(viewModel.messages) { message in
                            MessageBubbleView(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                if let lastMessage = viewModel.messages.last {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            .onTapGesture {
                isTextFieldFocused = false
            }
        }
    }
    
    // MARK: - Voice Mode View (Overlay)
    
    private var voiceModeView: some View {
        VStack(spacing: 20) {
            // Drag indicator
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color.textTertiary)
                .frame(width: 36, height: 5)
                .padding(.top, 12)
            
            // Connection status
            HStack(spacing: 8) {
                Circle()
                    .fill(viewModel.isConnected ? Color.statusConnected : Color.statusConnecting)
                    .frame(width: 8, height: 8)
                Text(viewModel.connectionStatus)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.textSecondary)
            }
            
            // Agent state indicator
            if viewModel.isConnected {
                AgentStateIndicator(state: viewModel.agentState)
            }
            
            // Animated orb
            OrbVisualizerView(
                agentState: viewModel.agentState,
                isConnected: viewModel.isConnected
            )
            .frame(width: 120, height: 120)
            
            // Voice controls
            HStack(spacing: 32) {
                // Mute toggle
                VoiceControlButton(
                    icon: viewModel.isMuted ? "mic.slash.fill" : "mic.fill",
                    label: viewModel.isMuted ? "Unmute" : "Mute",
                    isActive: viewModel.isMuted
                ) {
                    Task { await viewModel.toggleMute() }
                }
                
                // End voice call button
                VoiceControlButton(
                    icon: "xmark",
                    label: "End",
                    isDestructive: true
                ) {
                    Task {
                        await viewModel.endConversation()
                        withAnimation(.spring(response: 0.3)) {
                            viewModel.isVoiceModeActive = false
                        }
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.surfacePrimary)
                .shadow(color: .black.opacity(0.3), radius: 20, y: -5)
        )
        .padding(.horizontal, 8)
    }
    
    // MARK: - Input Bar View (Claude iOS Style)
    
    private var inputBarView: some View {
        VStack(spacing: 0) {
            // Separator line
            Rectangle()
                .fill(Color.surfaceSecondary)
                .frame(height: 1)
            
            HStack(alignment: .bottom, spacing: 12) {
                // Voice button (left side, like Claude iOS)
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        if viewModel.isVoiceModeActive {
                            Task { await viewModel.endConversation() }
                            viewModel.isVoiceModeActive = false
                        } else {
                            viewModel.isVoiceModeActive = true
                            Task { await viewModel.startConversation() }
                        }
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(viewModel.isVoiceModeActive ? Color.anthropicCoral : Color.surfaceSecondary)
                            .frame(width: 36, height: 36)
                        
                        if viewModel.state == .connecting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: viewModel.isVoiceModeActive ? "waveform" : "mic.fill")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(viewModel.isVoiceModeActive ? .white : .textSecondary)
                        }
                    }
                }
                .disabled(viewModel.state == .connecting)
                
                // Text input field
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Message", text: $viewModel.textInput, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1...6)
                        .focused($isTextFieldFocused)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                }
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.surfaceSecondary)
                )
                
                // Send button (right side)
                Button {
                    Task {
                        if viewModel.isVoiceModeActive {
                            // In voice mode: send text into the ElevenLabs voice session
                            await viewModel.sendVoiceSessionMessage(viewModel.textInput)
                        } else {
                            // Not in voice mode: send text directly to OpenClaw Gateway
                            await viewModel.sendTextMessage(viewModel.textInput)
                        }
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(sendButtonDisabled ? Color.surfaceSecondary : Color.anthropicCoral)
                            .frame(width: 36, height: 36)
                        
                        if viewModel.isSendingText {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(sendButtonDisabled ? .textTertiary : .white)
                        }
                    }
                }
                .disabled(sendButtonDisabled)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.backgroundDark)
        }
    }
}

// MARK: - Supporting Views

struct VoiceControlButton: View {
    let icon: String
    let label: String
    var isActive: Bool = false
    var isDestructive: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Circle()
                    .fill(backgroundColor)
                    .frame(width: 56, height: 56)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 22, weight: .medium))
                            .foregroundColor(iconColor)
                    )
                
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.textSecondary)
            }
        }
    }
    
    private var backgroundColor: Color {
        if isDestructive {
            return Color.statusDisconnected.opacity(0.2)
        }
        return isActive ? Color.anthropicCoral.opacity(0.2) : Color.surfaceSecondary
    }
    
    private var iconColor: Color {
        if isDestructive {
            return .statusDisconnected
        }
        return isActive ? .anthropicCoral : .textSecondary
    }
}

struct AgentStateIndicator: View {
    let state: AgentMode
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(state == .speaking ? Color.anthropicCoral : Color.anthropicOrange)
                .frame(width: 8, height: 8)
                .shadow(color: (state == .speaking ? Color.anthropicCoral : Color.anthropicOrange).opacity(0.5), radius: 4)
            
            Text(state == .speaking ? "Speaking" : "Listening")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.surfaceSecondary)
        )
    }
}

#Preview {
    ConversationView()
        .environmentObject(AppState.shared)
}
