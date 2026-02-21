//
//  ZoteroLibraryViewModel.swift
//  OpenClaw
//
//  ViewModel for managing Zotero library state and operations
//

import Foundation
import Combine

@MainActor
final class ZoteroLibraryViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var items: [ZoteroItem] = []
    @Published var collections: [ZoteroCollection] = []
    @Published var selectedCollection: ZoteroCollection?
    @Published var searchQuery = ""
    @Published var sortField: ZoteroSortField = .dateModified
    @Published var sortDirection: ZoteroSortDirection = .desc
    
    @Published var isLoading = false
    @Published var isConfigured = false
    @Published var errorMessage: String?
    @Published var showCollectionPicker = false
    
    // MARK: - Private Properties
    
    private let service = ZoteroService.shared
    private let keychain = KeychainManager.shared
    private var cancellables = Set<AnyCancellable>()
    private var hasLoaded = false
    
    // MARK: - Computed Properties
    
    var filteredItems: [ZoteroItem] {
        var result = items
        
        // Filter by search query
        if !searchQuery.isEmpty {
            let query = searchQuery.lowercased()
            result = result.filter { item in
                item.data.displayTitle.lowercased().contains(query) ||
                item.data.authorsString.lowercased().contains(query) ||
                (item.data.abstractNote?.lowercased().contains(query) ?? false) ||
                (item.data.tags?.contains { $0.tag.lowercased().contains(query) } ?? false)
            }
        }
        
        return result
    }
    
    // MARK: - Initialization
    
    init() {
        checkConfiguration()
        setupSearchDebounce()
    }
    
    // MARK: - Configuration
    
    func checkConfiguration() {
        isConfigured = keychain.hasZoteroCredentials()
    }
    
    // MARK: - Data Loading
    
    func loadIfNeeded() async {
        guard isConfigured, !hasLoaded else { return }
        await refresh()
    }
    
    func refresh() async {
        guard isConfigured else {
            errorMessage = nil
            items = []
            collections = []
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            // Fetch collections and items in parallel
            async let collectionsTask = service.fetchCollections(forceRefresh: true)
            async let itemsTask = service.fetchItems(
                collectionKey: selectedCollection?.key,
                sort: sortField,
                direction: sortDirection,
                forceRefresh: true
            )
            
            let (fetchedCollections, fetchedItems) = try await (collectionsTask, itemsTask)
            
            collections = fetchedCollections.sorted { $0.name < $1.name }
            items = fetchedItems
            hasLoaded = true
            
        } catch {
            print("[ZoteroVM] Error: \(error)")
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    // MARK: - Collection Filtering
    
    func selectCollection(_ collection: ZoteroCollection?) async {
        selectedCollection = collection
        isLoading = true
        errorMessage = nil
        
        do {
            items = try await service.fetchItems(
                collectionKey: collection?.key,
                sort: sortField,
                direction: sortDirection,
                forceRefresh: true
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    // MARK: - Sorting
    
    func toggleSortDirection() {
        sortDirection = sortDirection == .desc ? .asc : .desc
        Task {
            await refresh()
        }
    }
    
    // MARK: - Search
    
    private func setupSearchDebounce() {
        $searchQuery
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] query in
                guard let self = self, !query.isEmpty else { return }
                Task {
                    await self.performSearch(query: query)
                }
            }
            .store(in: &cancellables)
        
        $sortField
            .dropFirst()
            .sink { [weak self] _ in
                guard let self = self else { return }
                Task {
                    await self.refresh()
                }
            }
            .store(in: &cancellables)
    }
    
    private func performSearch(query: String) async {
        guard isConfigured else { return }
        
        isLoading = true
        
        do {
            items = try await service.search(query: query)
        } catch {
            // Don't show error for search, just keep existing items
            print("[ZoteroVM] Search error: \(error)")
        }
        
        isLoading = false
    }
    
    // MARK: - Cache Management
    
    func clearData() {
        items = []
        collections = []
        selectedCollection = nil
        searchQuery = ""
        hasLoaded = false
        errorMessage = nil
        
        Task {
            await service.clearCache()
        }
    }
    
    // MARK: - Collection Hierarchy
    
    /// Get root-level collections (no parent)
    func getRootCollections() -> [ZoteroCollection] {
        collections
            .filter { $0.parentKey == nil }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    /// Get child collections of a specific collection
    func getChildCollections(of parent: ZoteroCollection) -> [ZoteroCollection] {
        collections
            .filter { $0.parentKey == parent.key }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    /// Get the full path from root to the given collection
    func getCollectionPath(for collection: ZoteroCollection) -> [ZoteroCollection] {
        var path: [ZoteroCollection] = [collection]
        var current = collection
        
        // Walk up the tree to build the path
        while let parentKey = current.parentKey,
              let parent = collections.first(where: { $0.key == parentKey }) {
            path.insert(parent, at: 0)
            current = parent
        }
        
        return path
    }
}
