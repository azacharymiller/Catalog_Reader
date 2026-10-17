import PencilKit
import SwiftUI

/// The writing area on a hip card, with Apple's full tool palette.
struct InkPadView: UIViewRepresentable {
    let initialDrawing: PKDrawing
    var onChange: (PKDrawing) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawing = initialDrawing
        canvas.drawingPolicy = .default
        canvas.tool = PKInkingTool(.pen, color: .black, width: 2)
        canvas.backgroundColor = .secondarySystemBackground
        canvas.layer.cornerRadius = 12
        canvas.delegate = context.coordinator

        let picker = PKToolPicker()
        picker.addObserver(canvas)
        picker.setVisible(true, forFirstResponder: canvas)
        context.coordinator.toolPicker = picker
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.parent = self
    }

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: InkPadView
        var toolPicker: PKToolPicker?
        private var pending: Task<Void, Never>?

        init(_ parent: InkPadView) { self.parent = parent }

        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            if !canvasView.isFirstResponder { canvasView.becomeFirstResponder() }
        }

        /// Save a second after the writer pauses, not on every stroke.
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            pending?.cancel()
            pending = Task { [weak self, weak canvasView] in
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self, let canvasView else { return }
                self.parent.onChange(canvasView.drawing)
            }
        }
    }
}
