//
//  ProjectDetailView.swift
//  OpenClaw
//
//  Detailed view for a research project
//

import SwiftUI

struct ProjectDetailView: View {
    let project: ResearchProject
    @ObservedObject var viewModel: ResearchLabViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var showingStatusPicker = false
    @State private var showingAddNote = false
    @State private var newNoteContent = ""
    @State private var selectedSection: DetailSection = .overview
    
    enum DetailSection: String, CaseIterable {
        case overview = "Overview"
        case background = "Background"
        case plan = "Experiment Plan"
        case notes = "Notes"
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundDark
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header with status
                        ProjectHeader(
                            project: project,
                            onStatusTap: { showingStatusPicker = true }
                        )
                        
                        // Section picker
                        SectionPicker(selection: $selectedSection)
                        
                        // Content based on selected section
                        switch selectedSection {
                        case .overview:
                            OverviewSection(project: project)
                        case .background:
                            BackgroundSection(project: project)
                        case .plan:
                            ExperimentPlanSection(project: project)
                        case .notes:
                            NotesSection(
                                project: project,
                                onAddNote: { showingAddNote = true }
                            )
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle(project.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showingStatusPicker = true
                        } label: {
                            Label("Change Status", systemImage: "arrow.triangle.2.circlepath")
                        }
                        
                        if project.paperUrl != nil || project.arxivId != nil {
                            Button {
                                // TODO: Open PDF
                            } label: {
                                Label("View PDF", systemImage: "doc.fill")
                            }
                        }
                        
                        Divider()
                        
                        Button(role: .destructive) {
                            Task {
                                await viewModel.deleteProject(project)
                                dismiss()
                            }
                        } label: {
                            Label("Delete Project", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .confirmationDialog("Change Status", isPresented: $showingStatusPicker) {
                ForEach(ProjectStatus.allCases, id: \.self) { status in
                    Button(status.displayName) {
                        Task {
                            await viewModel.updateProjectStatus(project, to: status)
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showingAddNote) {
                AddNoteSheet(
                    content: $newNoteContent,
                    onSave: {
                        Task {
                            await viewModel.addNote(to: project, content: newNoteContent)
                            newNoteContent = ""
                            showingAddNote = false
                        }
                    }
                )
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Project Header

struct ProjectHeader: View {
    let project: ResearchProject
    let onStatusTap: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Source and date
            HStack {
                Label(project.source.displayName, systemImage: project.source.iconName)
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                
                Spacer()
                
                Text("Created \(project.createdAt.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            }
            
            // Status button
            Button(action: onStatusTap) {
                HStack {
                    Image(systemName: project.status.iconName)
                    Text(project.status.displayName)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(statusColor.opacity(0.2))
                .foregroundStyle(statusColor)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            
            // Paper metadata if available
            if project.hasPaperMetadata {
                PaperMetadataCard(project: project)
            }
        }
    }
    
    var statusColor: Color {
        switch project.status {
        case .idea: return .yellow
        case .researching: return .blue
        case .planned: return .purple
        case .inProgress: return .orange
        case .completed: return .green
        case .archived: return .gray
        }
    }
}

// MARK: - Paper Metadata Card

struct PaperMetadataCard: View {
    let project: ResearchProject
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title = project.paperTitle {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.textPrimary)
            }
            
            if let authors = project.paperAuthors, !authors.isEmpty {
                Text(authors.prefix(5).joined(separator: ", ") + (authors.count > 5 ? " et al." : ""))
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            
            HStack(spacing: 16) {
                if let arxivId = project.arxivId {
                    Label(arxivId, systemImage: "doc.text")
                        .font(.caption2)
                        .foregroundStyle(Color.anthropicOrange)
                }
                
                if let doi = project.doi {
                    Label("DOI", systemImage: "link")
                        .font(.caption2)
                        .foregroundStyle(Color.anthropicCoral)
                }
                
                if project.pdfLocalPath != nil {
                    Label("PDF saved", systemImage: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.statusConnected)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.surfaceSecondary)
        )
    }
}

// MARK: - Section Picker

struct SectionPicker: View {
    @Binding var selection: ProjectDetailView.DetailSection
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ProjectDetailView.DetailSection.allCases, id: \.self) { section in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selection = section
                        }
                    } label: {
                        Text(section.rawValue)
                            .font(.subheadline)
                            .fontWeight(selection == section ? .semibold : .regular)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(selection == section ? Color.anthropicCoral : Color.surfaceSecondary)
                            )
                            .foregroundStyle(selection == section ? .white : Color.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Overview Section

struct OverviewSection: View {
    let project: ResearchProject
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !project.projectDescription.isEmpty {
                DetailCard(title: "Description") {
                    Text(project.projectDescription)
                        .font(.body)
                        .foregroundStyle(Color.textPrimary)
                }
            }
            
            // Quick stats
            DetailCard(title: "Progress") {
                VStack(spacing: 12) {
                    ProgressRow(
                        title: "Background Research",
                        isComplete: project.background != nil,
                        date: project.backgroundGeneratedAt
                    )
                    
                    ProgressRow(
                        title: "Experiment Plan",
                        isComplete: project.hasExperimentPlan,
                        date: project.planGeneratedAt
                    )
                    
                    ProgressRow(
                        title: "Notes",
                        count: project.notes.count
                    )
                }
            }
            
            if project.zoteroItemKey != nil {
                DetailCard(title: "Zotero") {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.statusConnected)
                        Text("Synced with Zotero")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                        
                        Spacer()
                        
                        if let syncDate = project.lastSyncedAt {
                            Text(syncDate.formatted(.relative(presentation: .named)))
                                .font(.caption)
                                .foregroundStyle(Color.textTertiary)
                        }
                    }
                }
            }
        }
    }
}

struct ProgressRow: View {
    let title: String
    var isComplete: Bool = false
    var date: Date? = nil
    var count: Int? = nil
    
    var body: some View {
        HStack {
            Image(systemName: isComplete || (count ?? 0) > 0 ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isComplete || (count ?? 0) > 0 ? Color.statusConnected : Color.textTertiary)
            
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Color.textPrimary)
            
            Spacer()
            
            if let count = count {
                Text("\(count)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.surfaceElevated)
                    .clipShape(Capsule())
                    .foregroundStyle(Color.textSecondary)
            } else if let date = date {
                Text(date.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            } else if !isComplete {
                Text("Pending")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            }
        }
    }
}

// MARK: - Background Section

struct BackgroundSection: View {
    let project: ResearchProject
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let background = project.background {
                DetailCard(title: "Research Background") {
                    Text(background)
                        .font(.body)
                        .foregroundStyle(Color.textPrimary)
                }
                
                if let date = project.backgroundGeneratedAt {
                    Text("Generated \(date.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }
            } else {
                EmptyDetailView(
                    icon: "doc.text.magnifyingglass",
                    title: "No Background Yet",
                    description: "AI will analyze your paper or idea and generate background context",
                    actionTitle: "Generate Background"
                ) {
                    // TODO: Trigger background generation
                }
            }
            
            if let abstract = project.paperAbstract {
                DetailCard(title: "Paper Abstract") {
                    Text(abstract)
                        .font(.body)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
    }
}

// MARK: - Experiment Plan Section

struct ExperimentPlanSection: View {
    let project: ResearchProject
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if project.hasExperimentPlan {
                if let hypotheses = project.hypotheses, !hypotheses.isEmpty {
                    DetailCard(title: "Hypotheses") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(hypotheses.indices, id: \.self) { index in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("\(index + 1).")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundStyle(Color.anthropicCoral)
                                    Text(hypotheses[index])
                                        .font(.body)
                                        .foregroundStyle(Color.textPrimary)
                                }
                            }
                        }
                    }
                }
                
                if let methodology = project.methodology {
                    DetailCard(title: "Methodology") {
                        Text(methodology)
                            .font(.body)
                            .foregroundStyle(Color.textPrimary)
                    }
                }
                
                if let datasets = project.datasets, !datasets.isEmpty {
                    DetailCard(title: "Datasets") {
                        FlowLayout(spacing: 8) {
                            ForEach(datasets, id: \.self) { dataset in
                                Text(dataset)
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.surfaceElevated)
                                    .clipShape(Capsule())
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                    }
                }
                
                if let metrics = project.metrics, !metrics.isEmpty {
                    DetailCard(title: "Metrics") {
                        FlowLayout(spacing: 8) {
                            ForEach(metrics, id: \.self) { metric in
                                Text(metric)
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.anthropicCoral.opacity(0.2))
                                    .clipShape(Capsule())
                                    .foregroundStyle(Color.anthropicCoral)
                            }
                        }
                    }
                }
                
                if let outcomes = project.expectedOutcomes {
                    DetailCard(title: "Expected Outcomes") {
                        Text(outcomes)
                            .font(.body)
                            .foregroundStyle(Color.textPrimary)
                    }
                }
                
                if let risks = project.risks {
                    DetailCard(title: "Risks & Challenges") {
                        Text(risks)
                            .font(.body)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                
                if let scope = project.estimatedScope {
                    HStack {
                        Text("Scope:")
                            .font(.subheadline)
                            .foregroundStyle(Color.textTertiary)
                        Text(scope)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.textPrimary)
                    }
                }
            } else {
                EmptyDetailView(
                    icon: "list.bullet.clipboard",
                    title: "No Experiment Plan Yet",
                    description: "AI will create a structured plan with hypotheses, methodology, and expected outcomes",
                    actionTitle: "Generate Plan"
                ) {
                    // TODO: Trigger plan generation
                }
            }
        }
    }
}

// MARK: - Notes Section

struct NotesSection: View {
    let project: ResearchProject
    let onAddNote: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Notes")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                
                Spacer()
                
                Button(action: onAddNote) {
                    Label("Add Note", systemImage: "plus.circle.fill")
                        .font(.subheadline)
                }
            }
            
            if project.notes.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "note.text")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.textTertiary)
                    
                    Text("No notes yet")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                    
                    Button("Add your first note", action: onAddNote)
                        .font(.subheadline)
                        .foregroundStyle(Color.anthropicCoral)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                ForEach(project.notes.reversed()) { note in
                    NoteCard(note: note)
                }
            }
        }
    }
}

struct NoteCard: View {
    let note: ResearchNote
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: note.source.iconName)
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                
                Text(note.source == .ai ? "AI Insight" : "Your Note")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                
                Spacer()
                
                Text(note.timestamp.formatted(.relative(presentation: .named)))
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
            }
            
            Text(note.content)
                .font(.body)
                .foregroundStyle(Color.textPrimary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(note.source == .ai ? Color.anthropicCoral.opacity(0.1) : Color.surfaceSecondary)
        )
    }
}

// MARK: - Detail Card

struct DetailCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
            
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.surfacePrimary)
        )
    }
}

// MARK: - Empty Detail View

struct EmptyDetailView: View {
    let icon: String
    let title: String
    let description: String
    let actionTitle: String
    let action: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(Color.textTertiary)
            
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
            
            Text(description)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
            
            Button(action: action) {
                Text(actionTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.anthropicCoral)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.surfacePrimary)
        )
    }
}

// MARK: - Add Note Sheet

struct AddNoteSheet: View {
    @Binding var content: String
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundDark
                    .ignoresSafeArea()
                
                VStack {
                    TextEditor(text: $content)
                        .scrollContentBackground(.hidden)
                        .padding()
                        .background(Color.inputBackground)
                        .cornerRadius(12)
                        .foregroundStyle(Color.textPrimary)
                        .focused($isFocused)
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Add Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        content = ""
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: onSave)
                        .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                isFocused = true
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return CGSize(width: proposal.width ?? 0, height: result.height)
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                      y: bounds.minY + result.positions[index].y),
                         proposal: ProposedViewSize(result.sizes[index]))
        }
    }
    
    struct FlowResult {
        var positions: [CGPoint] = []
        var sizes: [CGSize] = []
        var height: CGFloat = 0
        
        init(in width: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > width && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }
                
                positions.append(CGPoint(x: x, y: y))
                sizes.append(size)
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
            }
            
            height = y + rowHeight
        }
    }
}
