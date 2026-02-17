//
//  ResearchLabViewModel.swift
//  OpenClaw
//
//  ViewModel for Research Lab feature
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class ResearchLabViewModel: ObservableObject {
    
    // MARK: - Published State
    
    @Published var projects: [ResearchProject] = []
    @Published var selectedProject: ResearchProject?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showError = false
    
    // Filters
    @Published var selectedStatus: ProjectStatus?
    @Published var searchQuery = ""
    
    // Creation
    @Published var showCreateSheet = false
    @Published var newProjectTitle = ""
    @Published var newProjectDescription = ""
    @Published var newProjectSource: ProjectSource = .manual
    @Published var paperUrlInput = ""
    
    // Statistics
    @Published var projectCounts: [ProjectStatus: Int] = [:]
    
    // MARK: - Dependencies
    
    private let storage = ResearchStorageService.shared
    private let networkMonitor = NetworkMonitor.shared
    
    // MARK: - Computed Properties
    
    var filteredProjects: [ResearchProject] {
        var result = projects
        
        // Filter by status
        if let status = selectedStatus {
            result = result.filter { $0.status == status }
        }
        
        // Filter by search query
        if !searchQuery.isEmpty {
            let query = searchQuery.lowercased()
            result = result.filter { project in
                project.title.lowercased().contains(query) ||
                project.projectDescription.lowercased().contains(query) ||
                (project.paperTitle?.lowercased().contains(query) ?? false)
            }
        }
        
        return result
    }
    
    var totalProjectCount: Int {
        projectCounts.values.reduce(0, +)
    }
    
    var canCreateProject: Bool {
        !newProjectTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var isOffline: Bool {
        !networkMonitor.isConnected
    }
    
    // MARK: - Initialization
    
    init() {
        Task {
            await loadProjects()
        }
    }
    
    // MARK: - Data Loading
    
    func loadProjects() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            projects = try storage.fetchAllProjects()
            projectCounts = try storage.getProjectCounts()
        } catch {
            showError(message: "Failed to load projects: \(error.localizedDescription)")
        }
    }
    
    func refreshProjects() async {
        await loadProjects()
    }
    
    // MARK: - Project CRUD
    
    func createProject() async {
        guard canCreateProject else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            let project = try storage.createProject(
                title: newProjectTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                description: newProjectDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                source: newProjectSource
            )
            
            // If paper URL provided, set it up for fetching
            if !paperUrlInput.isEmpty && newProjectSource == .paper {
                project.paperUrl = paperUrlInput
                project.status = .researching
                try storage.updateProject(project)
                
                // Queue paper fetching (would be done by PaperService)
                // TODO: Implement paper fetching
            }
            
            // Reset form
            resetCreateForm()
            showCreateSheet = false
            
            // Reload
            await loadProjects()
            
            // Select new project
            selectedProject = project
            
        } catch {
            showError(message: "Failed to create project: \(error.localizedDescription)")
        }
    }
    
    func deleteProject(_ project: ResearchProject) async {
        do {
            try storage.deleteProject(project)
            
            if selectedProject?.id == project.id {
                selectedProject = nil
            }
            
            await loadProjects()
        } catch {
            showError(message: "Failed to delete project: \(error.localizedDescription)")
        }
    }
    
    func updateProjectStatus(_ project: ResearchProject, to status: ProjectStatus) async {
        project.updateStatus(status)
        
        do {
            try storage.updateProject(project)
            await loadProjects()
        } catch {
            showError(message: "Failed to update status: \(error.localizedDescription)")
        }
    }
    
    func addNote(to project: ResearchProject, content: String) async {
        project.addNote(content, source: .user)
        
        do {
            try storage.updateProject(project)
        } catch {
            showError(message: "Failed to add note: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Voice Input
    
    func createFromVoiceInput(_ transcription: String) async {
        newProjectTitle = extractTitle(from: transcription)
        newProjectDescription = transcription
        newProjectSource = .voice
        
        await createProject()
    }
    
    private func extractTitle(from text: String) -> String {
        // Take first sentence or first 50 characters as title
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
        if let firstSentence = sentences.first, !firstSentence.isEmpty {
            let trimmed = firstSentence.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count <= 100 {
                return trimmed
            }
            return String(trimmed.prefix(97)) + "..."
        }
        
        if text.count <= 50 {
            return text
        }
        return String(text.prefix(47)) + "..."
    }
    
    // MARK: - Paper Import
    
    func importFromPaperUrl(_ urlString: String) async {
        let sourceType = PaperSourceType.detect(from: urlString)
        
        switch sourceType {
        case .unknown:
            showError(message: "Could not detect paper source from URL. Supported: arXiv, DOI, Semantic Scholar, direct PDF.")
            return
        default:
            break
        }
        
        // Create project with paper source
        newProjectTitle = "Importing paper..."
        newProjectDescription = ""
        newProjectSource = .paper
        paperUrlInput = urlString
        
        await createProject()
        
        // Paper metadata fetching would be triggered by PaperService
        // TODO: Implement PaperService integration
    }
    
    // MARK: - Helpers
    
    func resetCreateForm() {
        newProjectTitle = ""
        newProjectDescription = ""
        newProjectSource = .manual
        paperUrlInput = ""
    }
    
    func selectProject(_ project: ResearchProject) {
        selectedProject = project
    }
    
    func clearSelection() {
        selectedProject = nil
    }
    
    func setStatusFilter(_ status: ProjectStatus?) {
        selectedStatus = status
    }
    
    private func showError(message: String) {
        errorMessage = message
        showError = true
    }
}

// MARK: - Preview Helper

extension ResearchLabViewModel {
    static var preview: ResearchLabViewModel {
        let vm = ResearchLabViewModel()
        return vm
    }
}
