//
//  SettingsView.swift
//  OpenClaw
//
//  Configuration and settings interface
//

import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @EnvironmentObject private var pushManager: PushNotificationManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundDark.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 32) {
                        
                        // MARK: - Backend Section
                        SettingsSection(title: "Backend") {
                            SettingsTextField(
                                label: "OpenClaw Endpoint",
                                placeholder: "https://your-funnel.ts.net",
                                text: $viewModel.openClawEndpoint
                            )
                            
                            SettingsSecureField(
                                label: "Gateway Hook Token",
                                placeholder: "Optional - for notifications",
                                text: $viewModel.gatewayHookToken
                            )
                            
                            // Save Button for Backend
                            Button {
                                viewModel.saveBackendOnly()
                            } label: {
                                HStack(spacing: 8) {
                                    if viewModel.isSaved {
                                        Image(systemName: "checkmark")
                                            .fontWeight(.semibold)
                                    }
                                    Text(viewModel.isSaved ? "Saved" : "Save Backend")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    viewModel.canSaveBackend
                                        ? Color.anthropicCoral
                                        : Color.surfaceSecondary
                                )
                                .foregroundStyle(viewModel.canSaveBackend ? .white : Color.textSecondary)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .disabled(!viewModel.canSaveBackend)
                            .animation(.easeOut(duration: 0.2), value: viewModel.isSaved)
                        }
                        
                        // MARK: - Notifications Section
                        SettingsSection(title: "Notifications") {
                            switch pushManager.permissionStatus {
                            case .notDetermined:
                                Button {
                                    Task { await viewModel.requestNotificationPermission() }
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Enable Notifications")
                                            Text("Get alerts from OpenClaw")
                                                .font(.caption)
                                                .foregroundStyle(Color.textSecondary)
                                        }
                                        Spacer()
                                        Image(systemName: "bell.badge")
                                            .foregroundStyle(Color.anthropicCoral)
                                    }
                                    .padding(.vertical, 4)
                                }
                                
                            case .authorized, .provisional:
                                SettingsRow {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text("Notifications")
                                            Spacer()
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.green)
                                        }
                                        if let token = pushManager.deviceToken {
                                            Text("Token: \(String(token.prefix(8)))...")
                                                .font(.caption)
                                                .foregroundStyle(Color.textSecondary)
                                        }
                                    }
                                }
                                
                            case .denied:
                                Button {
                                    viewModel.openSystemSettings()
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Notifications Disabled")
                                            Text("Tap to open Settings")
                                                .font(.caption)
                                                .foregroundStyle(Color.textSecondary)
                                        }
                                        Spacer()
                                        Image(systemName: "gear")
                                            .foregroundStyle(Color.textSecondary)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                            
                            if pushManager.permissionStatus == .authorized || pushManager.permissionStatus == .provisional {
                                SettingsRow {
                                    Text("Heartbeat Alerts")
                                    Spacer()
                                    Toggle("", isOn: $viewModel.notificationsEnabled)
                                        .labelsHidden()
                                        .tint(.anthropicCoral)
                                }
                            }
                        }
                        
                        // MARK: - ElevenLabs Section
                        SettingsSection(title: "ElevenLabs") {
                            SettingsTextField(
                                label: "Agent ID",
                                placeholder: "Your agent ID",
                                text: $viewModel.agentId
                            )
                            
                            SettingsRow {
                                Text("Private Agent")
                                Spacer()
                                Toggle("", isOn: $viewModel.isPrivateAgent)
                                    .labelsHidden()
                                    .tint(.anthropicCoral)
                            }
                            
                            if viewModel.isPrivateAgent {
                                SettingsSecureField(
                                    label: "API Key",
                                    placeholder: "Your API key",
                                    text: $viewModel.apiKey
                                )
                            }
                            
                            // Save Button
                            Button {
                                viewModel.save()
                            } label: {
                                HStack(spacing: 8) {
                                    if viewModel.isSaved {
                                        Image(systemName: "checkmark")
                                            .fontWeight(.semibold)
                                    }
                                    Text(viewModel.isSaved ? "Saved" : "Save")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    viewModel.canSave 
                                        ? Color.anthropicCoral 
                                        : Color.surfaceSecondary
                                )
                                .foregroundStyle(viewModel.canSave ? .white : Color.textSecondary)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .disabled(!viewModel.canSave)
                            .animation(.easeOut(duration: 0.2), value: viewModel.isSaved)
                        }
                        .animation(.easeOut(duration: 0.2), value: viewModel.isPrivateAgent)
                        
                        // MARK: - Test Connection
                        SettingsSection(title: "Connection") {
                            Button {
                                Task { await viewModel.testConnection() }
                            } label: {
                                HStack {
                                    Text("Test Connection")
                                    Spacer()
                                    Group {
                                        if viewModel.isTestingConnection {
                                            ProgressView()
                                                .tint(.white)
                                        } else if let result = viewModel.connectionTestResult {
                                            switch result {
                                            case .success:
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(.green)
                                            case .failure:
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundStyle(.red)
                                            }
                                        } else {
                                            Image(systemName: "chevron.right")
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .disabled(viewModel.agentId.isEmpty)
                            
                            if case .failure(let message) = viewModel.connectionTestResult {
                                Text(message)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                        
                        // MARK: - Preferences
                        SettingsSection(title: "Preferences") {
                            SettingsRow {
                                Text("Auto-start Microphone")
                                Spacer()
                                Toggle("", isOn: $viewModel.autoStartMic)
                                    .labelsHidden()
                                    .tint(.anthropicCoral)
                            }
                            
                            SettingsRow {
                                Text("Show Transcript")
                                Spacer()
                                Toggle("", isOn: $viewModel.showTranscript)
                                    .labelsHidden()
                                    .tint(.anthropicCoral)
                            }
                            
                            SettingsRow {
                                Text("Haptic Feedback")
                                Spacer()
                                Toggle("", isOn: $viewModel.hapticFeedback)
                                    .labelsHidden()
                                    .tint(.anthropicCoral)
                            }
                        }
                        
                        // MARK: - About
                        SettingsSection(title: "About") {
                            SettingsInfoRow(label: "Backend", value: "DGX Spark")
                            SettingsInfoRow(label: "Voice", value: "ElevenLabs")
                            SettingsInfoRow(label: "Transport", value: "WebRTC")
                            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                                SettingsInfoRow(label: "Version", value: version)
                            }
                        }
                        
                        // MARK: - Reset
                        Button(role: .destructive) {
                            viewModel.clearCredentials()
                        } label: {
                            Text("Clear All Credentials")
                                .fontWeight(.medium)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.statusDisconnected.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.statusDisconnected)
                        
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.backgroundDark, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.anthropicCoral)
                }
            }
            .alert("Save Error", isPresented: $viewModel.showSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.saveError ?? "An unknown error occurred")
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Section Container

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Color.textSecondary)
                .tracking(0.5)
                .padding(.leading, 4)
            
            VStack(spacing: 1) {
                content
            }
            .background(Color.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

// MARK: - Row Container

struct SettingsRow<Content: View>: View {
    @ViewBuilder let content: Content
    
    var body: some View {
        HStack {
            content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.surfacePrimary)
    }
}

// MARK: - Text Field

struct SettingsTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(Color.textSecondary)
            
            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(Color.textPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.surfacePrimary)
    }
}

// MARK: - Secure Field

struct SettingsSecureField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    @State private var isSecure = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(Color.textSecondary)
            
            HStack {
                Group {
                    if isSecure {
                        SecureField(placeholder, text: $text)
                    } else {
                        TextField(placeholder, text: $text)
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(Color.textPrimary)
                
                Button {
                    isSecure.toggle()
                } label: {
                    Image(systemName: isSecure ? "eye.slash" : "eye")
                        .foregroundStyle(Color.textSecondary)
                        .font(.callout)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.surfacePrimary)
    }
}

// MARK: - Info Row

struct SettingsInfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(value)
                .foregroundStyle(Color.textPrimary)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.surfacePrimary)
    }
}

#Preview {
    SettingsView()
}
