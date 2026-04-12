//
//  PDFViewerViewModel.swift
//  OpenClaw
//
//  ViewModel managing PDF document loading and viewer state
//

import SwiftUI
import Combine
import PDFKit

@MainActor
final class PDFViewerViewModel: ObservableObject {
    @Published var pdfDocument: PDFDocument?
    @Published var isLoading = false
    @Published var downloadProgress: Double = 0
    @Published var errorMessage: String?
    @Published var currentPageIndex: Int = 0
    @Published var totalPages: Int = 0
    @Published var isAnnotating: Bool = false
    @Published var showSearch: Bool = false
    @Published var searchText: String = ""
    
    let itemKey: String
    let attachmentKey: String
    let title: String
    
    init(itemKey: String, attachmentKey: String, title: String) {
        self.itemKey = itemKey
        self.attachmentKey = attachmentKey
        self.title = title
    }
    
    func loadDocument() async {
        guard pdfDocument == nil else { return }
        isLoading = true
        errorMessage = nil
        
        do {
            let fileURL = try await PDFCacheManager.shared.downloadAndCache(itemKey: attachmentKey)
            
            guard let document = PDFDocument(url: fileURL) else {
                errorMessage = "Could not open PDF file"
                isLoading = false
                return
            }
            
            pdfDocument = document
            totalPages = document.pageCount
            print("[PDFViewer] Loaded document: \(totalPages) pages")
        } catch {
            errorMessage = error.localizedDescription
            print("[PDFViewer] Load error: \(error)")
        }
        
        isLoading = false
    }
    
    var pageLabel: String {
        guard totalPages > 0 else { return "" }
        return "Page \(currentPageIndex + 1) of \(totalPages)"
    }
}
