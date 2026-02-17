//
//  TodoListView.swift
//  OpenClaw
//
//  Simple TODO list interface synced with Gateway TODO.md
//

import SwiftUI

struct TodoListView: View {
    @StateObject private var viewModel = TodoListViewModel()
    @FocusState private var isInputFocused: Bool
    @State private var showDebugInfo = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundDark
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Sync status bar (tap to show debug info)
                    SyncStatusBar(
                        status: viewModel.lastSyncStatus,
                        isSyncing: viewModel.isSyncing
                    )
                    .onTapGesture {
                        showDebugInfo = true
                    }
                    
                    if viewModel.isLoading {
                        Spacer()
                        ProgressView()
                            .tint(.anthropicCoral)
                            .scaleEffect(1.2)
                        Spacer()
                    } else {
                        // Todo list (always show, with empty state message if no items)
                        List {
                            // Add new item section
                            Section {
                                AddTodoRow(
                                    text: $viewModel.newItemTitle,
                                    isFocused: $isInputFocused,
                                    onSubmit: {
                                        Task { await viewModel.addItem() }
                                    }
                                )
                            }
                            .listRowBackground(Color.surfacePrimary)
                            
                            // Empty state message
                            if !viewModel.hasItems {
                                Section {
                                    VStack(spacing: 12) {
                                        Image(systemName: "checklist")
                                            .font(.system(size: 40))
                                            .foregroundStyle(Color.textTertiary)
                                        Text("No tasks yet")
                                            .font(.subheadline)
                                            .foregroundStyle(Color.textSecondary)
                                        Text("Add your first task above")
                                            .font(.caption)
                                            .foregroundStyle(Color.textTertiary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 32)
                                }
                                .listRowBackground(Color.clear)
                            }
                            
                            // Pending items
                            if !viewModel.pendingItems.isEmpty {
                                Section {
                                    ForEach(viewModel.pendingItems) { item in
                                        TodoItemRow(
                                            item: item,
                                            onToggle: {
                                                Task { await viewModel.toggleItem(item) }
                                            },
                                            onEdit: {
                                                viewModel.startEditing(item)
                                            }
                                        )
                                    }
                                    .onDelete { offsets in
                                        Task { await viewModel.deleteItems(at: offsets, from: viewModel.pendingItems) }
                                    }
                                } header: {
                                    Text("Active")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(Color.textSecondary)
                                }
                                .listRowBackground(Color.surfacePrimary)
                            }
                            
                            // Completed items
                            if !viewModel.completedItems.isEmpty {
                                Section {
                                    ForEach(viewModel.completedItems) { item in
                                        TodoItemRow(
                                            item: item,
                                            onToggle: {
                                                Task { await viewModel.toggleItem(item) }
                                            },
                                            onEdit: {
                                                viewModel.startEditing(item)
                                            }
                                        )
                                    }
                                    .onDelete { offsets in
                                        Task { await viewModel.deleteItems(at: offsets, from: viewModel.completedItems) }
                                    }
                                } header: {
                                    HStack {
                                        Text("Completed")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(Color.textSecondary)
                                        
                                        Spacer()
                                        
                                        Button("Clear") {
                                            Task { await viewModel.clearCompleted() }
                                        }
                                        .font(.caption)
                                        .foregroundStyle(Color.anthropicCoral)
                                    }
                                }
                                .listRowBackground(Color.surfacePrimary)
                            }
                        }
                        .listStyle(.insetGrouped)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("TODO")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.backgroundDark, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await viewModel.refresh() }
                    } label: {
                        if viewModel.isSyncing {
                            ProgressView()
                                .tint(.textSecondary)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(.textSecondary)
                        }
                    }
                    .disabled(viewModel.isSyncing)
                }
            }
            .task {
                await viewModel.loadTodos()
            }
            .refreshable {
                await viewModel.refresh()
            }
            .sheet(item: $viewModel.editingItem) { item in
                EditTodoSheet(
                    viewModel: viewModel,
                    item: item
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .alert("Debug Info", isPresented: $showDebugInfo) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.debugInfo)
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Sync Status Bar

struct SyncStatusBar: View {
    let status: TodoListViewModel.SyncStatus
    let isSyncing: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            
            Text(statusText)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
            
            Spacer()
            
            if isSyncing {
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(.textSecondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color.surfacePrimary.opacity(0.8))
    }
    
    private var statusColor: Color {
        switch status {
        case .none:
            return .textTertiary
        case .success:
            return .statusConnected
        case .failed:
            return .statusDisconnected
        case .localOnly:
            return .statusConnecting
        }
    }
    
    private var statusText: String {
        switch status {
        case .none:
            return "Not synced"
        case .success:
            return "Synced with Gateway"
        case .failed:
            return "Sync failed - local only"
        case .localOnly:
            return "Local only - no endpoint configured"
        }
    }
}

// MARK: - Add Todo Row

struct AddTodoRow: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.anthropicCoral)
            
            TextField("Add a new task...", text: $text)
                .focused(isFocused)
                .foregroundStyle(Color.textPrimary)
                .submitLabel(.done)
                .onSubmit(onSubmit)
            
            if !text.isEmpty {
                Button(action: onSubmit) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.anthropicCoral)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Todo Item Row

struct TodoItemRow: View {
    let item: TodoItem
    let onToggle: () -> Void
    let onEdit: () -> Void
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter
    }()
    
    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(item.isCompleted ? Color.statusConnected : Color.textTertiary)
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading, spacing: 4) {
                // Title
                Text(item.title)
                    .foregroundStyle(item.isCompleted ? Color.textTertiary : Color.textPrimary)
                    .strikethrough(item.isCompleted, color: .textTertiary)
                
                // Description (if present)
                if let description = item.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(2)
                }
                
                // Metadata row
                HStack(spacing: 8) {
                    // Priority badge
                    PriorityBadge(priority: item.priority)
                    
                    // Created date
                    Label(dateFormatter.string(from: item.createdAt), systemImage: "calendar")
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                    
                    // Completed date (if applicable)
                    if let completedAt = item.completedAt {
                        Label(dateFormatter.string(from: completedAt), systemImage: "checkmark.circle")
                            .font(.caption2)
                            .foregroundStyle(Color.statusConnected)
                    }
                }
            }
            
            Spacer()
            
            Button(action: onEdit) {
                Image(systemName: "chevron.right")
                    .font(.subheadline)
                    .foregroundStyle(Color.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

// MARK: - Priority Badge

struct PriorityBadge: View {
    let priority: TodoPriority
    
    var body: some View {
        Text(priority.displayName)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(priorityColor.opacity(0.2))
            .foregroundStyle(priorityColor)
            .clipShape(Capsule())
    }
    
    private var priorityColor: Color {
        switch priority {
        case .high:
            return .statusDisconnected
        case .medium:
            return .statusConnecting
        case .low:
            return .statusConnected
        }
    }
}

// MARK: - Edit Todo Sheet

struct EditTodoSheet: View {
    @ObservedObject var viewModel: TodoListViewModel
    let item: TodoItem
    
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?
    
    enum Field {
        case title, description
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundDark
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Title
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Title")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(Color.textSecondary)
                            
                            TextField("Task title", text: $viewModel.editingTitle, axis: .vertical)
                                .focused($focusedField, equals: .title)
                                .textFieldStyle(.plain)
                                .padding()
                                .background(Color.surfaceSecondary)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(Color.textPrimary)
                        }
                        
                        // Description
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Description")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(Color.textSecondary)
                            
                            TextField("Optional description...", text: $viewModel.editingDescription, axis: .vertical)
                                .focused($focusedField, equals: .description)
                                .textFieldStyle(.plain)
                                .lineLimit(3...6)
                                .padding()
                                .background(Color.surfaceSecondary)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(Color.textPrimary)
                        }
                        
                        // Priority
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Priority")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(Color.textSecondary)
                            
                            HStack(spacing: 12) {
                                ForEach(TodoPriority.allCases, id: \.self) { priority in
                                    PriorityButton(
                                        priority: priority,
                                        isSelected: viewModel.editingPriority == priority,
                                        onTap: {
                                            viewModel.editingPriority = priority
                                        }
                                    )
                                }
                            }
                        }
                        
                        // Dates (read-only display)
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Dates")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(Color.textSecondary)
                            
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Created")
                                        .font(.caption2)
                                        .foregroundStyle(Color.textTertiary)
                                    Text(formatDate(item.createdAt))
                                        .font(.subheadline)
                                        .foregroundStyle(Color.textPrimary)
                                }
                                
                                Spacer()
                                
                                if let completedAt = item.completedAt {
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text("Completed")
                                            .font(.caption2)
                                            .foregroundStyle(Color.textTertiary)
                                        Text(formatDate(completedAt))
                                            .font(.subheadline)
                                            .foregroundStyle(Color.statusConnected)
                                    }
                                }
                            }
                            .padding()
                            .background(Color.surfaceSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        
                        // Status toggle
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Status")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(Color.textSecondary)
                            
                            Button {
                                Task {
                                    await viewModel.toggleItem(item)
                                    dismiss()
                                }
                            } label: {
                                HStack {
                                    Image(systemName: item.isCompleted ? "arrow.uturn.backward.circle" : "checkmark.circle")
                                    Text(item.isCompleted ? "Mark as Active" : "Mark as Completed")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(item.isCompleted ? Color.statusConnecting.opacity(0.15) : Color.statusConnected.opacity(0.15))
                                .foregroundStyle(item.isCompleted ? Color.statusConnecting : Color.statusConnected)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        
                        Spacer(minLength: 20)
                        
                        // Delete button
                        Button(role: .destructive) {
                            Task {
                                await viewModel.deleteItem(item)
                                dismiss()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("Delete Task")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.statusDisconnected.opacity(0.15))
                            .foregroundStyle(Color.statusDisconnected)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.backgroundDark, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        viewModel.cancelEditing()
                        dismiss()
                    }
                    .foregroundStyle(Color.textSecondary)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        Task {
                            await viewModel.saveEdit()
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.anthropicCoral)
                    .disabled(viewModel.editingTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                focusedField = .title
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Priority Button

struct PriorityButton: View {
    let priority: TodoPriority
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            Text(priority.displayName)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(isSelected ? priorityColor.opacity(0.2) : Color.surfaceSecondary)
                .foregroundStyle(isSelected ? priorityColor : Color.textSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSelected ? priorityColor : Color.clear, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
    }
    
    private var priorityColor: Color {
        switch priority {
        case .high:
            return .statusDisconnected
        case .medium:
            return .statusConnecting
        case .low:
            return .statusConnected
        }
    }
}

#Preview {
    TodoListView()
}
