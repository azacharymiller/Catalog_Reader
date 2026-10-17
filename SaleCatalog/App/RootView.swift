import SwiftUI
import SwiftData

enum AppTab: Hashable {
    case hips, catalog, compare, results
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Sale.importedAt, order: .reverse) private var sales: [Sale]
    @AppStorage("authorName") private var authorName = ""
    @State private var sync = SyncService()
    @State private var tab: AppTab = .hips
    @State private var catalogPage = 0
    @State private var showSettings = false

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
                    HStack(spacing: 0) {
                        RingBoardView(sale: sale)
                        Button { showSettings = true } label: {
                            SyncBadge(status: sync.status)
                        }
                        .padding(.horizontal, 12)
                    }
                    .background(.bar)
                }
            } else {
                ProgressView("Loading sale…")
            }
        }
        .environment(sync)
        .task { SaleImporter.loadSampleIfNeeded(into: context) }
        .task { await sync.run(context: context) }
        .sheet(isPresented: Binding(get: { authorName.isEmpty || showSettings }, set: { showSettings = $0 })) {
            SettingsView()
                .environment(sync)
                .interactiveDismissDisabled(authorName.isEmpty)
        }
    }

    private func openPage(_ page: Int) {
        catalogPage = page
        tab = .catalog
    }
}

struct SyncBadge: View {
    let status: SyncService.Status

    var body: some View {
        switch status {
        case .synced(let date):
            Label(date.formatted(date: .omitted, time: .shortened), systemImage: "checkmark.icloud")
                .foregroundStyle(.green)
        case .syncing:
            Label("Syncing", systemImage: "arrow.triangle.2.circlepath.icloud")
        case .failed:
            Label("Offline", systemImage: "exclamationmark.icloud").foregroundStyle(.orange)
        case .notConfigured, .signedOut, .codeSent:
            Label("Sign in", systemImage: "icloud.slash").foregroundStyle(.secondary)
        }
    }
}

struct SettingsView: View {
    @Environment(SyncService.self) private var sync
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("authorName") private var authorName = ""
    @AppStorage("serverURL") private var serverURL = ""
    @AppStorage("serverKey") private var serverKey = ""
    @State private var name = ""
    @State private var email = ""
    @State private var code = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Your name", text: $name)
                        .textContentType(.name)
                } header: {
                    Text("You")
                } footer: {
                    Text("Your notes, ratings and photos are labelled with this name for the rest of the team.")
                }

                Section {
                    TextField("Server address (https://….supabase.co)", text: $serverURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    SecureField("Public key", text: $serverKey)
                    Button("Connect") { sync.configure() }
                        .disabled(serverURL.isEmpty || serverKey.isEmpty)
                } header: {
                    Text("Team server")
                } footer: {
                    Text("Leave empty to use this iPad on its own.")
                }

                Section("Sign in") {
                    switch sync.status {
                    case .notConfigured:
                        Text("Connect to the team server first.").foregroundStyle(.secondary)
                    case .signedOut, .failed:
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                        Button("Email me a code") { Task { await sync.sendCode(to: email) } }
                            .disabled(email.isEmpty)
                        if case .failed(let message) = sync.status {
                            Text(message).foregroundStyle(.orange).font(.callout)
                        }
                    case .codeSent(let sentTo):
                        Text("Code sent to \(sentTo)")
                        TextField("6-digit code", text: $code)
                            .keyboardType(.numberPad)
                        Button("Sign in") { Task { await sync.verify(code: code, email: sentTo) } }
                            .disabled(code.count < 6)
                    case .syncing, .synced:
                        LabeledContent("Team", value: sync.teamName ?? "–")
                        Button("Sync now") { Task { await sync.syncNow(context: context) } }
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                Button("Done") {
                    authorName = name.trimmingCharacters(in: .whitespaces)
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .onAppear { name = authorName }
        }
    }
}
