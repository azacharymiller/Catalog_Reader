import Foundation
import PDFKit

/// Works out which catalog page each hip is on by reading the page text.
///
/// Keeneland, Fasig-Tipton and OBS pages print the hip number near the top
/// ("Hip No. 123"). The pattern needs checking against each company's real
/// PDF; pages it misses can be assigned by hand from the Catalog screen.
enum CatalogPDFIndexer {
    private static let hipPattern = try! NSRegularExpression(
        pattern: #"\bHip\s*(?:No\.?|Number)?\s*(\d{1,4})\b"#,
        options: [.caseInsensitive]
    )

    /// Hip number → page index. The first page a hip appears on wins.
    static func hipPages(at url: URL) -> [Int: Int] {
        guard let document = PDFDocument(url: url) else { return [:] }
        var map: [Int: Int] = [:]
        for index in 0..<document.pageCount {
            guard let text = document.page(at: index)?.string else { continue }
            let range = NSRange(text.startIndex..., in: text)
            for match in hipPattern.matches(in: text, range: range) {
                guard let numberRange = Range(match.range(at: 1), in: text),
                      let hip = Int(text[numberRange]) else { continue }
                if map[hip] == nil { map[hip] = index }
            }
        }
        return map
    }
}
