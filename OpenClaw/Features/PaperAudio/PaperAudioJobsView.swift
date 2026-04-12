//
//  PaperAudioJobsView.swift
//  OpenClaw
//
//  List view showing all paper audio generation jobs and their status
//

import SwiftUI

struct PaperAudioJobsView: View {
    @StateObject private var viewModel = PaperAudioViewModel()
    @EnvironmentObject private var playerManager: AudioPlayerManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedJob: PaperAudioJob?
    @State private var showDeleteConfirmation = false
    @State private var jobToDelete: PaperAudioJob?
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundDark.ignoresSafeArea()
                
                if viewModel.isLoading && viewModel.jobs.isEmpty {
                    loadingView
                } else if viewModel.jobs.isEmpty {
                    emptyView
                } else {
                    jobsList
                }
            }
            .navigationTitle("Paper Audio")
            .navigationBarTitleDisplayMode(.large)
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
            .sheet(item: $selectedJob) { job in
                PaperAudioPlayerView(job: job)
                    .environmentObject(playerManager)
            }
            .alert("Delete Audio", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    if let job = jobToDelete {
                        Task { await viewModel.deleteJob(job) }
                    }
                }
            } message: {
                Text("Delete this paper audio? This cannot be undone.")
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "An error occurred")
            }
        }
        .task {
            print("[PaperAudioJobsView] .task triggered — loading jobs")
            await viewModel.loadJobs()
        }
        .onAppear {
            print("[PaperAudioJobsView] onAppear")
        }
        .onDisappear {
            viewModel.stopPolling()
        }
    }
    
    // MARK: - Loading
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(Color.anthropicCoral)
                .scaleEffect(1.2)
            Text("Loading paper audio...")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
        }
    }
    
    // MARK: - Empty State
    
    private var emptyView: some View {
        VStack(spacing: 24) {
            if let error = viewModel.errorMessage {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 60))
                    .foregroundStyle(Color.statusDisconnected)
                
                Text("Failed to Load")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(Color.statusDisconnected)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .textSelection(.enabled)
                
                Button {
                    Task { await viewModel.loadJobs() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                        Text("Retry")
                    }
                    .fontWeight(.semibold)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.anthropicCoral)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                }
            } else {
                Image(systemName: "waveform.circle")
                    .font(.system(size: 60))
                    .foregroundStyle(Color.textSecondary)
                
                Text("No Paper Audio Yet")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                
                Text("Select a paper from your Zotero library and generate an audiobook version.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }
    
    // MARK: - Jobs List
    
    private var jobsList: some View {
        List {
            // Active jobs
            if !viewModel.activeJobs.isEmpty {
                Section {
                    ForEach(viewModel.activeJobs) { job in
                        PaperAudioJobRow(job: job)
                            .listRowBackground(Color.surfacePrimary)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task { await viewModel.cancelJob(job) }
                                } label: {
                                    Label("Cancel", systemImage: "xmark.circle")
                                }
                            }
                    }
                } header: {
                    Text("IN PROGRESS")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            
            // Completed jobs
            if !viewModel.completedJobs.isEmpty {
                Section {
                    ForEach(viewModel.completedJobs) { job in
                        PaperAudioJobRow(job: job)
                            .listRowBackground(Color.surfacePrimary)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedJob = job
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    jobToDelete = job
                                    showDeleteConfirmation = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                } header: {
                    Text("READY TO LISTEN")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            
            // Failed jobs
            if !viewModel.failedJobs.isEmpty {
                Section {
                    ForEach(viewModel.failedJobs) { job in
                        PaperAudioJobRow(job: job)
                            .listRowBackground(Color.surfacePrimary)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    jobToDelete = job
                                    showDeleteConfirmation = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    Task { await viewModel.retryJob(job) }
                                } label: {
                                    Label("Retry", systemImage: "arrow.clockwise")
                                }
                                .tint(Color.anthropicCoral)
                            }
                    }
                } header: {
                    Text("FAILED")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable {
            await viewModel.loadJobs()
        }
    }
}

// MARK: - Job Row

struct PaperAudioJobRow: View {
    let job: PaperAudioJob
    
    var body: some View {
        HStack(spacing: 12) {
            // Mode icon
            ZStack {
                Circle()
                    .fill(Color.anthropicCoral.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: job.mode.iconName)
                    .foregroundStyle(Color.anthropicCoral)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(job.paperTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                
                HStack(spacing: 6) {
                    // Mode badge
                    Text(job.mode.displayName)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.anthropicCoral)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.anthropicCoral.opacity(0.15))
                        .clipShape(Capsule())
                    
                    // Status or duration
                    if job.status == .completed, let duration = job.formattedDuration {
                        Text(duration)
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                    } else if job.status == .failed {
                        Text(job.errorMessage ?? "Failed")
                            .font(.caption)
                            .foregroundStyle(Color.statusDisconnected)
                            .lineLimit(1)
                    } else {
                        Text(job.status.displayName)
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                
                // Progress bar for active jobs
                if job.status.isActive, let progress = job.progress {
                    ProgressView(value: progress)
                        .tint(Color.anthropicCoral)
                        .scaleEffect(y: 0.6)
                }
            }
            
            Spacer()
            
            // Status indicator
            if job.status == .completed {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.anthropicCoral)
            } else if job.status.isActive {
                VStack {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(Color.anthropicCoral)
                    if let progress = job.progress {
                        Text("\(Int(progress * 100))%")
                            .font(.caption2)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            } else if job.status == .failed {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(Color.statusDisconnected)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Identifiable conformance for sheet

extension PaperAudioJob: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
