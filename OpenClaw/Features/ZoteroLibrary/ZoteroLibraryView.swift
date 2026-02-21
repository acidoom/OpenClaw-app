//
//  ZoteroLibraryView.swift
//  OpenClaw
//
//  Main view for browsing Zotero library items and notes
//

import SwiftUI

struct ZoteroLibraryView: View {
    @StateObject private var viewModel = ZoteroLibraryViewModel()
    @State private var showingSettings = false
    @State private var selectedItem: ZoteroItem?
    @State private var showingAddItem = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundDark.ignoresSafeArea()
                
                if !viewModel.isConfigured {
                    notConfiguredView
                } else if viewModel.isLoading && viewModel.items.isEmpty {
                    loadingView
                } else if let error = viewModel.errorMessage, viewModel.items.isEmpty {
                    errorView(error)
                } else {
                    libraryContent
                }
            }
            .navigationTitle("Zotero")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.backgroundDark, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if viewModel.isConfigured {
                        Button {
                            showingAddItem = true
                        } label: {
                            Image(systemName: "plus")
                                .foregroundStyle(Color.anthropicCoral)
                        }
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showingSettings = true
                        } label: {
                            Label("Settings", systemImage: "gear")
                        }
                        
                        if viewModel.isConfigured {
                            Button {
                                Task { await viewModel.refresh() }
                            } label: {
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }
                            
                            Divider()
                            
                            Menu("Sort By") {
                                ForEach(ZoteroSortField.allCases, id: \.self) { field in
                                    Button {
                                        viewModel.sortField = field
                                    } label: {
                                        HStack {
                                            Text(field.displayName)
                                            if viewModel.sortField == field {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            }
                            
                            Button {
                                viewModel.toggleSortDirection()
                            } label: {
                                Label(
                                    viewModel.sortDirection == .desc ? "Oldest First" : "Newest First",
                                    systemImage: viewModel.sortDirection == .desc ? "arrow.up" : "arrow.down"
                                )
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(Color.anthropicCoral)
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                ZoteroSettingsSheet(viewModel: viewModel)
            }
            .sheet(item: $selectedItem) { item in
                ZoteroItemDetailView(item: item) { _ in
                    Task { await viewModel.refresh() }
                }
            }
            .sheet(isPresented: $showingAddItem) {
                ZoteroAddItemView { _ in
                    Task { await viewModel.refresh() }
                }
            }
            .task {
                await viewModel.loadIfNeeded()
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Not Configured View
    
    private var notConfiguredView: some View {
        VStack(spacing: 24) {
            Image(systemName: "books.vertical")
                .font(.system(size: 60))
                .foregroundStyle(Color.textSecondary)
            
            VStack(spacing: 8) {
                Text("Connect to Zotero")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.textPrimary)
                
                Text("Add your Zotero API key and User ID to sync your library")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            Button {
                showingSettings = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "gear")
                    Text("Configure Zotero")
                }
                .fontWeight(.semibold)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.anthropicCoral)
                .foregroundStyle(.white)
                .clipShape(Capsule())
            }
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(Color.anthropicCoral)
            
            Text("Loading library...")
                .foregroundStyle(Color.textSecondary)
        }
    }
    
    // MARK: - Error View
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(Color.statusDisconnected)
            
            Text("Failed to Load")
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
            
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Button {
                Task { await viewModel.refresh() }
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
        }
    }
    
    // MARK: - Library Content
    
    private var libraryContent: some View {
        VStack(spacing: 0) {
            // Search bar
            searchBar
            
            // Collection sidebar toggle and breadcrumb
            collectionHeader
            
            // Items list
            if viewModel.filteredItems.isEmpty && !viewModel.searchQuery.isEmpty {
                noResultsView
            } else {
                itemsList
            }
        }
        .sheet(isPresented: $viewModel.showCollectionPicker) {
            CollectionPickerSheet(viewModel: viewModel)
        }
    }
    
    private var collectionHeader: some View {
        Button {
            viewModel.showCollectionPicker = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(Color.anthropicCoral)
                
                if let collection = viewModel.selectedCollection {
                    // Show breadcrumb path
                    let path = viewModel.getCollectionPath(for: collection)
                    HStack(spacing: 4) {
                        ForEach(Array(path.enumerated()), id: \.element.key) { index, col in
                            if index > 0 {
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(Color.textTertiary)
                            }
                            Text(col.name)
                                .lineLimit(1)
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color.textPrimary)
                } else {
                    Text("All Items")
                        .font(.subheadline)
                        .foregroundStyle(Color.textPrimary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(12)
            .background(Color.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    
    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.textSecondary)
            
            TextField("Search papers...", text: $viewModel.searchQuery)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(Color.textPrimary)
            
            if !viewModel.searchQuery.isEmpty {
                Button {
                    viewModel.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .padding(12)
        .background(Color.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    

    
    private var itemsList: some View {
        List {
            ForEach(viewModel.filteredItems) { item in
                ZoteroItemRow(item: item)
                    .listRowBackground(Color.surfacePrimary)
                    .listRowSeparatorTint(Color.surfaceSecondary)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedItem = item
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable {
            await viewModel.refresh()
        }
    }
    
    private var noResultsView: some View {
        VStack(spacing: 12) {
            Spacer()
            
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(Color.textSecondary)
            
            Text("No Results")
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
            
            Text("Try a different search term")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
            
            Spacer()
        }
    }
}

// MARK: - Collection Picker Sheet

struct CollectionPickerSheet: View {
    @ObservedObject var viewModel: ZoteroLibraryViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundDark.ignoresSafeArea()
                
                List {
                    // All Items option
                    Button {
                        viewModel.selectedCollection = nil
                        dismiss()
                        Task { await viewModel.selectCollection(nil) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "tray.full.fill")
                                .foregroundStyle(Color.anthropicCoral)
                                .frame(width: 24)
                            
                            Text("All Items")
                                .foregroundStyle(Color.textPrimary)
                            
                            Spacer()
                            
                            if viewModel.selectedCollection == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.anthropicCoral)
                            }
                        }
                    }
                    .listRowBackground(Color.surfacePrimary)
                    
                    // Root level collections
                    let rootCollections = viewModel.getRootCollections()
                    if !rootCollections.isEmpty {
                        Section {
                            ForEach(rootCollections) { collection in
                                CollectionRow(
                                    collection: collection,
                                    viewModel: viewModel,
                                    depth: 0,
                                    onSelect: {
                                        dismiss()
                                    }
                                )
                            }
                        } header: {
                            Text("Collections")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.textSecondary)
                        }
                        .listRowBackground(Color.surfacePrimary)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Collections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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

// MARK: - Collection Row (Recursive)

struct CollectionRow: View {
    let collection: ZoteroCollection
    @ObservedObject var viewModel: ZoteroLibraryViewModel
    let depth: Int
    let onSelect: () -> Void
    
    @State private var isExpanded = false
    
    private var children: [ZoteroCollection] {
        viewModel.getChildCollections(of: collection)
    }
    
    private var hasChildren: Bool {
        !children.isEmpty
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Collection row
            HStack(spacing: 8) {
                // Expand/collapse button
                if hasChildren {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                            .frame(width: 20)
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer()
                        .frame(width: 20)
                }
                
                // Folder icon
                Image(systemName: isExpanded ? "folder.fill" : "folder")
                    .foregroundStyle(Color.anthropicCoral)
                    .frame(width: 20)
                
                // Collection name
                Button {
                    viewModel.selectedCollection = collection
                    Task { await viewModel.selectCollection(collection) }
                    onSelect()
                } label: {
                    HStack {
                        Text(collection.name)
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        if viewModel.selectedCollection?.key == collection.key {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.anthropicCoral)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, CGFloat(depth) * 16)
            .padding(.vertical, 10)
            
            // Children (when expanded)
            if isExpanded && hasChildren {
                VStack(spacing: 0) {
                    ForEach(children) { child in
                        CollectionRow(
                            collection: child,
                            viewModel: viewModel,
                            depth: depth + 1,
                            onSelect: onSelect
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Zotero Item Row

struct ZoteroItemRow: View {
    let item: ZoteroItem
    
    var body: some View {
        HStack(spacing: 12) {
            // Type icon
            Image(systemName: item.data.itemType.iconName)
                .font(.title3)
                .foregroundStyle(Color.anthropicCoral)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                // Title
                Text(item.data.displayTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                
                // Authors and year
                HStack(spacing: 4) {
                    if !item.data.authorsString.isEmpty {
                        Text(item.data.authorsString)
                            .lineLimit(1)
                    }
                    if let year = item.data.formattedDate {
                        Text("•")
                        Text(year)
                    }
                }
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                
                // Publication
                if let publication = item.data.publicationTitle, !publication.isEmpty {
                    Text(publication)
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)
                }
                
                // Tags
                if let tags = item.data.tags, !tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(tags.prefix(3)) { tag in
                            Text(tag.tag)
                                .font(.caption2)
                                .foregroundStyle(Color.anthropicCoral)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.anthropicCoral.opacity(0.15))
                                .clipShape(Capsule())
                        }
                        if tags.count > 3 {
                            Text("+\(tags.count - 3)")
                                .font(.caption2)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Zotero Settings Sheet

struct ZoteroSettingsSheet: View {
    @ObservedObject var viewModel: ZoteroLibraryViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var apiKey = ""
    @State private var userId = ""
    @State private var isTesting = false
    @State private var testResult: Result<Bool, Error>?
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundDark.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Instructions
                        VStack(alignment: .leading, spacing: 8) {
                            Text("To connect your Zotero library:")
                                .font(.subheadline)
                                .foregroundStyle(Color.textPrimary)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                instructionRow(number: 1, text: "Go to zotero.org/settings/keys")
                                instructionRow(number: 2, text: "Create a new API key with read access")
                                instructionRow(number: 3, text: "Copy your API key and User ID")
                            }
                        }
                        .padding()
                        .background(Color.surfaceSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        
                        // Form
                        VStack(spacing: 16) {
                            SettingsTextField(
                                label: "User ID",
                                placeholder: "Your numeric user ID",
                                text: $userId
                            )
                            .keyboardType(.numberPad)
                            
                            SettingsSecureField(
                                label: "API Key",
                                placeholder: "Your Zotero API key",
                                text: $apiKey
                            )
                        }
                        .background(Color.surfaceSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        
                        // Test & Save buttons
                        VStack(spacing: 12) {
                            Button {
                                testConnection()
                            } label: {
                                HStack(spacing: 8) {
                                    if isTesting {
                                        ProgressView()
                                            .tint(.white)
                                    } else if case .success = testResult {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    } else if case .failure = testResult {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.red)
                                    }
                                    Text("Test Connection")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.surfaceSecondary)
                                .foregroundStyle(Color.textPrimary)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .disabled(apiKey.isEmpty || userId.isEmpty || isTesting)
                            
                            Button {
                                saveCredentials()
                            } label: {
                                Text("Save")
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(canSave ? Color.anthropicCoral : Color.surfaceSecondary)
                                    .foregroundStyle(canSave ? .white : Color.textSecondary)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .disabled(!canSave)
                        }
                        
                        // Error message
                        if case .failure(let error) = testResult {
                            Text(error.localizedDescription)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                        }
                        
                        // Clear credentials
                        if viewModel.isConfigured {
                            Button(role: .destructive) {
                                clearCredentials()
                            } label: {
                                Text("Disconnect Zotero")
                                    .fontWeight(.medium)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.statusDisconnected.opacity(0.15))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .foregroundStyle(Color.statusDisconnected)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Zotero Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(Color.anthropicCoral)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            loadExistingCredentials()
        }
    }
    
    private var canSave: Bool {
        !apiKey.isEmpty && !userId.isEmpty
    }
    
    private func instructionRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .font(.caption)
                .foregroundStyle(Color.anthropicCoral)
            Text(text)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        }
    }
    
    private func loadExistingCredentials() {
        if let existingKey = try? KeychainManager.shared.getZoteroApiKey() {
            apiKey = existingKey
        }
        if let existingId = try? KeychainManager.shared.getZoteroUserId() {
            userId = existingId
        }
    }
    
    private func testConnection() {
        isTesting = true
        testResult = nil
        
        Task {
            do {
                try KeychainManager.shared.saveZoteroCredentials(apiKey: apiKey, userId: userId)
                _ = try await ZoteroService.shared.testConnection()
                testResult = .success(true)
            } catch {
                testResult = .failure(error)
            }
            isTesting = false
        }
    }
    
    private func saveCredentials() {
        do {
            try KeychainManager.shared.saveZoteroCredentials(apiKey: apiKey, userId: userId)
            viewModel.checkConfiguration()
            Task {
                await viewModel.refresh()
            }
            dismiss()
        } catch {
            testResult = .failure(error)
        }
    }
    
    private func clearCredentials() {
        try? KeychainManager.shared.clearZoteroCredentials()
        apiKey = ""
        userId = ""
        viewModel.checkConfiguration()
        viewModel.clearData()
    }
}

#Preview {
    ZoteroLibraryView()
}
