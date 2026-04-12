//
//  AdaptiveRootView.swift
//  OpenClaw
//
//  Adaptive root view: TabView on iPhone, NavigationSplitView on iPad
//

import SwiftUI

struct AdaptiveRootView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var playerManager: AudioPlayerManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    var body: some View {
        if horizontalSizeClass == .regular {
            iPadLayout
        } else {
            iPhoneTabView
        }
    }
    
    // MARK: - iPhone Layout (existing TabView, unchanged)
    
    private var iPhoneTabView: some View {
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
            
            ZoteroLibraryView()
                .tabItem {
                    Label(AppTab.zotero.title, systemImage: AppTab.zotero.iconName)
                }
                .tag(AppTab.zotero)
            
            AudiobooksView()
                .tabItem {
                    Label(AppTab.audiobooks.title, systemImage: AppTab.audiobooks.iconName)
                }
                .tag(AppTab.audiobooks)
            
            PodcastsView()
                .tabItem {
                    Label(AppTab.podcasts.title, systemImage: AppTab.podcasts.iconName)
                }
                .tag(AppTab.podcasts)
            
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
    
    // MARK: - iPad Layout
    
    private var iPadLayout: some View {
        NavigationSplitView(columnVisibility: $appState.sidebarVisibility) {
            SidebarView()
        } detail: {
            iPadDetailWithPlayer
        }
        .navigationSplitViewStyle(.balanced)
        .tint(Color.anthropicCoral)
        .onChange(of: appState.pendingAction) { _, action in
            handleDeepLinkAction(action)
        }
    }
    
    private var iPadDetailWithPlayer: some View {
        GeometryReader { geo in
            let showSidebarPlayer = geo.size.width > 900 && playerManager.hasActiveSession && appState.isSidebarPlayerExpanded
            
            HStack(spacing: 0) {
                // Main content
                detailContent
                    .frame(maxWidth: .infinity)
                
                // Persistent sidebar player in wide layout
                if showSidebarPlayer {
                    Divider()
                    SidebarPlayerView()
                        .frame(width: 320)
                        .transition(.move(edge: .trailing))
                }
            }
            .overlay(alignment: .bottom) {
                // Bottom mini player when sidebar player is not shown
                if playerManager.hasActiveSession && !showSidebarPlayer {
                    MiniPlayerView()
                }
            }
            .animation(.easeInOut(duration: 0.3), value: showSidebarPlayer)
        }
    }
    
    @ViewBuilder
    private var detailContent: some View {
        switch appState.selectedTab {
        case .conversation:
            ConversationView()
        case .todoList:
            TodoListView()
        case .zotero:
            ZoteroLibraryView()
        case .audiobooks:
            AudiobooksView()
        case .podcasts:
            PodcastsView()
        case .researchLab:
            ResearchLabView()
        }
    }
    
    // MARK: - Deep Link Handling
    
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
        case .openTodoList:
            appState.selectedTab = .todoList
            appState.clearPendingAction()
        case .openAudiobook:
            appState.selectedTab = .audiobooks
            appState.clearPendingAction()
        case .openPodcast:
            appState.selectedTab = .podcasts
            appState.clearPendingAction()
        default:
            break
        }
    }
}
