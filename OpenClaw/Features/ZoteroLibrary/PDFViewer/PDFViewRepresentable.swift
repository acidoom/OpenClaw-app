//
//  PDFViewRepresentable.swift
//  OpenClaw
//
//  UIViewControllerRepresentable wrapping PDFView with PencilKit annotation overlay
//

import SwiftUI
import PDFKit
import PencilKit

struct PDFViewRepresentable: UIViewControllerRepresentable {
    let document: PDFDocument?
    @Binding var currentPageIndex: Int
    @Binding var isAnnotating: Bool
    let itemKey: String
    let annotationCache: AnnotationCache
    var onPDFViewCreated: ((PDFView) -> Void)?
    
    func makeUIViewController(context: Context) -> PDFAnnotationViewController {
        let vc = PDFAnnotationViewController()
        vc.delegate = context.coordinator
        vc.itemKey = itemKey
        vc.annotationCache = annotationCache
        return vc
    }
    
    func updateUIViewController(_ vc: PDFAnnotationViewController, context: Context) {
        if vc.pdfView.document !== document {
            vc.pdfView.document = document
            onPDFViewCreated?(vc.pdfView)
        }
        vc.setAnnotationMode(isAnnotating)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    class Coordinator: NSObject, PDFAnnotationViewControllerDelegate {
        var parent: PDFViewRepresentable
        
        init(parent: PDFViewRepresentable) {
            self.parent = parent
        }
        
        func pageDidChange(to pageIndex: Int) {
            DispatchQueue.main.async {
                self.parent.currentPageIndex = pageIndex
            }
        }
    }
}

// MARK: - Delegate Protocol

protocol PDFAnnotationViewControllerDelegate: AnyObject {
    func pageDidChange(to pageIndex: Int)
}

// MARK: - PDF Annotation ViewController

class PDFAnnotationViewController: UIViewController {
    let pdfView = PDFView()
    private let canvasView = PKCanvasView()
    private let toolPicker = PKToolPicker()
    private var isAnnotating = false
    
    weak var delegate: PDFAnnotationViewControllerDelegate?
    var itemKey: String = ""
    var annotationCache: AnnotationCache?
    
    /// Track which page the annotation was drawn on
    private var annotatingPageIndex: Int = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupPDFView()
        setupCanvasView()
    }
    
    private func setupPDFView() {
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = UIColor(named: "backgroundDark") ?? .black
        pdfView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pdfView)
        
        NSLayoutConstraint.activate([
            pdfView.topAnchor.constraint(equalTo: view.topAnchor),
            pdfView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pdfView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(pageChanged),
            name: .PDFViewPageChanged,
            object: pdfView
        )
    }
    
    private func setupCanvasView() {
        canvasView.drawingPolicy = .pencilOnly
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.isScrollEnabled = false
        canvasView.bouncesZoom = false
        canvasView.minimumZoomScale = 1
        canvasView.maximumZoomScale = 1
        canvasView.tool = PKInkingTool(.pen, color: .systemBlue, width: 3)
        canvasView.translatesAutoresizingMaskIntoConstraints = false
        canvasView.isHidden = true
        canvasView.isUserInteractionEnabled = false
        
        view.addSubview(canvasView)
        
        NSLayoutConstraint.activate([
            canvasView.topAnchor.constraint(equalTo: view.topAnchor),
            canvasView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            canvasView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            canvasView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    @objc private func pageChanged() {
        guard let currentPage = pdfView.currentPage,
              let pageIndex = pdfView.document?.index(for: currentPage) else { return }
        delegate?.pageDidChange(to: pageIndex)
    }
    
    // MARK: - Annotation Mode
    
    func setAnnotationMode(_ annotating: Bool) {
        guard annotating != isAnnotating else { return }
        
        if annotating {
            enterAnnotationMode()
        } else {
            exitAnnotationMode()
        }
    }
    
    private func enterAnnotationMode() {
        isAnnotating = true
        
        // Record which page we're annotating
        if let currentPage = pdfView.currentPage,
           let pageIndex = pdfView.document?.index(for: currentPage) {
            annotatingPageIndex = pageIndex
        }
        
        // Load existing drawing for this page
        if let drawing = annotationCache?.loadDrawing(for: itemKey, pageIndex: annotatingPageIndex) {
            canvasView.drawing = drawing
        } else {
            canvasView.drawing = PKDrawing()
        }
        
        // Show canvas, disable PDF scrolling
        canvasView.isHidden = false
        canvasView.isUserInteractionEnabled = true
        
        // Disable PDF interaction so touches go to the canvas
        disablePDFInteraction(true)
        
        // Show tool picker
        toolPicker.addObserver(canvasView)
        toolPicker.setVisible(true, forFirstResponder: canvasView)
        canvasView.becomeFirstResponder()
    }
    
    private func exitAnnotationMode() {
        isAnnotating = false
        
        // Save drawing for the page
        if !canvasView.drawing.strokes.isEmpty {
            annotationCache?.saveDrawing(canvasView.drawing, for: itemKey, pageIndex: annotatingPageIndex)
        }
        
        // Hide tool picker
        toolPicker.setVisible(false, forFirstResponder: canvasView)
        toolPicker.removeObserver(canvasView)
        canvasView.resignFirstResponder()
        
        // Hide canvas, restore PDF scrolling
        canvasView.isHidden = true
        canvasView.isUserInteractionEnabled = false
        disablePDFInteraction(false)
    }
    
    /// Disable/enable PDFView's internal scroll view interaction
    private func disablePDFInteraction(_ disable: Bool) {
        // Walk the hierarchy to find the scroll view
        func findScrollView(in view: UIView) -> UIScrollView? {
            // Don't return the PKCanvasView (it's also a UIScrollView)
            if view is PKCanvasView { return nil }
            if let sv = view as? UIScrollView { return sv }
            for subview in view.subviews {
                if let found = findScrollView(in: subview) { return found }
            }
            return nil
        }
        
        if let scrollView = findScrollView(in: pdfView) {
            scrollView.isScrollEnabled = !disable
            scrollView.pinchGestureRecognizer?.isEnabled = !disable
        }
    }
}
