import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Home screen: one sortable row of numbers per hip.
struct HipTableView: View {
    let sale: Sale
    var openPage: (Int) -> Void

    @Environment(\.modelContext) private var context
    @State private var sortOrder = [KeyPathComparator(\Hip.hipNumber)]
    @State private var selection: PersistentIdentifier?
    @State private var path: [PersistentIdentifier] = []
    @State private var search = ""
    @State private var typeFilter = "All"
    @State private var shortlistOnly = false
    @State private var hideSold = false
    @State private var importingData = false
    @State private var message: String?

    private var types: [String] {
        ["All"] + Set(sale.hips.map(\.typeGroup)).sorted()
    }

    private var rows: [Hip] {
        sale.hips.filter(matches).sorted(using: sortOrder)
    }

    var body: some View {
        NavigationStack(path: $path) {
            Table(rows, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Hip", value: \.hipNumber) { hip in
                    HStack(spacing: 4) {
                        Text("\(hip.hipNumber)").monospacedDigit().bold()
                        if hip.isShortlisted {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                        if hip.isFavorite {
                            Image(systemName: "star.fill").foregroundStyle(.yellow)
                        }
                    }
                }
                .width(min: 70, ideal: 90)
                TableColumn("Horse", value: \.sortName) { hip in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hip.displayName).bold()
                        Text(hip.pedigreeLine).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .width(min: 220, ideal: 300)
                TableColumn("Type", value: \.offeringLabel) { hip in
                    Text(hip.offeringLabel).font(.callout)
                }
                TableColumn("Foaled", value: \.sortFoaling) { hip in
                    Text(hip.foaledText).monospacedDigit()
                }
                TableColumn("Score", value: \.sortScore) { hip in
                    TierBadge(score: hip.agentScore, tier: hip.agentTier)
                }
                .width(min: 80, ideal: 90)
                TableColumn("Sire SW%", value: \.sortSireSW) { hip in
                    Text(hip.sirePctStakesWinners.map { String(format: "%.1f%%", $0) }
                         ?? (hip.sireFirstCrop ? "first crop" : "–"))
                        .foregroundStyle(hip.sirePctStakesWinners == nil ? .secondary : .primary)
                        .monospacedDigit()
                }
                TableColumn("Sire band", value: \.sortBandMedian) { hip in
                    Text(hip.bandText)
                        .foregroundStyle(hip.bandIsReliable ? .primary : .secondary)
                        .monospacedDigit()
                }
                .width(min: 140, ideal: 180)
                TableColumn("Black type", value: \.sortBlackType) { hip in
                    Text(hip.blackTypeText)
                        .fontWeight((hip.familyStakesWinners ?? 0) > 0 ? .semibold : .regular)
                        .monospacedDigit()
                }
                .width(min: 120, ideal: 150)
                TableColumn("Dam's foals sold", value: \.sortProduceMedian) { hip in
                    Text(hip.produceText).monospacedDigit()
                }
                .width(min: 120, ideal: 150)
                TableColumn("Result", value: \.sortPrice) { hip in
                    Text(hip.resultText).bold().monospacedDigit()
                }
            }
            .contextMenu(forSelectionType: PersistentIdentifier.self) { ids in
                Button("Short-list", systemImage: "checkmark.circle") { toggle(ids, \.isShortlisted) }
                Button("Favorite", systemImage: "star") { toggle(ids, \.isFavorite) }
            }
            .searchable(text: $search, prompt: "Hip, sire, dam, consignor")
            .navigationTitle(sale.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .onChange(of: selection) { _, id in
                guard let id else { return }
                path.append(id)
                selection = nil
            }
            .navigationDestination(for: PersistentIdentifier.self) { id in
                if let hip = context.model(for: id) as? Hip {
                    HipDetailView(hip: hip, openPage: openPage)
                }
            }
            .fileImporter(isPresented: $importingData, allowedContentTypes: [.json]) { result in
                importData(result)
            }
            .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Picker("Type", selection: $typeFilter) {
                ForEach(types, id: \.self) { Text($0) }
            }
            .pickerStyle(.menu)
            Toggle(isOn: $shortlistOnly) { Label("Short-list", systemImage: "checkmark.circle") }
            Toggle(isOn: $hideSold) { Label("Hide sold", systemImage: "eye.slash") }
            Menu {
                Button("Import hip data (JSON)", systemImage: "square.and.arrow.down") { importingData = true }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    private func matches(_ hip: Hip) -> Bool {
        if shortlistOnly && !hip.isShortlisted { return false }
        if hideSold && hip.result != nil { return false }
        if typeFilter != "All" && hip.typeGroup != typeFilter { return false }
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        if let number = Int(query) { return hip.hipNumber == number }
        return [hip.name, hip.sire, hip.dam, hip.damsire, hip.consignor, hip.coveringSire]
            .compactMap { $0 }
            .contains { $0.localizedCaseInsensitiveContains(query) }
    }

    private func toggle(_ ids: Set<PersistentIdentifier>, _ flag: ReferenceWritableKeyPath<Hip, Bool>) {
        let hips = ids.compactMap { context.model(for: $0) as? Hip }
        let newValue = !hips.allSatisfy { $0[keyPath: flag] }
        for hip in hips {
            hip[keyPath: flag] = newValue
            hip.needsSync = true
        }
    }

    private func importData(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let sale = try SaleImporter.importSale(Data(contentsOf: url), into: context)
            message = "Loaded \(sale.hips.count) hips for \(sale.name)."
        } catch {
            message = "Could not read that file: \(error.localizedDescription)"
        }
    }
}

extension Hip {
    /// Broad groups for the type filter.
    var typeGroup: String {
        guard let soldAs else { return sexWord }
        if soldAs.localizedCaseInsensitiveContains("prospect") { return "Prospect" }
        if soldAs.localizedCaseInsensitiveContains("broodmare") { return "Broodmare" }
        return soldAs
    }
}

struct TierBadge: View {
    let score: Double?
    let tier: String?

    var body: some View {
        HStack(spacing: 6) {
            Text(tier ?? "–")
                .font(.caption.bold())
                .frame(width: 22, height: 22)
                .background(color.opacity(0.2), in: RoundedRectangle(cornerRadius: 5))
                .foregroundStyle(color)
            Text(score.map { String(format: "%.0f", $0) } ?? "–")
                .monospacedDigit()
        }
    }

    private var color: Color {
        switch tier {
        case "A": .green
        case "B": .teal
        case "C": .orange
        case "D": .gray
        default: .secondary
        }
    }
}
