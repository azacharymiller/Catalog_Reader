import SwiftUI

/// The strip along the top of every screen: in the ring, next up, last prices.
/// "In the ring" is estimated as the first hip after the last result.
struct RingBoardView: View {
    let sale: Sale

    var body: some View {
        let ordered = sale.hips.sorted { $0.hipNumber < $1.hipNumber }
        let lastDone = ordered.lastIndex { $0.result != nil }
        let upcoming = ordered[(lastDone.map { $0 + 1 } ?? 0)...].filter { $0.result == nil }
        let inRing = upcoming.first
        let next = Array(upcoming.dropFirst().prefix(3))
        let recent = ordered.filter { $0.result == "sold" || $0.result == "rna" }.suffix(5).reversed()
        let alert = upcoming.prefix(4).contains { $0.isShortlisted }

        HStack(spacing: 16) {
            if let inRing {
                Label {
                    Text("Hip \(inRing.hipNumber)").bold().monospacedDigit()
                } icon: {
                    Image(systemName: "circle.fill").foregroundStyle(.red)
                }
                .accessibilityLabel("In the ring: hip \(inRing.hipNumber)")
            }
            if !next.isEmpty {
                HStack(spacing: 6) {
                    Text("Next").foregroundStyle(.secondary)
                    ForEach(next) { hip in
                        Text("\(hip.hipNumber)")
                            .monospacedDigit()
                            .fontWeight(hip.isShortlisted ? .bold : .regular)
                            .foregroundStyle(hip.isShortlisted ? .green : .primary)
                    }
                }
            }
            Divider().frame(height: 18)
            HStack(spacing: 12) {
                ForEach(Array(recent)) { hip in
                    Text("\(hip.hipNumber): \(hip.resultText)").monospacedDigit()
                }
                if recent.isEmpty {
                    Text("No results yet").foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(alert ? Color.green.opacity(0.18) : .clear)
    }
}
