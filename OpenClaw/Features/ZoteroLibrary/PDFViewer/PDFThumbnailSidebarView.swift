//
//  PDFThumbnailSidebarView.swift
//  OpenClaw
//
//  iPad sidebar showing PDF page thumbnails linked to the main PDFView
//

import SwiftUI
import PDFKit

struct PDFThumbnailSidebarView: UIViewRepresentable {
    let pdfView: PDFView
    
    func makeUIView(context: Context) -> PDFThumbnailView {
        let thumbnailView = PDFThumbnailView()
        thumbnailView.pdfView = pdfView
        thumbnailView.thumbnailSize = CGSize(width: 120, height: 160)
        thumbnailView.layoutMode = .vertical
        thumbnailView.backgroundColor = UIColor(Color.surfacePrimary)
        return thumbnailView
    }
    
    func updateUIView(_ uiView: PDFThumbnailView, context: Context) {
        if uiView.pdfView !== pdfView {
            uiView.pdfView = pdfView
        }
    }
}
