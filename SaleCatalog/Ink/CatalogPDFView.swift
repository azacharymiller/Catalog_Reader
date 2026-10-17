import PDFKit
import PencilKit
import SwiftUI

/// The catalog PDF with a PencilKit layer on every page.
/// The Pencil writes; fingers turn pages and zoom. A double tap on the
/// Pencil switches between pen and eraser.
struct CatalogPDFView: UIViewRepresentable {
    let document: PDFDocument
    @Binding var pageIndex: Int
    var canDraw: (Int) -> Bool
    var drawingForPage: (Int) -> PKDrawing
    var saveDrawing: (Int, PKDrawing) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        // The overlay provider must be set before the document.
        view.pageOverlayViewProvider = context.coordinator
        view.document = document
        view.displayMode = .singlePage
        view.displayDirection = .horizontal
        view.usePageViewController(true, withViewOptions: nil)
        view.autoScales = true
        view.isInMarkupMode = true

        let pencil = UIPencilInteraction()
        pencil.delegate = context.coordinator
        view.addInteraction(pencil)

        context.coordinator.pdfView = view
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged),
            name: .PDFViewPageChanged,
            object: view
        )
        if let page = document.page(at: pageIndex) { view.go(to: page) }
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        context.coordinator.parent = self
        if let current = view.currentPage,
           document.index(for: current) != pageIndex,
           let page = document.page(at: pageIndex) {
            view.go(to: page)
        }
    }

    static func dismantleUIView(_ view: PDFView, coordinator: Coordinator) {
        coordinator.saveAll()
    }

    @MainActor
    final class Coordinator: NSObject, PDFPageOverlayViewProvider, PKCanvasViewDelegate, UIPencilInteractionDelegate {
        var parent: CatalogPDFView
        weak var pdfView: PDFView?
        private var canvases: [Int: PKCanvasView] = [:]
        private var pendingSaves: [Int: Task<Void, Never>] = [:]
        private var erasing = false

        init(_ parent: CatalogPDFView) { self.parent = parent }

        private var currentTool: PKTool {
            erasing ? PKEraserTool(.vector) : PKInkingTool(.pen, color: .systemBlue, width: 2)
        }

        func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> UIView? {
            let index = parent.document.index(for: page)
            if let existing = canvases[index] { return existing }
            let canvas = PKCanvasView()
            canvas.backgroundColor = .clear
            canvas.isOpaque = false
            canvas.drawingPolicy = .pencilOnly
            canvas.tool = currentTool
            canvas.tag = index
            canvas.isUserInteractionEnabled = parent.canDraw(index)
            canvas.drawing = parent.drawingForPage(index)
            canvas.delegate = self
            canvases[index] = canvas
            return canvas
        }

        func pdfView(_ pdfView: PDFView, willEndDisplayingOverlayView overlayView: UIView, for page: PDFPage) {
            guard let canvas = overlayView as? PKCanvasView else { return }
            pendingSaves[canvas.tag]?.cancel()
            parent.saveDrawing(canvas.tag, canvas.drawing)
            canvases[canvas.tag] = nil
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            let index = canvasView.tag
            pendingSaves[index]?.cancel()
            pendingSaves[index] = Task { [weak self, weak canvasView] in
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self, let canvasView else { return }
                self.parent.saveDrawing(index, canvasView.drawing)
            }
        }

        func saveAll() {
            for (index, canvas) in canvases {
                pendingSaves[index]?.cancel()
                parent.saveDrawing(index, canvas.drawing)
            }
        }

        func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
            erasing.toggle()
            canvases.values.forEach { $0.tool = currentTool }
        }

        @objc func pageChanged() {
            guard let page = pdfView?.currentPage else { return }
            let index = parent.document.index(for: page)
            guard index != parent.pageIndex else { return }
            DispatchQueue.main.async { self.parent.pageIndex = index }
        }
    }
}
