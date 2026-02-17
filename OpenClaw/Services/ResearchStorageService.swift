//
//  ResearchStorageService.swift
//  OpenClaw
//
//  Persistence layer for Research Lab using SwiftData
//

import Foundation
import SwiftData
import Combine

@MainActor
final class ResearchStorageService: ObservableObject {
    static let shared = ResearchStorageService()
    
    private var modelContainer: ModelContainer?
    private var modelContext: ModelContext?
    
    @Published private(set) var isInitialized = false
    @Published private(set) var initializationError: String?
    
    private init() {
        setupContainer()
    }
    
    // MARK: - Setup
    
    private func setupContainer() {
        do {
            let schema = Schema([ResearchProject.self])
            let config = ModelConfiguration(
                "ResearchLab",
                schema: schema,
                isStoredInMemoryOnly: false,
                allowsSave: true
            )
            
            modelContainer = try ModelContainer(for: schema, configurations: [config])
            modelContext = modelContainer?.mainContext
            isInitialized = true
            
            print("[ResearchStorage] Initialized successfully")
        } catch {
            initializationError = error.localizedDescription
            print("[ResearchStorage] Failed to initialize: \(error)")
        }
    }
    
    // MARK: - CRUD Operations
    
    func createProject(
        title: String,
        description: String = "",
        source: ProjectSource = .manual
    ) throws -> ResearchProject {
        guard let context = modelContext else {
            throw ResearchStorageError.notInitialized
        }
        
        let project = ResearchProject(
            title: title,
            description: description,
            source: source
        )
        
        context.insert(project)
        try context.save()
        
        print("[ResearchStorage] Created project: \(project.id)")
        return project
    }
    
    func fetchAllProjects() throws -> [ResearchProject] {
        guard let context = modelContext else {
            throw ResearchStorageError.notInitialized
        }
        
        let descriptor = FetchDescriptor<ResearchProject>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        
        return try context.fetch(descriptor)
    }
    
    func fetchProjects(status: ProjectStatus? = nil, limit: Int? = nil) throws -> [ResearchProject] {
        guard let context = modelContext else {
            throw ResearchStorageError.notInitialized
        }
        
        var descriptor = FetchDescriptor<ResearchProject>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        
        if let status = status {
            descriptor.predicate = #Predicate<ResearchProject> { project in
                project.status == status
            }
        }
        
        if let limit = limit {
            descriptor.fetchLimit = limit
        }
        
        return try context.fetch(descriptor)
    }
    
    func fetchProject(id: UUID) throws -> ResearchProject? {
        guard let context = modelContext else {
            throw ResearchStorageError.notInitialized
        }
        
        let descriptor = FetchDescriptor<ResearchProject>(
            predicate: #Predicate<ResearchProject> { project in
                project.id == id
            }
        )
        
        return try context.fetch(descriptor).first
    }
    
    func updateProject(_ project: ResearchProject) throws {
        guard let context = modelContext else {
            throw ResearchStorageError.notInitialized
        }
        
        project.updatedAt = Date()
        try context.save()
        
        print("[ResearchStorage] Updated project: \(project.id)")
    }
    
    func deleteProject(_ project: ResearchProject) throws {
        guard let context = modelContext else {
            throw ResearchStorageError.notInitialized
        }
        
        // Delete associated PDF if exists
        if let pdfPath = project.pdfLocalPath {
            deletePDF(at: pdfPath)
        }
        
        context.delete(project)
        try context.save()
        
        print("[ResearchStorage] Deleted project: \(project.id)")
    }
    
    func deleteProject(id: UUID) throws {
        guard let project = try fetchProject(id: id) else {
            throw ResearchStorageError.projectNotFound
        }
        try deleteProject(project)
    }
    
    // MARK: - Search
    
    func searchProjects(query: String) throws -> [ResearchProject] {
        guard let context = modelContext else {
            throw ResearchStorageError.notInitialized
        }
        
        let lowercasedQuery = query.lowercased()
        
        let descriptor = FetchDescriptor<ResearchProject>(
            predicate: #Predicate<ResearchProject> { project in
                project.title.localizedStandardContains(lowercasedQuery) ||
                project.projectDescription.localizedStandardContains(lowercasedQuery) ||
                (project.paperTitle?.localizedStandardContains(lowercasedQuery) ?? false)
            },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        
        return try context.fetch(descriptor)
    }
    
    // MARK: - PDF Management
    
    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    private var pdfsDirectory: URL {
        documentsDirectory.appendingPathComponent("ResearchPDFs", isDirectory: true)
    }
    
    func savePDF(data: Data, for projectId: UUID) throws -> String {
        // Ensure PDFs directory exists
        try FileManager.default.createDirectory(
            at: pdfsDirectory,
            withIntermediateDirectories: true
        )
        
        let filename = "\(projectId.uuidString).pdf"
        let fileURL = pdfsDirectory.appendingPathComponent(filename)
        
        try data.write(to: fileURL)
        
        print("[ResearchStorage] Saved PDF for project: \(projectId)")
        return filename
    }
    
    func getPDFURL(path: String) -> URL? {
        let fileURL = pdfsDirectory.appendingPathComponent(path)
        return FileManager.default.fileExists(atPath: fileURL.path) ? fileURL : nil
    }
    
    func deletePDF(at path: String) {
        let fileURL = pdfsDirectory.appendingPathComponent(path)
        try? FileManager.default.removeItem(at: fileURL)
        print("[ResearchStorage] Deleted PDF: \(path)")
    }
    
    // MARK: - Statistics
    
    func getProjectCounts() throws -> [ProjectStatus: Int] {
        guard let context = modelContext else {
            throw ResearchStorageError.notInitialized
        }
        
        var counts: [ProjectStatus: Int] = [:]
        
        for status in ProjectStatus.allCases {
            let descriptor = FetchDescriptor<ResearchProject>(
                predicate: #Predicate<ResearchProject> { project in
                    project.status == status
                }
            )
            counts[status] = try context.fetchCount(descriptor)
        }
        
        return counts
    }
    
    func getTotalProjectCount() throws -> Int {
        guard let context = modelContext else {
            throw ResearchStorageError.notInitialized
        }
        
        let descriptor = FetchDescriptor<ResearchProject>()
        return try context.fetchCount(descriptor)
    }
    
    // MARK: - Sync Queue
    
    func getProjectsNeedingSync() throws -> [ResearchProject] {
        guard let context = modelContext else {
            throw ResearchStorageError.notInitialized
        }
        
        let descriptor = FetchDescriptor<ResearchProject>(
            predicate: #Predicate<ResearchProject> { project in
                project.needsSync == true
            }
        )
        
        return try context.fetch(descriptor)
    }
    
    func markSynced(_ project: ResearchProject) throws {
        project.needsSync = false
        project.lastSyncedAt = Date()
        try updateProject(project)
    }
    
    // MARK: - Export/Import
    
    func exportProject(_ project: ResearchProject) throws -> Data {
        let exportData = ProjectExportData(from: project)
        return try JSONEncoder().encode(exportData)
    }
    
    func importProject(from data: Data) throws -> ResearchProject {
        guard let context = modelContext else {
            throw ResearchStorageError.notInitialized
        }
        
        let exportData = try JSONDecoder().decode(ProjectExportData.self, from: data)
        let project = exportData.toResearchProject()
        
        context.insert(project)
        try context.save()
        
        return project
    }
}

// MARK: - Errors

enum ResearchStorageError: Error, LocalizedError {
    case notInitialized
    case projectNotFound
    case saveFailed(String)
    case fetchFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Storage service not initialized"
        case .projectNotFound:
            return "Project not found"
        case .saveFailed(let reason):
            return "Failed to save: \(reason)"
        case .fetchFailed(let reason):
            return "Failed to fetch: \(reason)"
        }
    }
}

// MARK: - Export Data Structure

struct ProjectExportData: Codable {
    let id: UUID
    let title: String
    let description: String
    let source: ProjectSource
    let status: ProjectStatus
    let createdAt: Date
    let updatedAt: Date
    
    let paperTitle: String?
    let paperAuthors: [String]?
    let paperAbstract: String?
    let arxivId: String?
    let doi: String?
    let paperPublicationDate: Date?
    let paperUrl: String?
    
    let background: String?
    let backgroundGeneratedAt: Date?
    
    let hypotheses: [String]?
    let methodology: String?
    let datasets: [String]?
    let metrics: [String]?
    let expectedOutcomes: String?
    let risks: String?
    let estimatedScope: String?
    let planGeneratedAt: Date?
    
    let notes: [ResearchNote]
    
    init(from project: ResearchProject) {
        self.id = project.id
        self.title = project.title
        self.description = project.projectDescription
        self.source = project.source
        self.status = project.status
        self.createdAt = project.createdAt
        self.updatedAt = project.updatedAt
        
        self.paperTitle = project.paperTitle
        self.paperAuthors = project.paperAuthors
        self.paperAbstract = project.paperAbstract
        self.arxivId = project.arxivId
        self.doi = project.doi
        self.paperPublicationDate = project.paperPublicationDate
        self.paperUrl = project.paperUrl
        
        self.background = project.background
        self.backgroundGeneratedAt = project.backgroundGeneratedAt
        
        self.hypotheses = project.hypotheses
        self.methodology = project.methodology
        self.datasets = project.datasets
        self.metrics = project.metrics
        self.expectedOutcomes = project.expectedOutcomes
        self.risks = project.risks
        self.estimatedScope = project.estimatedScope
        self.planGeneratedAt = project.planGeneratedAt
        
        self.notes = project.notes
    }
    
    func toResearchProject() -> ResearchProject {
        let project = ResearchProject(
            title: title,
            description: description,
            source: source
        )
        
        // Override auto-generated values
        project.status = status
        project.createdAt = createdAt
        project.updatedAt = updatedAt
        
        // Paper metadata
        project.paperTitle = paperTitle
        project.paperAuthors = paperAuthors
        project.paperAbstract = paperAbstract
        project.arxivId = arxivId
        project.doi = doi
        project.paperPublicationDate = paperPublicationDate
        project.paperUrl = paperUrl
        
        // AI content
        project.background = background
        project.backgroundGeneratedAt = backgroundGeneratedAt
        
        // Experiment plan
        project.hypotheses = hypotheses
        project.methodology = methodology
        project.datasets = datasets
        project.metrics = metrics
        project.expectedOutcomes = expectedOutcomes
        project.risks = risks
        project.estimatedScope = estimatedScope
        project.planGeneratedAt = planGeneratedAt
        
        // Notes
        project.notes = notes
        
        return project
    }
}
