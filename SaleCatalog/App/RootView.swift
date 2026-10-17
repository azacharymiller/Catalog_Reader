import SwiftUI
import SwiftData

enum AppTab: Hashable {
    case hips, catalog, compare, results
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Sale.importedAt, order: .reverse) private var sales: [Sale]
    @AppStorage("authorName") private var authorName = ""
    @State private var tab: AppTab = .hips
    @State private var catalogPage = 0

    var body: some View {
        Group {
            if let sale = sales.first {
                TabView(selection: $tab) {
                    HipTableView(sale: sale, openPage: openPage)
                        .tabItem { Label("Hips", systemImage: "list.number") }
                        .tag(AppTab.hips)
                    CatalogView(sale: sale, pageIndex: $catalogPage)
                        .tabItem { Label("Catalog", systemImage: "book") }
                        .tag(AppTab.catalog)
                    CompareView(sale: sale)
                        .tabItem { Label("Compare", systemImage: "rectangle.split.3x1") }
                        .tag(AppTab.compare)
                    ResultsView(sale: sale)
                        .tabItem { Label("Results", systemImage: "dollarsign.circle") }
                        .tag(AppTab.results)
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    RingBoardView(sale: sale)
                }
            } else {
                ProgressView("Loading sale…")
            }
        }
        .task { SaleImporter.loadSampleIfNeeded(into: context) }
        .sheet(isPresented: .constant(authorName.isEmpty)) {
            SettingsView()
                .interactiveDismissDisabled()
        }
    }

    private func openPage(_ page: Int) {
        catalogPage = page
        tab = .catalog
    }
}

struct SettingsView: View {
    @AppStorage("authorName") private var authorName = ""
    @State private var draft = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Your name", text: $draft)
                        .textContentType(.name)
                } footer: {
                    Text("Your notes, ratings and photos are labelled with this name for the rest of the team.")
                }
            }
            .navigationTitle("Who's using this iPad?")
            .toolbar {
                Button("Done") {
                    authorName = draft.trimmingCharacters(in: .whitespaces)
                    dismiss()
                }
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .onAppear { draft = authorName }
        }
    }
}
