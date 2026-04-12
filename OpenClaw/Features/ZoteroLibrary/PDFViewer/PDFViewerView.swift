//
//  PDFViewerView.swift
//  OpenClaw
//
//  Full PDF viewer with Apple Pencil annotation support, optimized for iPad
//

import SwiftUI
import PDFKit

struct PDFViewerView: View {
    let item: ZoteroItem
    let attachment: ZoteroItem
    
    @StateObject private var viewModel: PDFViewerViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showThumbnails = true
    @State private var annotationCache = AnnotationCache()
    @State private var pdfViewInstance: PDFView?
    
    init(item: ZoteroItem, attachment: ZoteroItem) {
        self.item = item
        self.attachment = attachment
        self._viewModel = StateObject(wrappedValue: PDFViewerViewModel(
            itemKey: item.key,
            attachmentKey: attachment.key,
            title: attachment.data.filename ?? item.data.displayTitle
        ))
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundDark.ignoresSafeArea()
                
                if viewModel.isLoading {
                    loadingView
                } else if let error = viewModel.errorMessage {
                    errorView(error)
                } else if viewModel.pdfDocument != nil {
                    pdfContent
                }
            }
            .navigationTitle(viewModel.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.backgroundDark, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.anthropicCoral)
                }
                
                ToolbarItem(placement: .principal) {
                    Text(viewModel.pageLabel)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Color.textSecondary)
                }
                
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if horizontalSizeClass == .regular {
                        Button {
                            withAnimation { showThumbnails.toggle() }
                        } label: {
                            Image(systemName: showThumbnails ? "sidebar.left" : "sidebar.leading")
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                    
                    Button {
                        viewModel.isAnnotating.toggle()
                    } label: {
                        Image(systemName: viewModel.isAnnotating ? "pencil.circle.fill" : "pencil.circle")
                            .foregroundStyle(viewModel.isAnnotating ? Color.anthropicCoral : Color.textSecondary)
                    }
                    
                    if let document = viewModel.pdfDocument {
                        ShareLink(item: document.documentURL ?? URL(fileURLWithPath: ""), preview: SharePreview(viewModel.title))
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
            .task {
                await annotationCache.preload(itemKey: attachment.key)
                await viewModel.loadDocument()
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - PDF Content
    
    @ViewBuilder
    private var pdfContent: some View {
        if horizontalSizeClass == .regular {
            // iPad: optional thumbnail sidebar + PDF viewer
            HStack(spacing: 0) {
                if showThumbnails, let pdfView = pdfViewInstance {
                    PDFThumbnailSidebarView(pdfView: pdfView)
                        .frame(width: 180)
                        .background(Color.surfacePrimary)
                        .transition(.move(edge: .leading))
                    
                    Divider()
                }
                
                pdfViewerContent
            }
            .animation(.easeInOut(duration: 0.25), value: showThumbnails)
        } else {
            // iPhone: full-screen PDF
            pdfViewerContent
        }
    }
    
    private var pdfViewerContent: some View {
        PDFViewRepresentable(
            document: viewModel.pdfDocument,
            currentPageIndex: $viewModel.currentPageIndex,
            isAnnotating: $viewModel.isAnnotating,
            itemKey: attachment.key,
            annotationCache: annotationCache,
            onPDFViewCreated: { pdfView in
                pdfViewInstance = pdfView
            }
        )
        .overlay(alignment: .top) {
            // Annotation mode indicator
            if viewModel.isAnnotating {
                HStack(spacing: 6) {
                    Image(systemName: "pencil.tip")
                        .font(.caption2)
                    Text("Annotation Mode")
                        .font(.caption2)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.anthropicCoral.opacity(0.9))
                .foregroundStyle(.white)
                .clipShape(Capsule())
                .padding(.top, 8)
            }
        }
    }
    
    // MARK: - Loading
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(Color.anthropicCoral)
                .scaleEffect(1.5)
            
            Text("Loading PDF...")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
            
            if viewModel.downloadProgress > 0 {
                ProgressView(value: viewModel.downloadProgress)
                    .tint(Color.anthropicCoral)
                    .frame(width: 200)
            }
        }
    }
    
    // MARK: - Error
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(Color.statusDisconnected)
            
            Text("Could not load PDF")
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
            
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Button {
                Task { await viewModel.loadDocument() }
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
}
