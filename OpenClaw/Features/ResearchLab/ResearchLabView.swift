//
//  ResearchLabView.swift
//  OpenClaw
//
//  Main view for Research Lab feature
//

import SwiftUI

struct ResearchLabView: View {
    @StateObject private var viewModel = ResearchLabViewModel()
    @State private var showingFilters = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundGradient
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Status filter chips
                    StatusFilterBar(
                        selectedStatus: $viewModel.selectedStatus,
                        counts: viewModel.projectCounts
                    )
                    
                    // Main content
                    if viewModel.isLoading && viewModel.projects.isEmpty {
                        LoadingView()
                    } else if viewModel.filteredProjects.isEmpty {
                        EmptyStateView(
                            hasProjects: !viewModel.projects.isEmpty,
                            selectedStatus: viewModel.selectedStatus
                        ) {
                            viewModel.showCreateSheet = true
                        }
                    } else {
                        ProjectListView(
                            projects: viewModel.filteredProjects,
                            onSelect: { viewModel.selectProject($0) },
                            onDelete: { project in
                                Task { await viewModel.deleteProject(project) }
                            }
                        )
                    }
                }
            }
            .navigationTitle("Research Lab")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $viewModel.searchQuery, prompt: "Search projects")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.showCreateSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Color.anthropicCoral)
                    }
                }
                
                ToolbarItem(placement: .topBarLeading) {
                    if viewModel.isOffline {
                        Label("Offline", systemImage: "wifi.slash")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .refreshable {
                await viewModel.refreshProjects()
            }
            .sheet(isPresented: $viewModel.showCreateSheet) {
                CreateProjectSheet(viewModel: viewModel)
            }
            .sheet(item: $viewModel.selectedProject) { project in
                ProjectDetailView(project: project, viewModel: viewModel)
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "An unknown error occurred")
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Status Filter Bar

struct StatusFilterBar: View {
    @Binding var selectedStatus: ProjectStatus?
    let counts: [ProjectStatus: Int]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(
                    title: "All",
                    count: counts.values.reduce(0, +),
                    isSelected: selectedStatus == nil
                ) {
                    selectedStatus = nil
                }
                
                ForEach(ProjectStatus.allCases.filter { $0 != .archived }, id: \.self) { status in
                    FilterChip(
                        title: status.displayName,
                        count: counts[status] ?? 0,
                        isSelected: selectedStatus == status,
                        iconName: status.iconName
                    ) {
                        selectedStatus = selectedStatus == status ? nil : status
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .background(Color.surfacePrimary.opacity(0.5))
    }
}

struct FilterChip: View {
    let title: String
    let count: Int
    let isSelected: Bool
    var iconName: String? = nil
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon = iconName {
                    Image(systemName: icon)
                        .font(.caption)
                }
                Text(title)
                    .font(.subheadline)
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.white.opacity(0.2) : Color.textTertiary.opacity(0.3))
                        )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? Color.anthropicCoral : Color.surfaceSecondary)
            )
            .foregroundStyle(isSelected ? .white : Color.textSecondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Project List View

struct ProjectListView: View {
    let projects: [ResearchProject]
    let onSelect: (ResearchProject) -> Void
    let onDelete: (ResearchProject) -> Void
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(projects) { project in
                    ProjectCard(project: project)
                        .onTapGesture { onSelect(project) }
                        .contextMenu {
                            Button(role: .destructive) {
                                onDelete(project)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
            .padding()
        }
    }
}

// MARK: - Project Card

struct ProjectCard: View {
    let project: ResearchProject
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: project.source.iconName)
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                
                Text(project.source.displayName)
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                
                Spacer()
                
                StatusBadge(status: project.status)
            }
            
            // Title
            Text(project.title)
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(2)
            
            // Description or paper info
            if let paperTitle = project.paperTitle {
                Text(paperTitle)
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
            } else if !project.projectDescription.isEmpty {
                Text(project.projectDescription)
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
            }
            
            // Footer
            HStack {
                if project.hasExperimentPlan {
                    Label("Plan ready", systemImage: "list.bullet.clipboard")
                        .font(.caption2)
                        .foregroundStyle(Color.statusConnected)
                }
                
                if project.background != nil {
                    Label("Background", systemImage: "doc.text")
                        .font(.caption2)
                        .foregroundStyle(Color.anthropicOrange)
                }
                
                Spacer()
                
                Text(project.updatedAt.formatted(.relative(presentation: .named)))
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.surfacePrimary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.cardBorder, lineWidth: 1)
        )
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let status: ProjectStatus
    
    var statusColor: Color {
        switch status {
        case .idea: return .yellow
        case .researching: return .blue
        case .planned: return .purple
        case .inProgress: return .orange
        case .completed: return .green
        case .archived: return .gray
        }
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.iconName)
                .font(.caption2)
            Text(status.displayName)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(statusColor.opacity(0.2))
        )
        .foregroundStyle(statusColor)
    }
}

// MARK: - Empty State View

struct EmptyStateView: View {
    let hasProjects: Bool
    let selectedStatus: ProjectStatus?
    let onCreate: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: hasProjects ? "line.3.horizontal.decrease.circle" : "flask")
                .font(.system(size: 60))
                .foregroundStyle(Color.textTertiary)
            
            if hasProjects {
                Text("No projects match filter")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                
                if let status = selectedStatus {
                    Text("No \(status.displayName.lowercased()) projects found")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                }
            } else {
                Text("Start Your Research")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                
                Text("Capture ideas, import papers, and plan experiments")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                
                Button(action: onCreate) {
                    Label("Create Project", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.anthropicCoral)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
                .padding(.top, 8)
            }
            
            Spacer()
        }
    }
}

// MARK: - Loading View

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
                .tint(Color.anthropicCoral)
            Text("Loading projects...")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
            Spacer()
        }
    }
}

// MARK: - Create Project Sheet

struct CreateProjectSheet: View {
    @ObservedObject var viewModel: ResearchLabViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var titleFocused: Bool
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundDark
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Source selection
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Source")
                                .font(.headline)
                                .foregroundStyle(Color.textPrimary)
                            
                            HStack(spacing: 12) {
                                ForEach([ProjectSource.manual, .paper, .voice], id: \.self) { source in
                                    SourceButton(
                                        source: source,
                                        isSelected: viewModel.newProjectSource == source
                                    ) {
                                        viewModel.newProjectSource = source
                                    }
                                }
                            }
                        }
                        
                        // Paper URL (if paper source)
                        if viewModel.newProjectSource == .paper {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Paper URL")
                                    .font(.headline)
                                    .foregroundStyle(Color.textPrimary)
                                
                                TextField("arXiv, DOI, or PDF link", text: $viewModel.paperUrlInput)
                                    .textFieldStyle(.plain)
                                    .padding()
                                    .background(Color.inputBackground)
                                    .cornerRadius(12)
                                    .foregroundStyle(Color.textPrimary)
                                
                                Text("Supports arXiv, DOI, Semantic Scholar, and direct PDF links")
                                    .font(.caption)
                                    .foregroundStyle(Color.textTertiary)
                            }
                        }
                        
                        // Title
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Title")
                                .font(.headline)
                                .foregroundStyle(Color.textPrimary)
                            
                            TextField("Project title", text: $viewModel.newProjectTitle)
                                .textFieldStyle(.plain)
                                .padding()
                                .background(Color.inputBackground)
                                .cornerRadius(12)
                                .foregroundStyle(Color.textPrimary)
                                .focused($titleFocused)
                        }
                        
                        // Description
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Description")
                                .font(.headline)
                                .foregroundStyle(Color.textPrimary)
                            
                            TextEditor(text: $viewModel.newProjectDescription)
                                .scrollContentBackground(.hidden)
                                .padding()
                                .frame(minHeight: 120)
                                .background(Color.inputBackground)
                                .cornerRadius(12)
                                .foregroundStyle(Color.textPrimary)
                        }
                        
                        Spacer(minLength: 40)
                    }
                    .padding()
                }
            }
            .navigationTitle("New Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.resetCreateForm()
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            await viewModel.createProject()
                        }
                    }
                    .disabled(!viewModel.canCreateProject)
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                titleFocused = true
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

struct SourceButton: View {
    let source: ProjectSource
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: source.iconName)
                    .font(.title2)
                Text(source.displayName)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.anthropicCoral.opacity(0.2) : Color.surfaceSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Color.anthropicCoral : Color.clear, lineWidth: 2)
            )
            .foregroundStyle(isSelected ? Color.anthropicCoral : Color.textSecondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    ResearchLabView()
}
