//
//  TodoWidget.swift
//  OpenClawWidgets
//
//  Tasks-only widget showing pending TODOs with priority indicators.
//

import WidgetKit
import SwiftUI

// MARK: - Timeline Provider

struct TodoTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodoWidgetEntry {
        TodoWidgetEntry(
            date: Date(),
            todos: [
                WidgetTodoItem(id: UUID(), title: "Sample task", priority: .high, isCompleted: false, createdAt: Date()),
                WidgetTodoItem(id: UUID(), title: "Another task", priority: .medium, isCompleted: false, createdAt: Date()),
            ]
        )
    }
    
    func getSnapshot(in context: Context, completion: @escaping (TodoWidgetEntry) -> Void) {
        let todos = WidgetDataManager.shared.loadTodos()
        completion(TodoWidgetEntry(date: Date(), todos: todos))
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<TodoWidgetEntry>) -> Void) {
        let todos = WidgetDataManager.shared.loadTodos()
        let entry = TodoWidgetEntry(date: Date(), todos: todos)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Timeline Entry

struct TodoWidgetEntry: TimelineEntry {
    let date: Date
    let todos: [WidgetTodoItem]
}

// MARK: - Widget View

struct TodoWidgetEntryView: View {
    var entry: TodoWidgetEntry
    @Environment(\.widgetFamily) var family
    
    private var maxItems: Int {
        switch family {
        case .systemSmall: return 3
        case .systemMedium: return 5
        default: return 5
        }
    }
    
    var body: some View {
        if entry.todos.isEmpty {
            emptyState
        } else {
            todoList
        }
    }
    
    private var emptyState: some View {
        Link(destination: URL(string: "openclaw://todo")!) {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Color(red: 0.45, green: 0.75, blue: 0.55))
                Text("All clear!")
                    .font(.headline)
                    .foregroundStyle(Color(red: 0.95, green: 0.93, blue: 0.90))
                Text("No pending tasks")
                    .font(.caption)
                    .foregroundStyle(Color(red: 0.70, green: 0.66, blue: 0.62))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .widgetBackground()
    }
    
    private var todoList: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 4) {
                Image(systemName: "checklist")
                    .font(.caption2)
                    .foregroundStyle(Color(red: 0.85, green: 0.45, blue: 0.40))
                Text("Tasks")
                    .font(.caption2.bold())
                    .foregroundStyle(Color(red: 0.85, green: 0.45, blue: 0.40))
                Spacer()
                Text("\(entry.todos.count)")
                    .font(.caption2)
                    .foregroundStyle(Color(red: 0.70, green: 0.66, blue: 0.62))
            }
            .padding(.bottom, 6)
            
            // Task list
            VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 5) {
                ForEach(Array(entry.todos.prefix(maxItems))) { todo in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(priorityColor(todo.priority))
                            .frame(width: 6, height: 6)
                        
                        Text(todo.title)
                            .font(family == .systemSmall ? .caption : .caption)
                            .foregroundStyle(Color(red: 0.95, green: 0.93, blue: 0.90))
                            .lineLimit(1)
                    }
                }
            }
            
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetBackground()
    }
    
    private func priorityColor(_ priority: WidgetTodoPriority) -> Color {
        switch priority {
        case .high: return Color(red: 0.85, green: 0.40, blue: 0.40)
        case .medium: return Color(red: 0.90, green: 0.55, blue: 0.35)
        case .low: return Color(red: 0.45, green: 0.75, blue: 0.55)
        }
    }
}

// MARK: - Widget Configuration

struct TodoWidget: Widget {
    let kind: String = "TodoWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodoTimelineProvider()) { entry in
            TodoWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Tasks")
        .description("View your pending tasks at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])

    }
}

// MARK: - Widget Background Modifier

extension View {
    func widgetBackground() -> some View {
        if #available(iOS 17.0, *) {
            return self.containerBackground(for: .widget) {
                Color(red: 0.08, green: 0.07, blue: 0.06)
            }
        } else {
            return self
                .padding()
                .background(Color(red: 0.08, green: 0.07, blue: 0.06))
        }
    }
}

// MARK: - Deep Link

extension TodoWidgetEntryView {
    var widgetURL: URL {
        URL(string: "openclaw://todo")!
    }
}

#Preview(as: .systemSmall) {
    TodoWidget()
} timeline: {
    TodoWidgetEntry(date: .now, todos: [
        WidgetTodoItem(id: UUID(), title: "Review PR #42", priority: .high, isCompleted: false, createdAt: Date()),
        WidgetTodoItem(id: UUID(), title: "Update documentation", priority: .medium, isCompleted: false, createdAt: Date()),
        WidgetTodoItem(id: UUID(), title: "Clean up tests", priority: .low, isCompleted: false, createdAt: Date()),
    ])
    TodoWidgetEntry(date: .now, todos: [])
}
