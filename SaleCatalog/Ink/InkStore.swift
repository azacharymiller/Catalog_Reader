import PencilKit
import SwiftData

/// Saves ink to the right hip and author, then converts it to text.
@MainActor
enum InkStore {
    static func note(for hip: Hip, location: String, author: String) -> HipNote? {
        hip.notes.first { $0.location == location && $0.author == author }
    }

    static func drawing(for hip: Hip, location: String, author: String) -> PKDrawing {
        guard let data = note(for: hip, location: location, author: author)?.drawingData,
              let drawing = try? PKDrawing(data: data) else { return PKDrawing() }
        return drawing
    }

    static func save(_ drawing: PKDrawing, hip: Hip, location: String, author: String, context: ModelContext) {
        let existing = note(for: hip, location: location, author: author)
        if existing == nil && drawing.strokes.isEmpty { return }
        let note = existing ?? {
            let new = HipNote(author: author, location: location)
            context.insert(new)
            new.hip = hip
            return new
        }()
        note.drawingData = drawing.dataRepresentation()
        note.updatedAt = .now
        note.needsSync = true
        try? context.save()

        let words = hip.recognitionWords
        Task {
            let text = await HandwritingRecognizer.recognize(drawing, customWords: words)
            note.recognizedText = text
            try? context.save()
        }
    }
}
