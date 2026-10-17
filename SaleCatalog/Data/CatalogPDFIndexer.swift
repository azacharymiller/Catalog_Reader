import Foundation
import PDFKit

/// Works out which catalog page each hip is on.
///
/// Keeneland pages print a "Hip No." label with the number directly below
/// it; the label moves between the left and right side on facing pages. So
/// find every label and read the number in the strip just under it.
/// Supplementary hips ("224A") are skipped until hips can carry a letter.
enum CatalogPDFIndexer {
    /// Hip number → page index. The first page a hip appears on wins.
    static func hipPages(at url: URL) -> [Int: Int] {
        guard let document = PDFDocument(url: url) else { return [:] }
        var map: [Int: Int] = [:]
        for label in document.findString("Hip No.", withOptions: .caseInsensitive) {
            guard let page = label.pages.first else { continue }
            let bounds = label.bounds(for: page)
            // PDF space has its origin at the bottom left, so "below" is a smaller y.
            let strip = CGRect(x: bounds.minX - 12, y: bounds.minY - 22,
                               width: bounds.width + 48, height: 20)
            guard let text = page.selection(for: strip)?.string,
                  let match = text.range(of: #"\b\d{1,4}\b"#, options: .regularExpression),
                  let hip = Int(text[match]) else { continue }
            let index = document.index(for: page)
            if map[hip] == nil { map[hip] = index }
        }
        return map
    }
}
