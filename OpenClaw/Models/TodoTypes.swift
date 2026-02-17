//
//  TodoTypes.swift
//  OpenClaw
//
//  Models for TODO list functionality
//

import Foundation

enum TodoPriority: String, Codable, CaseIterable {
    case high
    case medium
    case low
    
    var displayName: String {
        rawValue.capitalized
    }
}

struct TodoItem: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var description: String?
    var priority: TodoPriority
    var isCompleted: Bool
    var createdAt: Date
    var completedAt: Date?
    
    init(
        id: UUID = UUID(),
        title: String,
        description: String? = nil,
        priority: TodoPriority = .medium,
        isCompleted: Bool = false,
        createdAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.priority = priority
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.completedAt = completedAt
    }
    
    mutating func toggleCompleted() {
        isCompleted.toggle()
        completedAt = isCompleted ? Date() : nil
    }
}

struct TodoList: Codable {
    var items: [TodoItem]
    var lastSyncedAt: Date?
    
    init(items: [TodoItem] = [], lastSyncedAt: Date? = nil) {
        self.items = items
        self.lastSyncedAt = lastSyncedAt
    }
    
    // MARK: - Date Formatting
    
    private static let isoDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter
    }()
    
    private static func parseDate(_ string: String) -> Date? {
        return isoDateFormatter.date(from: string)
    }
    
    private static func formatDate(_ date: Date) -> String {
        return isoDateFormatter.string(from: date)
    }
    
    // MARK: - Markdown Parsing
    
    /// Parse from structured markdown format:
    /// ```
    /// # TODO
    ///
    /// ## Active
    /// - [ ] Task title
    ///   description: Optional longer description
    ///   priority: high|medium|low
    ///   created: 2024-02-15
    ///
    /// ## Completed
    /// - [x] Completed task
    ///   completed: 2024-02-10
    /// ```
    static func fromMarkdown(_ markdown: String) -> TodoList {
        var items: [TodoItem] = []
        let lines = markdown.components(separatedBy: .newlines)
        
        print("[TodoList] Parsing markdown with \(lines.count) lines")
        
        var currentItem: (title: String, isCompleted: Bool)?
        var currentDescription: String?
        var currentPriority: TodoPriority = .medium
        var currentCreated: Date = Date()
        var currentCompleted: Date?
        
        func saveCurrentItem() {
            if let item = currentItem {
                let todoItem = TodoItem(
                    title: item.title,
                    description: currentDescription,
                    priority: currentPriority,
                    isCompleted: item.isCompleted,
                    createdAt: currentCreated,
                    completedAt: currentCompleted
                )
                items.append(todoItem)
                print("[TodoList] Parsed item: '\(item.title)' completed: \(item.isCompleted)")
            }
            // Reset for next item
            currentItem = nil
            currentDescription = nil
            currentPriority = .medium
            currentCreated = Date()
            currentCompleted = nil
        }
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip empty lines and headers
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }
            
            // Check for checkbox item: - [ ] or - [x]
            if trimmed.hasPrefix("- [") {
                // Save previous item if exists
                saveCurrentItem()
                
                let isCompleted = trimmed.contains("[x]") || trimmed.contains("[X]")
                if let closingBracket = trimmed.firstIndex(of: "]") {
                    let startIndex = trimmed.index(after: closingBracket)
                    let title = String(trimmed[startIndex...]).trimmingCharacters(in: .whitespaces)
                    if !title.isEmpty {
                        currentItem = (title: title, isCompleted: isCompleted)
                    }
                }
                continue
            }
            
            // Check for metadata (indented lines with key: value)
            if (line.hasPrefix("  ") || line.hasPrefix("\t")) && currentItem != nil {
                let parts = trimmed.split(separator: ":", maxSplits: 1)
                if parts.count == 2 {
                    let key = String(parts[0]).lowercased().trimmingCharacters(in: .whitespaces)
                    let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
                    
                    switch key {
                    case "description", "desc":
                        currentDescription = value
                    case "priority":
                        currentPriority = TodoPriority(rawValue: value.lowercased()) ?? .medium
                    case "created":
                        currentCreated = parseDate(value) ?? Date()
                    case "completed":
                        currentCompleted = parseDate(value)
                    default:
                        break
                    }
                }
                continue
            }
        }
        
        // Don't forget the last item
        saveCurrentItem()
        
        print("[TodoList] Total parsed items: \(items.count)")
        return TodoList(items: items, lastSyncedAt: Date())
    }
    
    // MARK: - Markdown Serialization
    
    /// Convert to structured markdown format
    func toMarkdown(preservingOriginal original: String? = nil) -> String {
        var lines: [String] = ["# TODO", ""]
        
        let active = items.filter { !$0.isCompleted }
        let completed = items.filter { $0.isCompleted }
        
        // Active section
        lines.append("## Active")
        lines.append("")
        
        if active.isEmpty {
            lines.append("_No active tasks_")
            lines.append("")
        } else {
            for item in active {
                lines.append("- [ ] \(item.title)")
                if let desc = item.description, !desc.isEmpty {
                    lines.append("  description: \(desc)")
                }
                lines.append("  priority: \(item.priority.rawValue)")
                lines.append("  created: \(Self.formatDate(item.createdAt))")
                lines.append("")
            }
        }
        
        // Completed section
        lines.append("## Completed")
        lines.append("")
        
        if completed.isEmpty {
            lines.append("_No completed tasks_")
            lines.append("")
        } else {
            for item in completed {
                lines.append("- [x] \(item.title)")
                if let desc = item.description, !desc.isEmpty {
                    lines.append("  description: \(desc)")
                }
                if let completedAt = item.completedAt {
                    lines.append("  completed: \(Self.formatDate(completedAt))")
                }
                lines.append("")
            }
        }
        
        return lines.joined(separator: "\n")
    }
}
