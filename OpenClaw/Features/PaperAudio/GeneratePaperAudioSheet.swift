//
//  GeneratePaperAudioSheet.swift
//  OpenClaw
//
//  Sheet for configuring and starting paper-to-audiobook generation
//

import SwiftUI

struct GeneratePaperAudioSheet: View {
    let item: ZoteroItem
    let onGenerated: (() -> Void)?
    
    @StateObject private var viewModel = PaperAudioViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var existingJobs: [PaperAudioJob] = []
    @State private var isLoadingExisting = true
    
    init(item: ZoteroItem, onGenerated: (() -> Void)? = nil) {
        self.item = item
        self.onGenerated = onGenerated
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundDark.ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Paper info header
                        paperHeader
                        
                        // Existing jobs for this paper
                        if !existingJobs.isEmpty {
                            existingJobsSection
                        }
                        
                        // Mode picker
                        modeSection
                        
                        // Configuration toggles
                        configSection
                        
                        // Generate button
                        generateButton
                    }
                    .padding()
                }
                
                if viewModel.isGenerating {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(Color.anthropicCoral)
                        Text("Starting generation...")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
            .navigationTitle("Paper Audio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(Color.anthropicCoral)
                }
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "An error occurred")
            }
        }
        .presentationDetents([.large])
        .task {
            print("[GenerateSheet] .task triggered for item: \(item.key) — \(item.data.displayTitle)")
            existingJobs = await viewModel.loadJobs(forZoteroKey: item.key)
            print("[GenerateSheet] Loaded \(existingJobs.count) existing jobs for this item")
            isLoadingExisting = false
        }
    }
    
    // MARK: - Paper Header
    
    private var paperHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Item type badge
            HStack(spacing: 6) {
                Image(systemName: item.data.itemType.iconName)
                    .font(.caption)
                Text(item.data.itemType.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(Color.anthropicCoral)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.anthropicCoral.opacity(0.15))
            .clipShape(Capsule())
            
            Text(item.data.displayTitle)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(Color.textPrimary)
            
            if !item.data.authorsString.isEmpty {
                Text(item.data.authorsString)
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }
    
    // MARK: - Existing Jobs Section
    
    private var existingJobsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("EXISTING AUDIO")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Color.textSecondary)
                .tracking(0.5)
            
            VStack(spacing: 1) {
                ForEach(existingJobs) { job in
                    HStack(spacing: 12) {
                        Image(systemName: job.mode.iconName)
                            .foregroundStyle(Color.anthropicCoral)
                            .frame(width: 24)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(job.mode.displayName)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(Color.textPrimary)
                            
                            HStack(spacing: 4) {
                                Text(job.status.displayName)
                                    .font(.caption)
                                    .foregroundStyle(
                                        job.status == .completed ? Color.statusConnected :
                                        job.status == .failed ? Color.statusDisconnected :
                                        Color.textSecondary
                                    )
                                
                                if let duration = job.formattedDuration {
                                    Text("•")
                                        .font(.caption)
                                        .foregroundStyle(Color.textTertiary)
                                    Text(duration)
                                        .font(.caption)
                                        .foregroundStyle(Color.textTertiary)
                                }
                            }
                        }
                        
                        Spacer()
                        
                        if job.status.isActive {
                            ProgressView()
                                .scaleEffect(0.7)
                                .tint(Color.anthropicCoral)
                        } else if job.status == .completed {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.statusConnected)
                        } else if job.status == .failed {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(Color.statusDisconnected)
                        }
                    }
                    .padding()
                    .background(Color.surfacePrimary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    // MARK: - Mode Selection
    
    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LISTENING MODE")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Color.textSecondary)
                .tracking(0.5)
            
            VStack(spacing: 1) {
                ForEach(PaperListeningMode.allCases, id: \.self) { mode in
                    Button {
                        viewModel.applyDefaults(for: mode)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: mode.iconName)
                                .font(.title3)
                                .foregroundStyle(
                                    viewModel.selectedMode == mode
                                        ? Color.anthropicCoral
                                        : Color.textSecondary
                                )
                                .frame(width: 28)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(mode.displayName)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundStyle(Color.textPrimary)
                                    
                                    Text(mode.estimatedDuration)
                                        .font(.caption2)
                                        .foregroundStyle(Color.textTertiary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.surfaceElevated)
                                        .clipShape(Capsule())
                                }
                                
                                Text(mode.description)
                                    .font(.caption)
                                    .foregroundStyle(Color.textSecondary)
                                    .lineLimit(2)
                            }
                            
                            Spacer()
                            
                            if viewModel.selectedMode == mode {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.anthropicCoral)
                            } else {
                                Image(systemName: "circle")
                                    .foregroundStyle(Color.textTertiary)
                            }
                        }
                        .padding()
                        .background(
                            viewModel.selectedMode == mode
                                ? Color.anthropicCoral.opacity(0.08)
                                : Color.surfacePrimary
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    // MARK: - Configuration Toggles
    
    private var configSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("OPTIONS")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Color.textSecondary)
                .tracking(0.5)
            
            VStack(spacing: 1) {
                configToggle(
                    label: "Skip Equations",
                    description: "Summarize equations in plain language",
                    icon: "function",
                    isOn: $viewModel.skipEquations
                )
                configToggle(
                    label: "Skip Tables",
                    description: "Omit table narration",
                    icon: "tablecells",
                    isOn: $viewModel.skipTables
                )
                configToggle(
                    label: "Skip References",
                    description: "Remove citation markers and bibliography",
                    icon: "quote.closing",
                    isOn: $viewModel.skipReferences
                )
                configToggle(
                    label: "Summarize Figures",
                    description: "Briefly describe key figures",
                    icon: "chart.bar",
                    isOn: $viewModel.summarizeFigures
                )
                configToggle(
                    label: "Explain Jargon",
                    description: "Define technical terms once in simple language",
                    icon: "text.book.closed",
                    isOn: $viewModel.explainJargon
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    private func configToggle(label: String, description: String, icon: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(Color.anthropicCoral)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.subheadline)
                        .foregroundStyle(Color.textPrimary)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }
            }
        }
        .tint(Color.anthropicCoral)
        .padding()
        .background(Color.surfacePrimary)
    }
    
    // MARK: - Generate Button
    
    private var generateButton: some View {
        Button {
            Task {
                await viewModel.startGeneration(from: item)
                if viewModel.errorMessage == nil {
                    onGenerated?()
                    dismiss()
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "waveform.circle.fill")
                Text("Generate \(viewModel.selectedMode.displayName)")
            }
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.anthropicCoral)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(viewModel.isGenerating)
        .padding(.top, 8)
    }
}
