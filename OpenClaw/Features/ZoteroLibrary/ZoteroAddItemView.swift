//
//  ZoteroAddItemView.swift
//  OpenClaw
//
//  View for creating new Zotero library items
//

import SwiftUI
import Combine

struct ZoteroAddItemView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ZoteroAddItemViewModel()
    
    let onItemCreated: (ZoteroItem) -> Void
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundDark.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Item Type Picker
                        itemTypePicker
                        
                        // Basic Info
                        basicInfoSection
                        
                        // Authors
                        authorsSection
                        
                        // Publication Details (for articles)
                        if viewModel.showPublicationFields {
                            publicationSection
                        }
                        
                        // Abstract
                        abstractSection
                        
                        // Tags
                        tagsSection
                    }
                    .padding()
                }
                
                if viewModel.isSaving {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(Color.anthropicCoral)
                }
            }
            .navigationTitle("Add Item")
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
                        Task {
                            if let item = await viewModel.save() {
                                onItemCreated(item)
                                dismiss()
                            }
                        }
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(viewModel.canSave ? Color.anthropicCoral : Color.textSecondary)
                    .disabled(!viewModel.canSave)
                }
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "An error occurred")
            }
        }
    }
    
    // MARK: - Item Type Picker
    
    private var itemTypePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ITEM TYPE")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Color.textSecondary)
                .tracking(0.5)
            
            Menu {
                ForEach(ZoteroAddItemViewModel.availableItemTypes, id: \.self) { type in
                    Button {
                        viewModel.selectedItemType = type
                    } label: {
                        HStack {
                            Image(systemName: type.iconName)
                            Text(type.displayName)
                            if viewModel.selectedItemType == type {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Image(systemName: viewModel.selectedItemType.iconName)
                        .foregroundStyle(Color.anthropicCoral)
                    Text(viewModel.selectedItemType.displayName)
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                .padding()
                .background(Color.surfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    
    // MARK: - Basic Info Section
    
    private var basicInfoSection: some View {
        VStack(spacing: 1) {
            FormTextField(label: "Title", text: $viewModel.title, placeholder: "Enter title")
            FormTextField(label: "URL", text: $viewModel.url, placeholder: "https://...")
            FormTextField(label: "DOI", text: $viewModel.doi, placeholder: "10.xxxx/xxxxx")
            FormTextField(label: "Date", text: $viewModel.date, placeholder: "YYYY or YYYY-MM-DD")
        }
        .background(Color.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Authors Section
    
    private var authorsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("AUTHORS")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.textSecondary)
                    .tracking(0.5)
                
                Spacer()
                
                Button {
                    viewModel.addAuthor()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Color.anthropicCoral)
                }
            }
            
            VStack(spacing: 1) {
                ForEach(viewModel.authors.indices, id: \.self) { index in
                    AuthorRow(
                        firstName: $viewModel.authors[index].firstName,
                        lastName: $viewModel.authors[index].lastName,
                        onDelete: {
                            viewModel.removeAuthor(at: index)
                        }
                    )
                }
                
                if viewModel.authors.isEmpty {
                    Text("No authors added")
                        .font(.subheadline)
                        .foregroundStyle(Color.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.surfacePrimary)
                }
            }
            .background(Color.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    // MARK: - Publication Section
    
    private var publicationSection: some View {
        VStack(spacing: 1) {
            FormTextField(label: "Publication", text: $viewModel.publicationTitle, placeholder: "Journal or book name")
            FormTextField(label: "Volume", text: $viewModel.volume, placeholder: "")
            FormTextField(label: "Issue", text: $viewModel.issue, placeholder: "")
            FormTextField(label: "Pages", text: $viewModel.pages, placeholder: "e.g., 1-15")
            FormTextField(label: "Publisher", text: $viewModel.publisher, placeholder: "")
        }
        .background(Color.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Abstract Section
    
    private var abstractSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ABSTRACT")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Color.textSecondary)
                .tracking(0.5)
            
            TextEditor(text: $viewModel.abstractNote)
                .frame(minHeight: 100)
                .padding(8)
                .background(Color.surfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(Color.textPrimary)
        }
    }
    
    // MARK: - Tags Section
    
    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("TAGS")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.textSecondary)
                    .tracking(0.5)
                
                Spacer()
            }
            
            HStack {
                TextField("Add tag...", text: $viewModel.newTag)
                    .textInputAutocapitalization(.never)
                    .foregroundStyle(Color.textPrimary)
                
                Button {
                    viewModel.addTag()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Color.anthropicCoral)
                }
                .disabled(viewModel.newTag.isEmpty)
            }
            .padding()
            .background(Color.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            if !viewModel.tags.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(viewModel.tags, id: \.self) { tag in
                        HStack(spacing: 4) {
                            Text(tag)
                                .font(.caption)
                            Button {
                                viewModel.removeTag(tag)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                            }
                        }
                        .foregroundStyle(Color.anthropicCoral)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.anthropicCoral.opacity(0.15))
                        .clipShape(Capsule())
                    }
                }
            }
        }
    }
}

// MARK: - Form Text Field

struct FormTextField: View {
    let label: String
    @Binding var text: String
    let placeholder: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
            
            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.never)
                .foregroundStyle(Color.textPrimary)
        }
        .padding()
        .background(Color.surfacePrimary)
    }
}

// MARK: - Author Row

struct AuthorRow: View {
    @Binding var firstName: String
    @Binding var lastName: String
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("First Name")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                TextField("First", text: $firstName)
                    .foregroundStyle(Color.textPrimary)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Last Name")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                TextField("Last", text: $lastName)
                    .foregroundStyle(Color.textPrimary)
            }
            
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(Color.statusDisconnected)
            }
        }
        .padding()
        .background(Color.surfacePrimary)
    }
}

// MARK: - View Model

@MainActor
final class ZoteroAddItemViewModel: ObservableObject {
    static let availableItemTypes: [ZoteroItemType] = [
        .journalArticle, .book, .bookSection, .conferencePaper,
        .thesis, .report, .webpage, .preprint, .document
    ]
    
    @Published var selectedItemType: ZoteroItemType = .journalArticle
    @Published var title = ""
    @Published var url = ""
    @Published var doi = ""
    @Published var date = ""
    @Published var publicationTitle = ""
    @Published var volume = ""
    @Published var issue = ""
    @Published var pages = ""
    @Published var publisher = ""
    @Published var abstractNote = ""
    @Published var authors: [AuthorInput] = []
    @Published var tags: [String] = []
    @Published var newTag = ""
    
    @Published var isSaving = false
    @Published var showError = false
    @Published var errorMessage: String?
    
    struct AuthorInput {
        var firstName: String = ""
        var lastName: String = ""
    }
    
    var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    var showPublicationFields: Bool {
        [.journalArticle, .magazineArticle, .newspaperArticle, .conferencePaper, .bookSection]
            .contains(selectedItemType)
    }
    
    func addAuthor() {
        authors.append(AuthorInput())
    }
    
    func removeAuthor(at index: Int) {
        guard index < authors.count else { return }
        authors.remove(at: index)
    }
    
    func addTag() {
        let tag = newTag.trimmingCharacters(in: .whitespaces)
        guard !tag.isEmpty, !tags.contains(tag) else { return }
        tags.append(tag)
        newTag = ""
    }
    
    func removeTag(_ tag: String) {
        tags.removeAll { $0 == tag }
    }
    
    func save() async -> ZoteroItem? {
        isSaving = true
        errorMessage = nil
        
        do {
            let creators = authors.compactMap { author -> ZoteroNewCreator? in
                let first = author.firstName.trimmingCharacters(in: .whitespaces)
                let last = author.lastName.trimmingCharacters(in: .whitespaces)
                guard !first.isEmpty || !last.isEmpty else { return nil }
                return ZoteroNewCreator(
                    creatorType: "author",
                    firstName: first.isEmpty ? nil : first,
                    lastName: last.isEmpty ? nil : last,
                    name: nil
                )
            }
            
            let tagItems = tags.map { ZoteroNewTag(tag: $0) }
            
            let newItem = ZoteroNewItem(
                itemType: selectedItemType.rawValue,
                title: title.trimmingCharacters(in: .whitespaces),
                creators: creators.isEmpty ? nil : creators,
                abstractNote: abstractNote.isEmpty ? nil : abstractNote,
                date: date.isEmpty ? nil : date,
                url: url.isEmpty ? nil : url,
                DOI: doi.isEmpty ? nil : doi,
                publicationTitle: publicationTitle.isEmpty ? nil : publicationTitle,
                volume: volume.isEmpty ? nil : volume,
                issue: issue.isEmpty ? nil : issue,
                pages: pages.isEmpty ? nil : pages,
                publisher: publisher.isEmpty ? nil : publisher,
                tags: tagItems.isEmpty ? nil : tagItems
            )
            
            let item = try await ZoteroService.shared.createItem(newItem)
            isSaving = false
            return item
            
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            isSaving = false
            return nil
        }
    }
}

#Preview {
    ZoteroAddItemView { _ in }
}
