//
//  ZoteroItemDetailView.swift
//  OpenClaw
//
//  Detail view for a Zotero library item showing metadata and notes
//

import SwiftUI
import Combine

struct ZoteroItemDetailView: View {
    let item: ZoteroItem
    var onItemUpdated: ((ZoteroItem) -> Void)?
    
    @StateObject private var viewModel: ZoteroItemDetailViewModel
    @EnvironmentObject private var playerManager: AudioPlayerManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedNote: ZoteroNote?
    @State private var showEditSheet = false
    @State private var showAddNoteSheet = false
    @State private var editingNote: ZoteroNote?
    @State private var showGenerateAudioSheet = false
    @State private var paperAudioJobs: [PaperAudioJob] = []
    @State private var selectedPaperAudioJob: PaperAudioJob?
    @State private var paperAudioError: String?
    @State private var attachments: [ZoteroItem] = []
    @State private var isLoadingAttachments = false
    @State private var selectedPDFAttachment: ZoteroItem?
    
    init(item: ZoteroItem, onItemUpdated: ((ZoteroItem) -> Void)? = nil) {
        self.item = item
        self.onItemUpdated = onItemUpdated
        self._viewModel = StateObject(wrappedValue: ZoteroItemDetailViewModel(item: item))
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundDark.ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Header
                        headerSection
                        
                        // Metadata
                        metadataSection
                        
                        // Abstract
                        if let abstract = viewModel.currentItem.data.abstractNote, !abstract.isEmpty {
                            abstractSection(abstract)
                        }
                        
                        // Notes
                        notesSection
                        
                        // PDF Attachments
                        attachmentsSection
                        
                        // Tags
                        if let tags = viewModel.currentItem.data.tags, !tags.isEmpty {
                            tagsSection(tags)
                        }
                        
                        // Links
                        linksSection
                        
                        // Paper Audio
                        paperAudioSection
                        
                        // Delete button
                        deleteButton
                    }
                    .padding()
                }
                
                if viewModel.isProcessing {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(Color.anthropicCoral)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showEditSheet = true
                    } label: {
                        Image(systemName: "pencil")
                            .foregroundStyle(Color.anthropicCoral)
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.anthropicCoral)
                }
            }
            .sheet(item: $selectedNote) { note in
                NoteDetailSheet(
                    note: note,
                    onEdit: {
                        selectedNote = nil
                        editingNote = note
                    }
                )
            }
            .sheet(isPresented: $showEditSheet) {
                ZoteroEditItemSheet(viewModel: viewModel) { updatedItem in
                    onItemUpdated?(updatedItem)
                }
            }
            .sheet(isPresented: $showAddNoteSheet) {
                ZoteroNoteEditorSheet(
                    parentKey: viewModel.currentItem.key,
                    existingNote: nil,
                    onSave: { _ in
                        Task { await viewModel.loadNotes() }
                    }
                )
            }
            .sheet(item: $editingNote) { note in
                ZoteroNoteEditorSheet(
                    parentKey: viewModel.currentItem.key,
                    existingNote: note,
                    onSave: { _ in
                        Task { await viewModel.loadNotes() }
                    }
                )
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "An error occurred")
            }
            .sheet(isPresented: $showGenerateAudioSheet) {
                GeneratePaperAudioSheet(item: viewModel.currentItem) {
                    Task { await loadPaperAudioJobs() }
                }
            }
            .sheet(item: $selectedPaperAudioJob) { job in
                PaperAudioPlayerView(job: job)
                    .environmentObject(playerManager)
            }
            .fullScreenCover(item: $selectedPDFAttachment) { attachment in
                PDFViewerView(item: item, attachment: attachment)
            }
            .alert("Delete Item", isPresented: $viewModel.showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    Task {
                        if await viewModel.deleteItem() {
                            dismiss()
                        }
                    }
                }
            } message: {
                Text("Are you sure you want to delete this item? This cannot be undone.")
            }
        }
        .presentationDetents([.large])
        .task {
            print("[ZoteroDetail] .task started for item: \(viewModel.currentItem.key)")
            await viewModel.loadNotes()
            print("[ZoteroDetail] Notes loaded, now loading attachments and paper audio jobs...")
            await loadAttachments()
            await loadPaperAudioJobs()
        }
    }
    
    // MARK: - PDF Attachments
    
    private var pdfAttachments: [ZoteroItem] {
        attachments.filter { $0.data.isPDF }
    }
    
    private var downloadablePDFs: [ZoteroItem] {
        pdfAttachments.filter { $0.data.isDownloadable }
    }
    
    private var linkedOnlyPDFs: [ZoteroItem] {
        pdfAttachments.filter { !$0.data.isDownloadable }
    }
    
    private var attachmentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ATTACHMENTS")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.textSecondary)
                    .tracking(0.5)
                
                Spacer()
                
                if isLoadingAttachments {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(Color.anthropicCoral)
                }
            }
            
            if pdfAttachments.isEmpty && !isLoadingAttachments {
                Text("No PDF attachments")
                    .font(.subheadline)
                    .foregroundStyle(Color.textTertiary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.surfaceSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(spacing: 1) {
                    ForEach(downloadablePDFs) { attachment in
                        AttachmentRow(attachment: attachment)
                            .onTapGesture {
                                selectedPDFAttachment = attachment
                            }
                    }
                    
                    ForEach(linkedOnlyPDFs) { attachment in
                        AttachmentRow(attachment: attachment, isLinkedOnly: true)
                    }
                }
                .background(Color.surfaceSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    
    private func loadAttachments() async {
        isLoadingAttachments = true
        do {
            let children = try await ZoteroService.shared.fetchChildItems(parentKey: viewModel.currentItem.key)
            attachments = children.filter { $0.data.itemType == .attachment }
            print("[ZoteroDetail] Found \(pdfAttachments.count) PDF attachments")
        } catch {
            print("[ZoteroDetail] Failed to load attachments: \(error)")
        }
        isLoadingAttachments = false
    }
    
    // MARK: - Paper Audio Section
    
    private var paperAudioSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PAPER AUDIO")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Color.textSecondary)
                .tracking(0.5)
            
            // Show error if fetch failed
            if let error = paperAudioError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.statusDisconnected)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Color.statusDisconnected)
                        .lineLimit(3)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.statusDisconnected.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            
            VStack(spacing: 1) {
                // Existing completed jobs — tap to play
                ForEach(paperAudioJobs.filter { $0.status == .completed }) { job in
                    Button {
                        selectedPaperAudioJob = job
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: job.mode.iconName)
                                .foregroundStyle(Color.anthropicCoral)
                                .frame(width: 24)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(job.mode.displayName)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(Color.textPrimary)
                                
                                if let duration = job.formattedDuration {
                                    Text(duration)
                                        .font(.caption)
                                        .foregroundStyle(Color.textTertiary)
                                }
                            }
                            
                            Spacer()
                            
                            Image(systemName: "play.circle.fill")
                                .font(.title3)
                                .foregroundStyle(Color.anthropicCoral)
                        }
                        .padding()
                        .background(Color.surfacePrimary)
                    }
                    .buttonStyle(.plain)
                }
                
                // Active jobs — show progress
                ForEach(paperAudioJobs.filter { $0.status.isActive }) { job in
                    HStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(Color.anthropicCoral)
                            .frame(width: 24)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(job.mode.displayName) — \(job.status.displayName)")
                                .font(.subheadline)
                                .foregroundStyle(Color.textPrimary)
                            
                            if let progress = job.progress {
                                ProgressView(value: progress)
                                    .tint(Color.anthropicCoral)
                                    .scaleEffect(y: 0.6)
                            }
                        }
                        
                        Spacer()
                    }
                    .padding()
                    .background(Color.surfacePrimary)
                }
                
                // Generate button
                Button {
                    showGenerateAudioSheet = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "waveform.circle.fill")
                            .foregroundStyle(Color.anthropicCoral)
                            .frame(width: 24)
                        
                        Text("Generate Audiobook")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.anthropicCoral)
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                    }
                    .padding()
                    .background(Color.surfacePrimary)
                }
                .buttonStyle(.plain)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    private func loadPaperAudioJobs() async {
        print("[ZoteroDetail] Loading paper audio jobs for item key: \(viewModel.currentItem.key)")
        paperAudioError = nil
        do {
            let allJobs = try await PaperAudioService.shared.fetchJobs(forceRefresh: true)
            paperAudioJobs = allJobs.filter { $0.zoteroItemKey == viewModel.currentItem.key }
            print("[ZoteroDetail] Loaded \(paperAudioJobs.count) paper audio jobs for \(viewModel.currentItem.key) (from \(allJobs.count) total)")
            for job in paperAudioJobs {
                print("[ZoteroDetail]   - Job \(job.id): \(job.mode.rawValue) / \(job.status.rawValue)")
            }
        } catch {
            paperAudioError = error.localizedDescription
            print("[ZoteroDetail] Failed to load paper audio jobs: \(error)")
        }
    }
    
    private var deleteButton: some View {
        Button(role: .destructive) {
            viewModel.showDeleteConfirmation = true
        } label: {
            HStack {
                Image(systemName: "trash")
                Text("Delete Item")
            }
            .fontWeight(.medium)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.statusDisconnected.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .foregroundStyle(Color.statusDisconnected)
        .padding(.top, 20)
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Item type badge
            HStack(spacing: 6) {
                Image(systemName: viewModel.currentItem.data.itemType.iconName)
                    .font(.caption)
                Text(viewModel.currentItem.data.itemType.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(Color.anthropicCoral)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.anthropicCoral.opacity(0.15))
            .clipShape(Capsule())
            
            // Title
            Text(viewModel.currentItem.data.displayTitle)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(Color.textPrimary)
            
            // Authors
            if !viewModel.currentItem.data.authorsString.isEmpty {
                Text(viewModel.currentItem.data.authorsString)
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }
    
    // MARK: - Metadata Section
    
    private var metadataSection: some View {
        VStack(spacing: 1) {
            if let publication = viewModel.currentItem.data.publicationTitle, !publication.isEmpty {
                MetadataRow(label: "Publication", value: publication)
            }
            
            if let date = viewModel.currentItem.data.formattedDate {
                MetadataRow(label: "Year", value: date)
            }
            
            if let volume = viewModel.currentItem.data.volume, !volume.isEmpty {
                MetadataRow(label: "Volume", value: formatVolumeInfo(volume: volume))
            }
            
            if let publisher = viewModel.currentItem.data.publisher, !publisher.isEmpty {
                MetadataRow(label: "Publisher", value: formatPublisherInfo(publisher: publisher))
            }
            
            if let doi = viewModel.currentItem.data.DOI, !doi.isEmpty {
                MetadataRow(label: "DOI", value: doi, isLink: true)
            }
        }
        .background(Color.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private func formatVolumeInfo(volume: String) -> String {
        var info = "Vol. \(volume)"
        if let issue = viewModel.currentItem.data.issue, !issue.isEmpty {
            info += ", No. \(issue)"
        }
        if let pages = viewModel.currentItem.data.pages, !pages.isEmpty {
            info += ", pp. \(pages)"
        }
        return info
    }
    
    private func formatPublisherInfo(publisher: String) -> String {
        if let place = viewModel.currentItem.data.place, !place.isEmpty {
            return "\(publisher), \(place)"
        }
        return publisher
    }
    
    // MARK: - Abstract Section
    
    private func abstractSection(_ abstract: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ABSTRACT")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Color.textSecondary)
                .tracking(0.5)
            
            Text(abstract)
                .font(.subheadline)
                .foregroundStyle(Color.textPrimary)
                .lineSpacing(4)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Notes Section
    
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("NOTES")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.textSecondary)
                    .tracking(0.5)
                
                Spacer()
                
                if viewModel.isLoadingNotes {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Button {
                        showAddNoteSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color.anthropicCoral)
                    }
                }
            }
            
            if viewModel.notes.isEmpty && !viewModel.isLoadingNotes {
                Button {
                    showAddNoteSheet = true
                } label: {
                    HStack {
                        Image(systemName: "plus")
                        Text("Add a note")
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color.anthropicCoral)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.surfaceSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            } else {
                VStack(spacing: 1) {
                    ForEach(viewModel.notes) { note in
                        NoteRow(note: note)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedNote = note
                            }
                    }
                }
                .background(Color.surfaceSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    
    // MARK: - Tags Section
    
    private func tagsSection(_ tags: [ZoteroTag]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TAGS")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Color.textSecondary)
                .tracking(0.5)
            
            FlowLayout(spacing: 8) {
                ForEach(tags) { tag in
                    Text(tag.tag)
                        .font(.caption)
                        .foregroundStyle(Color.anthropicCoral)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.anthropicCoral.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
        }
    }
    
    // MARK: - Links Section
    
    private var linksSection: some View {
        VStack(spacing: 1) {
            if let url = viewModel.currentItem.data.url, !url.isEmpty, let linkURL = URL(string: url) {
                LinkRow(label: "Open URL", url: linkURL, icon: "globe")
            }
            
            if let doi = viewModel.currentItem.data.DOI, !doi.isEmpty, let doiURL = URL(string: "https://doi.org/\(doi)") {
                LinkRow(label: "Open DOI", url: doiURL, icon: "link")
            }
        }
        .background(Color.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Metadata Row

struct MetadataRow: View {
    let label: String
    let value: String
    var isLink: Bool = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .frame(width: horizontalSizeClass == .regular ? 120 : 90, alignment: .leading)
            
            Text(value)
                .font(.subheadline)
                .foregroundStyle(isLink ? Color.anthropicCoral : Color.textPrimary)
                .textSelection(.enabled)
            
            Spacer()
        }
        .padding()
        .background(Color.surfacePrimary)
    }
}

// MARK: - Note Row

struct NoteRow: View {
    let note: ZoteroNote
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "note.text")
                .foregroundStyle(Color.anthropicCoral)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(note.previewText)
                    .font(.subheadline)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                
                if let date = note.dateModified {
                    Text(date)
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
        }
        .padding()
        .background(Color.surfacePrimary)
    }
}

// MARK: - Link Row

struct LinkRow: View {
    let label: String
    let url: URL
    let icon: String
    
    var body: some View {
        Link(destination: url) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(Color.anthropicCoral)
                
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(Color.textPrimary)
                
                Spacer()
                
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            }
            .padding()
            .background(Color.surfacePrimary)
        }
    }
}

// MARK: - Note Detail Sheet

struct NoteDetailSheet: View {
    let note: ZoteroNote
    let onEdit: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundDark.ignoresSafeArea()
                
                ScrollView {
                    Text(note.plainTextNote)
                        .font(.body)
                        .foregroundStyle(Color.textPrimary)
                        .textSelection(.enabled)
                        .padding()
                }
            }
            .navigationTitle("Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                        onEdit()
                    } label: {
                        Image(systemName: "pencil")
                            .foregroundStyle(Color.anthropicCoral)
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(Color.anthropicCoral)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - View Model

@MainActor
final class ZoteroItemDetailViewModel: ObservableObject {
    @Published var currentItem: ZoteroItem
    @Published var notes: [ZoteroNote] = []
    @Published var isLoadingNotes = false
    @Published var isProcessing = false
    @Published var showError = false
    @Published var errorMessage: String?
    @Published var showDeleteConfirmation = false
    
    private let service = ZoteroService.shared
    
    init(item: ZoteroItem) {
        self.currentItem = item
    }
    
    func loadNotes() async {
        isLoadingNotes = true
        
        do {
            notes = try await service.fetchNotes(parentKey: currentItem.key)
        } catch {
            print("[ZoteroDetail] Failed to load notes: \(error)")
        }
        
        isLoadingNotes = false
    }
    
    func updateItem(updates: ZoteroItemUpdates) async -> ZoteroItem? {
        isProcessing = true
        errorMessage = nil
        
        do {
            let updated = try await service.updateItem(
                key: currentItem.key,
                version: currentItem.version,
                updates: updates
            )
            currentItem = updated
            isProcessing = false
            return updated
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            isProcessing = false
            return nil
        }
    }
    
    func deleteItem() async -> Bool {
        isProcessing = true
        errorMessage = nil
        
        do {
            try await service.deleteItem(key: currentItem.key, version: currentItem.version)
            isProcessing = false
            return true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            isProcessing = false
            return false
        }
    }
}

// MARK: - Edit Item Sheet

struct ZoteroEditItemSheet: View {
    @ObservedObject var viewModel: ZoteroItemDetailViewModel
    let onSave: (ZoteroItem) -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var title: String = ""
    @State private var abstractNote: String = ""
    @State private var date: String = ""
    @State private var url: String = ""
    @State private var doi: String = ""
    @State private var publicationTitle: String = ""
    @State private var volume: String = ""
    @State private var issue: String = ""
    @State private var pages: String = ""
    @State private var publisher: String = ""
    @State private var isSaving = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundDark.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Basic Info
                        VStack(spacing: 1) {
                            FormTextField(label: "Title", text: $title, placeholder: "Enter title")
                            FormTextField(label: "Date", text: $date, placeholder: "YYYY or YYYY-MM-DD")
                            FormTextField(label: "URL", text: $url, placeholder: "https://...")
                            FormTextField(label: "DOI", text: $doi, placeholder: "10.xxxx/xxxxx")
                        }
                        .background(Color.surfaceSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        
                        // Publication Details
                        VStack(spacing: 1) {
                            FormTextField(label: "Publication", text: $publicationTitle, placeholder: "Journal name")
                            FormTextField(label: "Volume", text: $volume, placeholder: "")
                            FormTextField(label: "Issue", text: $issue, placeholder: "")
                            FormTextField(label: "Pages", text: $pages, placeholder: "e.g., 1-15")
                            FormTextField(label: "Publisher", text: $publisher, placeholder: "")
                        }
                        .background(Color.surfaceSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        
                        // Abstract
                        VStack(alignment: .leading, spacing: 8) {
                            Text("ABSTRACT")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.textSecondary)
                                .tracking(0.5)
                            
                            TextEditor(text: $abstractNote)
                                .frame(minHeight: 120)
                                .padding(8)
                                .background(Color.surfacePrimary)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(Color.textPrimary)
                        }
                    }
                    .padding()
                }
                
                if isSaving {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(Color.anthropicCoral)
                }
            }
            .navigationTitle("Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(Color.textSecondary)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        save()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.anthropicCoral)
                    .disabled(isSaving)
                }
            }
        }
        .onAppear {
            loadCurrentValues()
        }
    }
    
    private func loadCurrentValues() {
        let data = viewModel.currentItem.data
        title = data.title ?? ""
        abstractNote = data.abstractNote ?? ""
        date = data.date ?? ""
        url = data.url ?? ""
        doi = data.DOI ?? ""
        publicationTitle = data.publicationTitle ?? ""
        volume = data.volume ?? ""
        issue = data.issue ?? ""
        pages = data.pages ?? ""
        publisher = data.publisher ?? ""
    }
    
    private func save() {
        isSaving = true
        
        let updates = ZoteroItemUpdates(
            title: title.isEmpty ? nil : title,
            abstractNote: abstractNote.isEmpty ? nil : abstractNote,
            date: date.isEmpty ? nil : date,
            url: url.isEmpty ? nil : url,
            DOI: doi.isEmpty ? nil : doi,
            publicationTitle: publicationTitle.isEmpty ? nil : publicationTitle,
            volume: volume.isEmpty ? nil : volume,
            issue: issue.isEmpty ? nil : issue,
            pages: pages.isEmpty ? nil : pages,
            publisher: publisher.isEmpty ? nil : publisher
        )
        
        Task {
            if let updated = await viewModel.updateItem(updates: updates) {
                onSave(updated)
                dismiss()
            }
            isSaving = false
        }
    }
}

// MARK: - Note Editor Sheet

struct ZoteroNoteEditorSheet: View {
    let parentKey: String
    let existingNote: ZoteroNote?
    let onSave: (ZoteroItem) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var noteContent: String = ""
    @State private var isSaving = false
    @State private var showError = false
    @State private var errorMessage: String?
    
    private var isEditing: Bool { existingNote != nil }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundDark.ignoresSafeArea()
                
                VStack {
                    TextEditor(text: $noteContent)
                        .padding()
                        .background(Color.surfacePrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(Color.textPrimary)
                        .padding()
                }
                
                if isSaving {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(Color.anthropicCoral)
                }
            }
            .navigationTitle(isEditing ? "Edit Note" : "New Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(Color.textSecondary)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        save()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(noteContent.isEmpty ? Color.textSecondary : Color.anthropicCoral)
                    .disabled(noteContent.isEmpty || isSaving)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "An error occurred")
            }
        }
        .onAppear {
            if let note = existingNote {
                noteContent = note.note
            }
        }
    }
    
    private func save() {
        isSaving = true
        
        Task {
            do {
                let htmlContent = "<p>\(noteContent.replacingOccurrences(of: "\n", with: "</p><p>"))</p>"
                
                if let note = existingNote {
                    // Update existing note - need to fetch version first
                    let children = try await ZoteroService.shared.fetchChildItems(parentKey: parentKey)
                    if let noteItem = children.first(where: { $0.key == note.key }) {
                        let updated = try await ZoteroService.shared.updateNote(
                            key: note.key,
                            version: noteItem.version,
                            content: htmlContent
                        )
                        onSave(updated)
                    }
                } else {
                    // Create new note
                    let created = try await ZoteroService.shared.createNote(
                        parentKey: parentKey,
                        content: htmlContent
                    )
                    onSave(created)
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
            isSaving = false
        }
    }
}

// MARK: - Attachment Row

struct AttachmentRow: View {
    let attachment: ZoteroItem
    var isLinkedOnly: Bool = false
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isLinkedOnly ? "link" : "doc.fill")
                .font(.title3)
                .foregroundStyle(isLinkedOnly ? Color.textTertiary : Color.anthropicCoral)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.data.filename ?? "PDF")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(isLinkedOnly ? Color.textSecondary : Color.textPrimary)
                    .lineLimit(1)
                
                Text(isLinkedOnly ? "Linked file — not synced to Zotero" : (attachment.data.contentType ?? "application/pdf"))
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
            }
            
            Spacer()
            
            if !isLinkedOnly {
                Image(systemName: "eye.fill")
                    .font(.caption)
                    .foregroundStyle(Color.anthropicCoral)
            }
        }
        .padding(12)
        .contentShape(Rectangle())
    }
}

#Preview {
    ZoteroItemDetailView(item: ZoteroItem(
        key: "ABC123",
        version: 1,
        library: ZoteroItem.ZoteroLibrary(type: "user", id: 123, name: "My Library"),
        data: ZoteroItemData(
            key: "ABC123",
            version: 1,
            itemType: .journalArticle,
            title: "A Sample Research Paper Title That Might Be Long",
            abstractNote: "This is a sample abstract that describes the research paper in detail.",
            creators: [
                ZoteroCreator(creatorType: "author", firstName: "John", lastName: "Doe", name: nil),
                ZoteroCreator(creatorType: "author", firstName: "Jane", lastName: "Smith", name: nil)
            ],
            tags: [ZoteroTag(tag: "machine learning"), ZoteroTag(tag: "AI")],
            date: "2024",
            dateAdded: nil,
            dateModified: nil,
            url: "https://example.com",
            DOI: "10.1234/example",
            publicationTitle: "Journal of Example Studies",
            volume: "42",
            issue: "3",
            pages: "123-456",
            publisher: nil,
            place: nil,
            note: nil,
            parentItem: nil,
            contentType: nil,
            filename: nil,
            linkMode: nil
        )
    ))
}
