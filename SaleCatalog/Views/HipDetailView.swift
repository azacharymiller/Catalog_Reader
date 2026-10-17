import PencilKit
import SwiftData
import SwiftUI

/// Hip card: the numbers first, then marks, ink notes, the team's notes and media.
struct HipDetailView: View {
    @Bindable var hip: Hip
    var openPage: (Int) -> Void

    @Environment(\.modelContext) private var context
    @AppStorage("authorName") private var author = ""

    private var myCardNote: HipNote? {
        InkStore.note(for: hip, location: "card", author: author)
    }

    private var otherNotes: [HipNote] {
        hip.notes
            .filter { !($0.location == "card" && $0.author == author) && !$0.text.isEmpty }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                marks
                StatGrid(hip: hip)
                myNotes
                if !otherNotes.isEmpty { teamNotes }
                MediaSection(hip: hip)
            }
            .padding(24)
        }
        .navigationTitle("Hip \(hip.hipNumber)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let page = hip.pdfPageIndex {
                Button("Catalog page", systemImage: "book") { openPage(page) }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(hip.displayName).font(.largeTitle.bold())
            Text(hip.pedigreeLine).font(.title3)
            Text([hip.offeringLabel, hip.consignor, hip.bcEligible ? "BC eligible" : nil]
                .compactMap { $0 }
                .joined(separator: " · "))
                .foregroundStyle(.secondary)
        }
    }

    private var marks: some View {
        HStack(spacing: 20) {
            Toggle(isOn: mark(\.isShortlisted)) { Label("Short-list", systemImage: "checkmark.circle") }
                .toggleStyle(.button)
                .tint(.green)
            Toggle(isOn: mark(\.isFavorite)) { Label("Favorite", systemImage: "star") }
                .toggleStyle(.button)
                .tint(.yellow)
            RatingView(rating: Binding(get: { hip.rating }, set: { hip.rating = $0; hip.needsSync = true }))
            if hip.teamFavoriteCount > 0 || hip.teamRatingAverage != nil {
                Text([hip.teamFavoriteCount > 0 ? "\(hip.teamFavoriteCount) team favorites" : nil,
                      hip.teamRatingAverage.map { String(format: "team rating %.1f", $0) }]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack {
                Text("Bid ceiling").foregroundStyle(.secondary)
                TextField("$", value: bidCeiling, format: .currency(code: "USD").precision(.fractionLength(0)))
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
            }
        }
    }

    private var myNotes: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("My notes").font(.headline)
            InkPadView(initialDrawing: InkStore.drawing(for: hip, location: "card", author: author)) { drawing in
                InkStore.save(drawing, hip: hip, location: "card", author: author, context: context)
            }
            .frame(height: 260)
            if let note = myCardNote {
                TextField("Converted text appears here", text: Binding(
                    get: { note.text },
                    set: { note.correctedText = $0; note.needsSync = true }
                ), axis: .vertical)
                .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var teamNotes: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("All notes").font(.headline)
            ForEach(otherNotes) { note in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(note.author) · \(note.locationLabel) · \(note.updatedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(note.text)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func mark(_ flag: ReferenceWritableKeyPath<Hip, Bool>) -> Binding<Bool> {
        Binding(get: { hip[keyPath: flag] }, set: { hip[keyPath: flag] = $0; hip.needsSync = true })
    }

    private var bidCeiling: Binding<Double> {
        Binding(get: { hip.bidCeiling ?? 0 }, set: { hip.bidCeiling = $0 > 0 ? $0 : nil; hip.needsSync = true })
    }
}

/// The quantified catalog page.
struct StatGrid: View {
    let hip: Hip

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
            StatTile(title: "Agent score", value: hip.agentScore.map { String(format: "%.0f", $0) } ?? "–",
                     detail: hip.agentTier.map { "Tier \($0) in this sale" } ?? "Too little data for a tier")
            StatTile(title: "Foaled", value: hip.foaledText, detail: hip.crop.map { "Crop \($0)" } ?? "")
            StatTile(title: "Sire stakes winners", value: hip.sirePctStakesWinners.map { String(format: "%.1f%%", $0) } ?? "–",
                     detail: [hip.sireGradedWinners.map { "\($0) graded winners" },
                              hip.sireFee.map { "fee \($0.shortDollars)" }].compactMap { $0 }.joined(separator: " · "))
            StatTile(title: "Sire price band", value: hip.bandIsReliable ? (hip.bandMedian?.shortDollars ?? "–") : "–",
                     detail: bandDetail, dimmed: !hip.bandIsReliable)
            StatTile(title: "Family score", value: hip.femaleLineScore.map { String(format: "%.1f / 10", $0) } ?? "–",
                     detail: "Female line, from the agent score")
            StatTile(title: "Dam's foals at auction", value: hip.produceMedian?.shortDollars ?? "–",
                     detail: hip.produceText)
            StatTile(title: "Black type under 1st dam", value: hip.blackTypeText,
                     detail: blackTypeDetail)
            if let produce = damProduceLine {
                StatTile(title: "Dam's produce record", value: produce, detail: "foals · to race · winners · SW")
            }
            if hip.secondDamStakesWinners != nil || hip.thirdDamStakesWinners != nil {
                StatTile(title: "Deeper family",
                         value: "\(hip.secondDamStakesWinners.map(String.init) ?? "–") / \(hip.thirdDamStakesWinners.map(String.init) ?? "–")",
                         detail: "Stakes winners under 2nd / 3rd dam")
            }
            if let btw = hip.sireBlackTypeWinners {
                StatTile(title: "Sire's record (catalog)", value: "\(btw) SW",
                         detail: [hip.sireCrops.map { "\($0) crops" }, hip.sireStarters.map { "\($0) starters" },
                                  hip.sireWinners.map { "\($0) winners" }].compactMap { $0 }.joined(separator: " · "))
            }
            if let coveringSire = hip.coveringSire {
                StatTile(title: hip.pregnant == false ? "Mated to" : "In foal to", value: coveringSire,
                         detail: "His weanlings: \(hip.coverBandText)")
            }
            if hip.earned != nil || hip.ownProduceStakesWinners != nil {
                StatTile(title: "Her own record",
                         value: hip.earned?.shortDollars ?? "–",
                         detail: "Earned · her foals: \(hip.ownProduceStakesWinners ?? 0) SW, \(hip.ownProduceStakesPlaced ?? 0) SP")
            }
        }
    }

    private var bandDetail: String {
        guard let count = hip.bandCount else { return "No comparable sales" }
        let year = hip.bandYear.map { " in \($0)" } ?? ""
        if !hip.bandIsReliable { return "Too few sales (\(count))\(year)" }
        return "\(hip.bandQ1?.shortDollars ?? "?")–\(hip.bandQ3?.shortDollars ?? "?") middle half, \(count) sold\(year)"
    }

    private var blackTypeDetail: String {
        var parts: [String] = []
        switch hip.damBlackType {
        case "winner": parts.append("Dam is a stakes winner")
        case "placed": parts.append("Dam is stakes-placed")
        default: break
        }
        if let winners = hip.damStakesWinners, let placed = hip.damStakesPlaced {
            parts.append("her foals: \(winners) SW, \(placed) SP")
        }
        return parts.isEmpty ? "Read from the catalog page" : parts.joined(separator: " · ")
    }

    private var damProduceLine: String? {
        guard let foals = hip.damFoals else { return nil }
        return [foals, hip.damRunners, hip.damWinners, hip.damStakesWinners]
            .map { $0.map(String.init) ?? "?" }
            .joined(separator: " · ")
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let detail: String
    var dimmed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.bold()).monospacedDigit()
                .foregroundStyle(dimmed ? .secondary : .primary)
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct RatingView: View {
    @Binding var rating: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { value in
                Button {
                    rating = rating == value ? 0 : value
                } label: {
                    Image(systemName: value <= rating ? "circle.fill" : "circle")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                .accessibilityLabel("Rate \(value)")
            }
        }
    }
}
