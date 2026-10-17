import SwiftUI

/// Short-listed hips side by side. The best value in each row is highlighted.
struct CompareView: View {
    let sale: Sale

    private var picks: [Hip] {
        sale.hips.filter(\.isShortlisted).sorted { $0.hipNumber < $1.hipNumber }
    }

    var body: some View {
        NavigationStack {
            Group {
                if picks.count < 2 {
                    ContentUnavailableView("Short-list two or more hips",
                                           systemImage: "rectangle.split.3x1",
                                           description: Text("Short-listed hips line up here for a head-to-head comparison."))
                } else {
                    ScrollView([.horizontal, .vertical]) {
                        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                            GridRow {
                                Text("")
                                ForEach(picks) { hip in
                                    VStack(alignment: .leading) {
                                        Text("Hip \(hip.hipNumber)").font(.headline)
                                        Text(hip.displayName).font(.subheadline)
                                        Text(hip.pedigreeLine).font(.caption).foregroundStyle(.secondary)
                                    }
                                    .frame(width: 200, alignment: .leading)
                                }
                            }
                            Divider()
                            ForEach(CompareRow.all, id: \.title) { row in
                                GridRow {
                                    Text(row.title).foregroundStyle(.secondary)
                                    ForEach(picks) { hip in
                                        Text(row.text(hip))
                                            .monospacedDigit()
                                            .fontWeight(isBest(row, hip) ? .bold : .regular)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(isBest(row, hip) ? Color.green.opacity(0.18) : .clear,
                                                        in: RoundedRectangle(cornerRadius: 5))
                                    }
                                }
                            }
                        }
                        .padding(24)
                    }
                }
            }
            .navigationTitle("Compare")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func isBest(_ row: CompareRow, _ hip: Hip) -> Bool {
        guard let higherIsBetter = row.higherIsBetter, let value = row.value(hip) else { return false }
        let values = picks.compactMap(row.value)
        guard values.count > 1, Set(values).count > 1 else { return false }
        return value == (higherIsBetter ? values.max() : values.min())
    }
}

struct CompareRow {
    let title: String
    var value: (Hip) -> Double? = { _ in nil }
    let text: (Hip) -> String
    /// nil = no "best" in this row
    var higherIsBetter: Bool? = nil

    static let all: [CompareRow] = [
        CompareRow(title: "Type", text: \.offeringLabel),
        CompareRow(title: "Agent score", value: \.agentScore,
                   text: { h in [h.agentTier, h.agentScore.map { String(format: "%.0f", $0) }].compactMap { $0 }.joined(separator: " · ") },
                   higherIsBetter: true),
        CompareRow(title: "Foaled", value: { $0.foalingDate?.timeIntervalSince1970 }, text: \.foaledText, higherIsBetter: false),
        CompareRow(title: "Sire SW%", value: \.sirePctStakesWinners,
                   text: { $0.sirePctStakesWinners.map { String(format: "%.1f%%", $0) } ?? "–" }, higherIsBetter: true),
        CompareRow(title: "Sire graded winners", value: { $0.sireGradedWinners.map(Double.init) },
                   text: { $0.sireGradedWinners.map(String.init) ?? "–" }, higherIsBetter: true),
        CompareRow(title: "Sire fee", text: { $0.sireFee?.shortDollars ?? "–" }),
        CompareRow(title: "Sire price band", text: \.bandText),
        CompareRow(title: "Family score", value: \.femaleLineScore,
                   text: { $0.femaleLineScore.map { String(format: "%.1f", $0) } ?? "–" }, higherIsBetter: true),
        CompareRow(title: "Dam's foals sold", value: \.produceMedian, text: \.produceText, higherIsBetter: true),
        CompareRow(title: "In foal to", text: { $0.coveringSire ?? "–" }),
        CompareRow(title: "Consignor", text: { $0.consignor ?? "–" }),
        CompareRow(title: "Rating", value: { $0.rating > 0 ? Double($0.rating) : nil },
                   text: { $0.rating > 0 ? "\($0.rating) / 5" : "–" }, higherIsBetter: true),
        CompareRow(title: "Bid ceiling", text: { $0.bidCeiling?.shortDollars ?? "–" }),
        CompareRow(title: "Result", text: { $0.resultText.isEmpty ? "–" : $0.resultText }),
    ]
}
