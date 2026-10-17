import PDFKit
import PencilKit
import SwiftData
import SwiftUI

/// The sale company's PDF, page by page, with Pencil ink saved to the hip on each page.
struct CatalogView: View {
    @Bindable var sale: Sale
    @Binding var pageIndex: Int

    @Environment(\.modelContext) private var context
    @AppStorage("authorName") private var author = ""
    @State private var document: PDFDocument?
    @State private var importing = false
    @State private var indexing = false
    @State private var message: String?
    @State private var openHip: Hip?
    @State private var goToHip = ""

    /// Page index → hip, from the import's page matching.
    private var hipsByPage: [Int: Hip] {
        Dictionary(sale.hips.compactMap { hip in hip.pdfPageIndex.map { ($0, hip) } },
                   uniquingKeysWith: { first, _ in first })
    }

    /// The hip on this page, or the last hip before it (pedigree pages can run to two).
    private func hip(forPage index: Int) -> Hip? {
        let map = hipsByPage
        if let hip = map[index] { return hip }
        guard let previous = map.keys.filter({ $0 < index }).max() else { return nil }
        return map[previous]
    }

    var body: some View {
        NavigationStack {
            Group {
                if let document {
                    CatalogPDFView(
                        document: document,
                        pageIndex: $pageIndex,
                        canDraw: { hip(forPage: $0) != nil },
                        drawingForPage: { page in
                            guard let hip = hip(forPage: page) else { return PKDrawing() }
                            return InkStore.drawing(for: hip, location: "page:\(page)", author: author)
                        },
                        saveDrawing: { page, drawing in
                            guard let hip = hip(forPage: page) else { return }
                            InkStore.save(drawing, hip: hip, location: "page:\(page)", author: author, context: context)
                        }
                    )
                    .ignoresSafeArea(edges: .bottom)
                } else if indexing {
                    ProgressView("Reading the catalog…")
                } else {
                    ContentUnavailableView {
                        Label("No catalog loaded", systemImage: "book.closed")
                    } description: {
                        Text("Import the sale company's PDF catalog for \(sale.name).")
                    } actions: {
                        Button("Import PDF") { importing = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle(pageTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    TextField("Go to hip", text: $goToHip)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)
                        .onSubmit(goTo)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Hip card", systemImage: "rectangle.and.pencil.and.ellipsis") {
                        openHip = hip(forPage: pageIndex)
                    }
                    .disabled(document == nil || hip(forPage: pageIndex) == nil)
                    Button("Import PDF", systemImage: "square.and.arrow.down") { importing = true }
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf]) { result in
                Task { await importPDF(result) }
            }
            .sheet(item: $openHip) { hip in
                NavigationStack {
                    HipDetailView(hip: hip) { page in
                        openHip = nil
                        pageIndex = page
                    }
                    .toolbar { Button("Done") { openHip = nil } }
                }
            }
            .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            }
            .task(id: sale.pdfFileName) { loadDocument() }
        }
    }

    private var pageTitle: String {
        guard document != nil else { return "Catalog" }
        guard let hip = hip(forPage: pageIndex) else { return "Page \(pageIndex + 1)" }
        return "Hip \(hip.hipNumber) · \(hip.displayName)"
    }

    private func loadDocument() {
        guard let name = sale.pdfFileName else { document = nil; return }
        document = PDFDocument(url: AppFiles.url(name))
    }

    private func goTo() {
        guard let number = Int(goToHip),
              let page = sale.hips.first(where: { $0.hipNumber == number })?.pdfPageIndex else {
            message = "Hip \(goToHip) is not matched to a catalog page."
            return
        }
        pageIndex = page
        goToHip = ""
    }

    @MainActor
    private func importPDF(_ result: Result<URL, Error>) async {
        guard case .success(let url) = result else { return }
        let fileName = "catalog-\(sale.saleId).pdf"
        let destination = AppFiles.url(fileName)
        do {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: url, to: destination)
        } catch {
            message = "Could not copy the PDF: \(error.localizedDescription)"
            return
        }

        indexing = true
        let pages = await Task.detached { CatalogPDFIndexer.hipPages(at: destination) }.value
        indexing = false

        var matched = 0
        for hip in sale.hips {
            hip.pdfPageIndex = pages[hip.hipNumber]
            if hip.pdfPageIndex != nil { matched += 1 }
        }
        sale.pdfFileName = fileName
        try? context.save()
        loadDocument()
        pageIndex = sale.hips.compactMap(\.pdfPageIndex).min() ?? 0
        message = "Matched \(matched) of \(sale.hips.count) hips to catalog pages."
    }
}
