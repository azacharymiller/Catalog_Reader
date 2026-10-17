import PencilKit
import UIKit
import Vision

/// Converts ink to text on the iPad with Apple's Vision framework. No network needed.
@MainActor
enum HandwritingRecognizer {
    static func recognize(_ drawing: PKDrawing, customWords: [String]) async -> String {
        guard !drawing.strokes.isEmpty, let image = render(drawing) else { return "" }
        return await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US"]
            request.usesLanguageCorrection = true
            request.customWords = customWords
            try? VNImageRequestHandler(cgImage: image).perform([request])
            // Vision's boxes have their origin at the bottom left, so read top line first.
            let lines = (request.results ?? [])
                .sorted { $0.boundingBox.midY > $1.boundingBox.midY }
                .compactMap { $0.topCandidates(1).first?.string }
            return lines.joined(separator: "\n")
        }.value
    }

    /// Dark ink on white, whatever the iPad's appearance setting.
    private static func render(_ drawing: PKDrawing) -> CGImage? {
        let bounds = drawing.bounds.insetBy(dx: -24, dy: -24)
        var ink = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            ink = drawing.image(from: bounds, scale: 2)
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = ink.scale
        let composed = UIGraphicsImageRenderer(size: ink.size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: ink.size))
            ink.draw(at: .zero)
        }
        return composed.cgImage
    }
}
