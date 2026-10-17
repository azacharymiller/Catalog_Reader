import SwiftData
import SwiftUI

/// Every hip through the ring so far, newest first, with session figures.
struct ResultsView: View {
    let sale: Sale
    @State private var entering = false

    private var results: [Hip] {
        sale.hips.filter { $0.result != nil }.sorted { $0.hipNumber > $1.hipNumber }
    }

    private var soldPrices: [Double] {
        results.filter { $0.result == "sold" }.compactMap(\.price).sorted()
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 32) {
                        figure("Sold", "\(soldPrices.count)")
                        figure("RNA", "\(results.filter { $0.result == "rna" }.count)")
                        figure("Median", median.map(\.shortDollars) ?? "–")
                        figure("Gross", soldPrices.isEmpty ? "–" : soldPrices.reduce(0, +).shortDollars)
                    }
                }
                Section("Results") {
                    ForEach(results) { hip in
                        HStack {
                            Text("\(hip.hipNumber)").monospacedDigit().bold().frame(width: 56, alignment: .leading)
                            VStack(alignment: .leading) {
                                Text(hip.displayName)
                                Text(hip.pedigreeLine).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text(hip.resultText).bold().monospacedDigit()
                                if let buyer = hip.buyer { Text(buyer).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                        .listRowBackground(hip.isShortlisted ? Color.green.opacity(0.1) : nil)
                    }
                }
            }
            .navigationTitle("Results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Enter result", systemImage: "plus") { entering = true }
            }
            .sheet(isPresented: $entering) {
                ResultEntryView(sale: sale)
            }
        }
    }

    private var median: Double? {
        guard !soldPrices.isEmpty else { return nil }
        let mid = soldPrices.count / 2
        return soldPrices.count.isMultiple(of: 2) ? (soldPrices[mid - 1] + soldPrices[mid]) / 2 : soldPrices[mid]
    }

    private func figure(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.bold()).monospacedDigit()
        }
    }
}

/// Typing a result in by hand, for when the live feed is down.
/// The feed replaces it when it catches up.
struct ResultEntryView: View {
    let sale: Sale
    @Environment(\.dismiss) private var dismiss
    @State private var hipNumber: Int?
    @State private var outcome = "sold"
    @State private var price: Double?
    @State private var buyer = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Hip", value: $hipNumber, format: .number)
                    .keyboardType(.numberPad)
                Picker("Result", selection: $outcome) {
                    Text("Sold").tag("sold")
                    Text("RNA").tag("rna")
                    Text("Out").tag("out")
                }
                .pickerStyle(.segmented)
                if outcome != "out" {
                    TextField(outcome == "rna" ? "Final bid" : "Price", value: $price,
                              format: .currency(code: "USD").precision(.fractionLength(0)))
                        .keyboardType(.numberPad)
                }
                if outcome == "sold" {
                    TextField("Buyer", text: $buyer)
                }
            }
            .navigationTitle("Enter result")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(hip == nil)
                }
            }
        }
    }

    private var hip: Hip? {
        hipNumber.flatMap { number in sale.hips.first { $0.hipNumber == number } }
    }

    private func save() {
        guard let hip else { return }
        hip.result = outcome
        hip.price = outcome == "out" ? nil : price
        hip.buyer = outcome == "sold" && !buyer.isEmpty ? buyer : nil
        hip.resultAt = .now
        hip.resultSource = "manual"
        hip.needsSync = true
        dismiss()
    }
}
