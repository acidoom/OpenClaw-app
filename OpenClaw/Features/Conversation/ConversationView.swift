//
//  ConversationView.swift
//  OpenClaw
//
//  Main voice conversation interface - Anthropic-inspired design
//

import SwiftUI

struct ConversationView: View {
    @StateObject private var viewModel = ConversationViewModel()
    @EnvironmentObject private var appState: AppState
    
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
                
                // OpenClaw logo watermark in background
                VStack {
                    Spacer()
                    Image("OpenClawLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 320)
                        .opacity(0.35)
                        .accessibilityHidden(true)
                    Spacer()
                }
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Connection status bar
                    ConnectionStatusBar(
                        status: viewModel.connectionStatus,
                        statusColor: viewModel.statusColor,
                        isNetworkAvailable: viewModel.isNetworkAvailable
                    )
                    
                    // Message transcript
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 16) {
                                ForEach(viewModel.messages) { message in
                                    MessageBubbleView(message: message)
                                        .id(message.id)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                        }
                        .onChange(of: viewModel.messages.count) { _, _ in
                            if let lastMessage = viewModel.messages.last {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                    
                    // Voice orb and controls - immersive design without container
                    VStack(spacing: 24) {
                        // Agent state indicator
                        if viewModel.isConnected {
                            AgentStateIndicator(state: viewModel.agentState)
                        }
                        
                        // Animated orb
                        OrbVisualizerView(
                            agentState: viewModel.agentState,
                            isConnected: viewModel.isConnected
                        )
                        .frame(width: 140, height: 140)
                        
                        // Control buttons
                        HStack(spacing: 40) {
                            // Text mode toggle
                            ControlButton(
                                icon: "keyboard",
                                isActive: viewModel.showTextInput,
                                isEnabled: viewModel.isConnected
                            ) {
                                viewModel.toggleTextInput()
                            }
                            .accessibilityLabel("Toggle text input")
                            .accessibilityHint("Switch between voice and text input")
                            
                            // Main action button
                            MainActionButton(
                                isConnected: viewModel.isConnected,
                                isConnecting: viewModel.state == .connecting
                            ) {
                                Task {
                                    if viewModel.isConnected {
                                        await viewModel.endConversation()
                                    } else {
                                        await viewModel.startConversation()
                                    }
                                }
                            }
                            
                            // Mute toggle
                            ControlButton(
                                icon: viewModel.isMuted ? "mic.slash.fill" : "mic.fill",
                                isActive: viewModel.isMuted,
                                isEnabled: viewModel.isConnected
                            ) {
                                Task { await viewModel.toggleMute() }
                            }
                            .accessibilityLabel(viewModel.isMuted ? "Unmute microphone" : "Mute microphone")
                        }
                        
                        // Optional text input
                        if viewModel.showTextInput && viewModel.isConnected {
                            TextInputBar(
                                text: $viewModel.textInput,
                                onSend: {
                                    Task { await viewModel.sendMessage(viewModel.textInput) }
                                }
                            )
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .padding(.vertical, 32)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
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
                    .accessibilityLabel("Settings")
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
                // Handle any pending action when view appears
                if let action = appState.pendingAction {
                    viewModel.handleDeepLinkAction(action)
                    appState.clearPendingAction()
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Supporting Views

struct ConnectionStatusBar: View {
    let status: String
    let statusColor: ConversationViewModel.StatusColor
    let isNetworkAvailable: Bool
    
    var body: some View {
        HStack(spacing: 10) {
            // Animated status dot
            Circle()
                .fill(indicatorColor)
                .frame(width: 8, height: 8)
                .shadow(color: indicatorColor.opacity(0.5), radius: 4)
            
            Text(status)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.textSecondary)
            
            Spacer()
            
            if !isNetworkAvailable {
                HStack(spacing: 4) {
                    Image(systemName: "wifi.slash")
                    Text("Offline")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.statusDisconnected)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.surfacePrimary.opacity(0.8))
    }
    
    private var indicatorColor: Color {
        switch statusColor {
        case .neutral:
            return .textTertiary
        case .connecting:
            return .statusConnecting
        case .connected:
            return .statusConnected
        case .disconnected:
            return .statusDisconnected
        }
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

struct ControlButton: View {
    let icon: String
    let isActive: Bool
    let isEnabled: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(isActive ? .anthropicCoral : .textSecondary)
                .frame(width: 52, height: 52)
                .background(
                    Circle()
                        .fill(Color.surfaceSecondary)
                )
                .overlay(
                    Circle()
                        .stroke(isActive ? Color.anthropicCoral.opacity(0.3) : Color.clear, lineWidth: 2)
                )
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
    }
}

struct MainActionButton: View {
    let isConnected: Bool
    let isConnecting: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                // Outer glow
                Circle()
                    .fill(buttonColor.opacity(0.2))
                    .frame(width: 88, height: 88)
                
                // Main button
                Circle()
                    .fill(
                        LinearGradient(
                            colors: isConnected ? [.statusDisconnected, .statusDisconnected.opacity(0.8)] : [.anthropicCoral, .anthropicOrange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)
                    .shadow(color: buttonColor.opacity(0.4), radius: 12, y: 4)
                
                if isConnecting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.2)
                } else {
                    Image(systemName: isConnected ? "stop.fill" : "waveform")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
        }
        .disabled(isConnecting)
        .scaleEffect(isConnecting ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isConnecting)
        .accessibilityLabel(isConnecting ? "Connecting" : isConnected ? "End conversation" : "Start conversation")
    }

    private var buttonColor: Color {
        if isConnecting {
            return .anthropicOrange
        }
        return isConnected ? .statusDisconnected : .anthropicCoral
    }
}

struct TextInputBar: View {
    @Binding var text: String
    let onSend: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            TextField("Type a message...", text: $text)
                .textFieldStyle(.plain)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color.surfaceSecondary)
                )
                .foregroundColor(.textPrimary)
            
            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(text.isEmpty ? .textTertiary : .anthropicCoral)
            }
            .disabled(text.isEmpty)
            .accessibilityLabel("Send message")
        }
        .padding(.top, 12)
    }
}

#Preview {
    ConversationView()
        .environmentObject(AppState.shared)
}
