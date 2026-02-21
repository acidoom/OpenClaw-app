//
//  TodoListViewModel.swift
//  OpenClaw
//
//  ViewModel for TODO list management
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class TodoListViewModel: ObservableObject {
    @Published var todoList = TodoList()
    @Published var newItemTitle = ""
    @Published var isLoading = false
    @Published var isSyncing = false
    @Published var showError = false
    @Published var errorMessage: String?
    @Published var lastSyncStatus: SyncStatus = .none
    
    // Edit state - all fields
    @Published var editingItem: TodoItem?
    @Published var editingTitle = ""
    @Published var editingDescription = ""
    @Published var editingPriority: TodoPriority = .medium
    
    // Debug info
    @Published var debugInfo: String = ""
    
    enum SyncStatus {
        case none
        case success
        case failed
        case localOnly
    }
    
    private let todoService = TodoService.shared
    
    var pendingItems: [TodoItem] {
        todoList.items.filter { !$0.isCompleted }
    }
    
    var completedItems: [TodoItem] {
        todoList.items.filter { $0.isCompleted }
    }
    
    var hasItems: Bool {
        !todoList.items.isEmpty
    }
    
    // MARK: - Actions
    
    func loadTodos() async {
        isLoading = true
        print("[TodoVM] loadTodos started")
        
        do {
            todoList = try await todoService.sync()
            print("[TodoVM] Sync success - got \(todoList.items.count) items")
            for (i, item) in todoList.items.enumerated() {
                print("[TodoVM]   [\(i)] \(item.isCompleted ? "[x]" : "[ ]") \(item.title.prefix(40))... priority:\(item.priority.rawValue)")
            }
            lastSyncStatus = .success
            debugInfo = await todoService.getDebugInfo()
        } catch TodoServiceError.noEndpointConfigured {
            // Load local only
            todoList = await todoService.loadLocal()
            print("[TodoVM] No endpoint - loaded \(todoList.items.count) local items")
            lastSyncStatus = .localOnly
            debugInfo = await todoService.getDebugInfo()
        } catch {
            // Load local as fallback
            todoList = await todoService.loadLocal()
            print("[TodoVM] Error: \(error) - loaded \(todoList.items.count) local items")
            lastSyncStatus = .failed
            errorMessage = error.localizedDescription
            debugInfo = await todoService.getDebugInfo()
        }
        
        print("[TodoVM] loadTodos done - hasItems: \(hasItems), pending: \(pendingItems.count), completed: \(completedItems.count)")
        isLoading = false
    }
    
    func addItem() async {
        let title = newItemTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        
        let newItem = TodoItem(title: title, priority: .medium)
        todoList.items.insert(newItem, at: 0)
        newItemTitle = ""
        
        await saveAndSync()
    }
    
    func toggleItem(_ item: TodoItem) async {
        guard let index = todoList.items.firstIndex(where: { $0.id == item.id }) else { return }
        todoList.items[index].toggleCompleted()
        
        await saveAndSync()
    }
    
    func deleteItem(_ item: TodoItem) async {
        todoList.items.removeAll { $0.id == item.id }
        
        await saveAndSync()
    }
    
    func deleteItems(at offsets: IndexSet, from items: [TodoItem]) async {
        for offset in offsets {
            let item = items[offset]
            todoList.items.removeAll { $0.id == item.id }
        }
        
        await saveAndSync()
    }
    
    func clearCompleted() async {
        todoList.items.removeAll { $0.isCompleted }
        
        await saveAndSync()
    }
    
    func refresh() async {
        isSyncing = true
        await loadTodos()
        isSyncing = false
    }
    
    // MARK: - Edit Actions
    
    func startEditing(_ item: TodoItem) {
        editingItem = item
        editingTitle = item.title
        editingDescription = item.description ?? ""
        editingPriority = item.priority
    }
    
    func cancelEditing() {
        editingItem = nil
        editingTitle = ""
        editingDescription = ""
        editingPriority = .medium
    }
    
    func saveEdit() async {
        guard let item = editingItem else { return }
        let newTitle = editingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let newDescription = editingDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !newTitle.isEmpty else {
            cancelEditing()
            return
        }
        
        if let index = todoList.items.firstIndex(where: { $0.id == item.id }) {
            todoList.items[index].title = newTitle
            todoList.items[index].description = newDescription.isEmpty ? nil : newDescription
            todoList.items[index].priority = editingPriority
        }
        
        cancelEditing()
        await saveAndSync()
    }
    
    func updateItemTitle(_ item: TodoItem, newTitle: String) async {
        let trimmedTitle = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        
        if let index = todoList.items.firstIndex(where: { $0.id == item.id }) {
            todoList.items[index].title = trimmedTitle
        }
        
        await saveAndSync()
    }
    
    // MARK: - Reorder Actions
    
    func movePendingItems(from source: IndexSet, to destination: Int) async {
        // Get current pending items
        var pending = pendingItems
        
        // Perform the move on the pending array
        pending.move(fromOffsets: source, toOffset: destination)
        
        // Rebuild the full list: moved pending items + completed items
        let completed = completedItems
        todoList.items = pending + completed
        
        await saveAndSync()
    }
    
    func moveCompletedItems(from source: IndexSet, to destination: Int) async {
        // Get current completed items
        var completed = completedItems
        
        // Perform the move on the completed array
        completed.move(fromOffsets: source, toOffset: destination)
        
        // Rebuild the full list: pending items + moved completed items
        let pending = pendingItems
        todoList.items = pending + completed
        
        await saveAndSync()
    }
    
    // MARK: - Private
    
    private func saveAndSync() async {
        isSyncing = true
        print("[TodoVM] saveAndSync started with \(todoList.items.count) items")
        
        do {
            try await todoService.syncAndSave(todoList)
            lastSyncStatus = .success
            errorMessage = nil
            print("[TodoVM] saveAndSync success!")
        } catch TodoServiceError.noEndpointConfigured {
            await todoService.saveLocal(todoList)
            lastSyncStatus = .localOnly
            errorMessage = "No endpoint configured - saved locally only"
            print("[TodoVM] saveAndSync - no endpoint, saved locally")
        } catch {
            await todoService.saveLocal(todoList)
            lastSyncStatus = .failed
            errorMessage = "Sync failed: \(error.localizedDescription)"
            print("[TodoVM] saveAndSync failed: \(error)")
        }
        
        // Update debug info after save attempt
        debugInfo = await todoService.getDebugInfo()
        isSyncing = false
    }
}
