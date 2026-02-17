//
//  ResearchTypes.swift
//  OpenClaw
//
//  Data models for Research Lab feature
//

import Foundation
import SwiftData

// MARK: - Research Project

@Model
final class ResearchProject {
    var id: UUID
    var title: String
    var projectDescription: String
    var source: ProjectSource
    var status: ProjectStatus
    var createdAt: Date
    var updatedAt: Date
    
    // Paper metadata (optional - only for paper-based projects)
    var paperTitle: String?
    var paperAuthors: [String]?
    var paperAbstract: String?
    var arxivId: String?
    var doi: String?
    var paperPublicationDate: Date?
    var pdfLocalPath: String?
    var paperUrl: String?
    
    // AI-generated content
    var background: String?
    var backgroundGeneratedAt: Date?
    
    // Experiment plan
    var hypotheses: [String]?
    var methodology: String?
    var datasets: [String]?
    var metrics: [String]?
    var expectedOutcomes: String?
    var risks: String?
    var estimatedScope: String?
    var planGeneratedAt: Date?
    
    // Zotero integration
    var zoteroItemKey: String?
    var zoteroCollectionKey: String?
    var lastSyncedAt: Date?
    
    // Notes stored as JSON-encoded array
    var notesData: Data?
    
    // Offline sync tracking
    var needsSync: Bool
    var pendingOperations: Data?  // JSON-encoded array of pending operations
    
    init(
        title: String,
        description: String = "",
        source: ProjectSource = .manual
    ) {
        self.id = UUID()
        self.title = title
        self.projectDescription = description
        self.source = source
        self.status = .idea
        self.createdAt = Date()
        self.updatedAt = Date()
        self.needsSync = false
    }
    
    // MARK: - Notes Management
    
    var notes: [ResearchNote] {
        get {
            guard let data = notesData else { return [] }
            return (try? JSONDecoder().decode([ResearchNote].self, from: data)) ?? []
        }
        set {
            notesData = try? JSONEncoder().encode(newValue)
            updatedAt = Date()
        }
    }
    
    func addNote(_ content: String, source: NoteSource = .user) {
        var currentNotes = notes
        currentNotes.append(ResearchNote(content: content, source: source))
        notes = currentNotes
    }
    
    // MARK: - Paper Metadata Helpers
    
    var hasPaperMetadata: Bool {
        paperTitle != nil || arxivId != nil || doi != nil
    }
    
    var paperMetadataSummary: String? {
        guard let title = paperTitle else { return nil }
        let authors = paperAuthors?.prefix(3).joined(separator: ", ") ?? "Unknown authors"
        let suffix = (paperAuthors?.count ?? 0) > 3 ? " et al." : ""
        return "\(title)\n\(authors)\(suffix)"
    }
    
    // MARK: - Experiment Plan Helpers
    
    var hasExperimentPlan: Bool {
        hypotheses != nil || methodology != nil
    }
    
    // MARK: - Status Helpers
    
    func updateStatus(_ newStatus: ProjectStatus) {
        status = newStatus
        updatedAt = Date()
    }
}

// MARK: - Supporting Types

enum ProjectSource: String, Codable {
    case voice          // Dictated idea
    case paper          // Imported from paper link
    case zotero         // Imported from Zotero
    case manual         // Manually created
    
    var displayName: String {
        switch self {
        case .voice: return "Voice Note"
        case .paper: return "Research Paper"
        case .zotero: return "Zotero Import"
        case .manual: return "Manual Entry"
        }
    }
    
    var iconName: String {
        switch self {
        case .voice: return "mic.fill"
        case .paper: return "doc.text.fill"
        case .zotero: return "books.vertical.fill"
        case .manual: return "square.and.pencil"
        }
    }
}

enum ProjectStatus: String, Codable, CaseIterable {
    case idea           // Initial capture
    case researching    // Gathering background
    case planned        // Experiment plan ready
    case inProgress     // Actively working
    case completed      // Done
    case archived       // No longer active
    
    var displayName: String {
        switch self {
        case .idea: return "Idea"
        case .researching: return "Researching"
        case .planned: return "Planned"
        case .inProgress: return "In Progress"
        case .completed: return "Completed"
        case .archived: return "Archived"
        }
    }
    
    var iconName: String {
        switch self {
        case .idea: return "lightbulb.fill"
        case .researching: return "magnifyingglass"
        case .planned: return "list.bullet.clipboard.fill"
        case .inProgress: return "play.fill"
        case .completed: return "checkmark.circle.fill"
        case .archived: return "archivebox.fill"
        }
    }
    
    var color: String {
        switch self {
        case .idea: return "yellow"
        case .researching: return "blue"
        case .planned: return "purple"
        case .inProgress: return "orange"
        case .completed: return "green"
        case .archived: return "gray"
        }
    }
}

// MARK: - Research Note

struct ResearchNote: Identifiable, Codable, Equatable {
    let id: UUID
    var content: String
    let timestamp: Date
    let source: NoteSource
    
    init(id: UUID = UUID(), content: String, source: NoteSource = .user) {
        self.id = id
        self.content = content
        self.timestamp = Date()
        self.source = source
    }
}

enum NoteSource: String, Codable {
    case user           // User-written note
    case ai             // AI-generated insight
    case imported       // Imported from external source
    
    var iconName: String {
        switch self {
        case .user: return "person.fill"
        case .ai: return "sparkles"
        case .imported: return "arrow.down.circle.fill"
        }
    }
}

// MARK: - Sync Operations (for offline queue)

enum SyncOperation: Codable {
    case createProject(projectId: UUID)
    case updateProject(projectId: UUID)
    case deleteProject(projectId: UUID)
    case syncToZotero(projectId: UUID)
    case fetchPaper(url: String, projectId: UUID)
    case generateBackground(projectId: UUID)
    case generatePlan(projectId: UUID)
    
    var requiresNetwork: Bool {
        switch self {
        case .createProject, .updateProject, .deleteProject:
            return false
        default:
            return true
        }
    }
}

// MARK: - Paper Source Detection

enum PaperSourceType {
    case arxiv(id: String)
    case doi(id: String)
    case semanticScholar(id: String)
    case directPDF(url: URL)
    case unknown
    
    static func detect(from urlString: String) -> PaperSourceType {
        let lowercased = urlString.lowercased()
        
        // arXiv detection
        if lowercased.contains("arxiv.org") {
            // Extract arXiv ID from various URL formats
            // https://arxiv.org/abs/2301.12345
            // https://arxiv.org/pdf/2301.12345.pdf
            if let range = urlString.range(of: #"(\d{4}\.\d{4,5}(v\d+)?)"#, options: .regularExpression) {
                return .arxiv(id: String(urlString[range]))
            }
        }
        
        // DOI detection
        if lowercased.contains("doi.org") || lowercased.contains("10.") {
            if let range = urlString.range(of: #"10\.\d{4,}/[^\s]+"#, options: .regularExpression) {
                return .doi(id: String(urlString[range]))
            }
        }
        
        // Semantic Scholar
        if lowercased.contains("semanticscholar.org") {
            if let range = urlString.range(of: #"paper/([a-f0-9]+)"#, options: .regularExpression) {
                let match = String(urlString[range])
                let id = match.replacingOccurrences(of: "paper/", with: "")
                return .semanticScholar(id: id)
            }
        }
        
        // Direct PDF
        if lowercased.hasSuffix(".pdf"), let url = URL(string: urlString) {
            return .directPDF(url: url)
        }
        
        return .unknown
    }
}
