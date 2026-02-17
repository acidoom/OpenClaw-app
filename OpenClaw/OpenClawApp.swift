//
//  OpenClawApp.swift
//  OpenClaw
//
//  Created by Antares Gryczan on 5/2/26.
//

import SwiftUI
import UIKit

@main
struct OpenClawApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared
    @StateObject private var pushManager = PushNotificationManager.shared
    
    var body: some Scene {
        WindowGroup {
            Group {
                if appState.isConfigured {
                    MainTabView()
                } else {
                    OnboardingView()
                }
            }
            .environmentObject(appState)
            .environmentObject(pushManager)
            .task {
                // Check notification permission status on launch
                await pushManager.checkPermissionStatus()
                appState.updateNotificationPermission(pushManager.permissionStatus)
            }
            .onChange(of: pushManager.permissionStatus) { _, newValue in
                appState.updateNotificationPermission(newValue)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                // Clear badge when app becomes active
                Task {
                    await pushManager.clearBadge()
                }
            }
        }
    }
}

// MARK: - Onboarding View

struct OnboardingView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundGradient
                    .ignoresSafeArea()
                
                VStack(spacing: 32) {
                    Spacer()
                    
                    // App Icon / Logo
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [.orbCyan, .orbBlue, .orbBlue.opacity(0.3)],
                                    center: .center,
                                    startRadius: 10,
                                    endRadius: 60
                                )
                            )
                            .frame(width: 120, height: 120)
                            .shadow(color: .orbBlue.opacity(0.5), radius: 20)
                        
                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.white)
                    }
                    
                    VStack(spacing: 8) {
                        Text("OpenClaw")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Text("Voice Assistant")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Configuration Form
                    VStack(spacing: 16) {
                        Text("Configure Your Agent")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        VStack(spacing: 12) {
                            TextField("ElevenLabs Agent ID", text: $viewModel.agentId)
                                .textFieldStyle(.plain)
                                .padding()
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(12)
                                .foregroundColor(.white)
                            
                            Toggle("Private Agent (requires API key)", isOn: $viewModel.isPrivateAgent)
                                .foregroundColor(.white)
                                .padding(.horizontal, 4)
                            
                            if viewModel.isPrivateAgent {
                                SecureField("ElevenLabs API Key", text: $viewModel.apiKey)
                                    .textFieldStyle(.plain)
                                    .padding()
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(12)
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(.horizontal)
                        
                        Button {
                            viewModel.save()
                        } label: {
                            Text("Get Started")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(viewModel.canSave ? Color.orbBlue : Color.gray)
                                )
                        }
                        .disabled(!viewModel.canSave)
                        .padding(.horizontal)
                    }
                    .padding(.vertical, 24)
                    .background(
                        RoundedRectangle(cornerRadius: 24)
                            .fill(Color.black.opacity(0.3))
                    )
                    .padding(.horizontal)
                    
                    Spacer()
                }
            }
            .alert("Error", isPresented: $viewModel.showSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.saveError ?? "An unknown error occurred")
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Main Tab View

struct MainTabView: View {
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        TabView(selection: $appState.selectedTab) {
            ConversationView()
                .tabItem {
                    Label(AppTab.conversation.title, systemImage: AppTab.conversation.iconName)
                }
                .tag(AppTab.conversation)
            
            TodoListView()
                .tabItem {
                    Label(AppTab.todoList.title, systemImage: AppTab.todoList.iconName)
                }
                .tag(AppTab.todoList)
            
            ResearchLabView()
                .tabItem {
                    Label(AppTab.researchLab.title, systemImage: AppTab.researchLab.iconName)
                }
                .tag(AppTab.researchLab)
        }
        .tint(Color.anthropicCoral)
        .onChange(of: appState.pendingAction) { _, action in
            handleDeepLinkAction(action)
        }
    }
    
    private func handleDeepLinkAction(_ action: DeepLinkAction?) {
        guard let action = action else { return }
        
        switch action {
        case .openResearchLab:
            appState.selectedTab = .researchLab
            appState.clearPendingAction()
        case .openResearchProject(let projectId):
            appState.selectedTab = .researchLab
            appState.selectedResearchProjectId = projectId
            appState.clearPendingAction()
        default:
            break // Other actions handled by ConversationView
        }
    }
}
