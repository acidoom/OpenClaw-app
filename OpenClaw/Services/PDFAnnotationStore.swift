//
//  PDFAnnotationStore.swift
//  OpenClaw
//
//  Persists PencilKit drawings per PDF page for Zotero annotations
//

import Foundation
import PencilKit

// MARK: - Thread-safe Annotation Cache

/// Synchronous in-memory cache for PKDrawings, accessible from PDFPageOverlayViewProvider callbacks.
/// Persists changes asynchronously to PDFAnnotationStore.
final class AnnotationCache: @unchecked Sendable {
    private var drawings: [String: [Int: PKDrawing]] = [:]
    private let queue = DispatchQueue(label: "com.openclaw.annotationCache")
    
    func loadDrawing(for itemKey: String, pageIndex: Int) -> PKDrawing? {
        queue.sync { drawings[itemKey]?[pageIndex] }
    }
    
    func saveDrawing(_ drawing: PKDrawing, for itemKey: String, pageIndex: Int) {
        queue.sync { drawings[itemKey, default: [:]][pageIndex] = drawing }
        // Persist asynchronously
        Task { await PDFAnnotationStore.shared.saveDrawing(drawing, for: itemKey, pageIndex: pageIndex) }
    }
    
    func preload(itemKey: String) async {
        let allDrawings = await PDFAnnotationStore.shared.loadAllDrawings(for: itemKey)
        queue.sync { drawings[itemKey] = allDrawings }
    }
    
    func clear(itemKey: String) {
        _ = queue.sync { drawings.removeValue(forKey: itemKey) }
    }
}

// MARK: - Persistent Annotation Store

actor PDFAnnotationStore {
    static let shared = PDFAnnotationStore()
    
    private let fileManager = FileManager.default
    
    private var annotationsDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("ZoteroAnnotations", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    private init() {}
    
    private func itemDirectory(for itemKey: String) -> URL {
        let dir = annotationsDirectory.appendingPathComponent(itemKey, isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    private func drawingFileURL(for itemKey: String, pageIndex: Int) -> URL {
        itemDirectory(for: itemKey).appendingPathComponent("page_\(pageIndex).drawing")
    }
    
    // MARK: - Save/Load
    
    func saveDrawing(_ drawing: PKDrawing, for itemKey: String, pageIndex: Int) {
        let fileURL = drawingFileURL(for: itemKey, pageIndex: pageIndex)
        let data = drawing.dataRepresentation()
        do {
            try data.write(to: fileURL)
        } catch {
            print("[PDFAnnotations] Save error for \(itemKey) page \(pageIndex): \(error)")
        }
    }
    
    func loadDrawing(for itemKey: String, pageIndex: Int) -> PKDrawing? {
        let fileURL = drawingFileURL(for: itemKey, pageIndex: pageIndex)
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? PKDrawing(data: data)
    }
    
    func loadAllDrawings(for itemKey: String) -> [Int: PKDrawing] {
        let dir = itemDirectory(for: itemKey)
        guard let contents = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return [:]
        }
        
        var result: [Int: PKDrawing] = [:]
        for fileURL in contents where fileURL.pathExtension == "drawing" {
            let name = fileURL.deletingPathExtension().lastPathComponent
            if let pageIndex = Int(name.replacingOccurrences(of: "page_", with: "")),
               let data = try? Data(contentsOf: fileURL),
               let drawing = try? PKDrawing(data: data) {
                result[pageIndex] = drawing
            }
        }
        
        print("[PDFAnnotations] Loaded \(result.count) drawings for \(itemKey)")
        return result
    }
    
    // MARK: - Management
    
    func hasAnnotations(for itemKey: String) -> Bool {
        let dir = itemDirectory(for: itemKey)
        guard let contents = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return false
        }
        return contents.contains { $0.pathExtension == "drawing" }
    }
    
    func deleteAnnotations(for itemKey: String) {
        let dir = itemDirectory(for: itemKey)
        try? fileManager.removeItem(at: dir)
        print("[PDFAnnotations] Deleted annotations for \(itemKey)")
    }
}
