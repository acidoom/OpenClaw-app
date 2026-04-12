//
//  SidebarView.swift
//  OpenClaw
//
//  iPad sidebar navigation list
//

import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showingSettings = false
    
    private var sidebarSelection: Binding<AppTab?> {
        Binding(
            get: { appState.selectedTab },
            set: { if let tab = $0 { appState.selectedTab = tab } }
        )
    }
    
    var body: some View {
        List(selection: sidebarSelection) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Label(tab.title, systemImage: tab.iconName)
                    .tag(tab)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("OpenClaw")
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                Button {
                    showingSettings = true
                } label: {
                    Label("Settings", systemImage: "gear")
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
