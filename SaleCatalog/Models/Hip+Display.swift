import Foundation

/// Display text and sort keys. Table columns sort on non-optional values,
/// so missing numbers sort to the bottom.
extension Hip {
    var displayName: String {
        if let name { return name.capitalized }
        return "\(sexWord) by \(sire.capitalized)"
    }

    var pedigreeLine: String {
        var line = "\(sire.capitalized) – \(dam.capitalized)"
        if let damsire { line += ", by \(damsire.capitalized)" }
        return line
    }

    var sexWord: String {
        switch sex {
        case "C": "Colt"
        case "F": "Filly"
        case "M": "Mare"
        case "G": "Gelding"
        case "H": "Horse"
        case "R": "Ridgling"
        default: "Foal"
        }
    }

    var offeringLabel: String {
        if let soldAs, !soldAs.isEmpty {
            if soldAs == "Broodmare", let coveringSire { return "In foal to \(coveringSire)" }
            return soldAs
        }
        return sexWord
    }

    var foaledText: String {
        guard let foalingDate else { return crop.map(String.init) ?? "–" }
        return foalingDate.formatted(.dateTime.month(.abbreviated).day().year())
    }

    var bandIsReliable: Bool { (bandCount ?? 0) >= 15 }

    var bandText: String {
        guard let bandMedian, let bandCount else { return "–" }
        guard bandIsReliable else { return "too few (\(bandCount))" }
        let low = bandQ1?.shortDollars ?? "?"
        let high = bandQ3?.shortDollars ?? "?"
        return "\(low)–\(high) · med \(bandMedian.shortDollars)"
    }

    var produceText: String {
        guard let produceSold, produceSold > 0 else { return "none sold" }
        let median = produceMedian.map { " · med \($0.shortDollars)" } ?? ""
        return "\(produceSold) sold\(median)"
    }

    var resultText: String {
        switch result {
        case "sold": price.map(\.shortDollars) ?? "Sold"
        case "rna": "RNA " + (price.map(\.shortDollars) ?? "")
        case "out": "Out"
        default: ""
        }
    }

    /// Black type under the first dam, e.g. "3 SW · 2 SP · 1 G1".
    var blackTypeText: String {
        guard let winners = familyStakesWinners, let placed = familyStakesPlaced else { return "–" }
        if winners == 0 && placed == 0 { return "none" }
        var parts = ["\(winners) SW", "\(placed) SP"]
        if let g1 = familyG1, g1 > 0 { parts.append("\(g1) G1") }
        return parts.joined(separator: " · ")
    }

    var coverBandText: String {
        guard let coverBandMedian, let coverBandCount else { return "–" }
        guard coverBandCount >= 15 else { return "too few (\(coverBandCount))" }
        return "med \(coverBandMedian.shortDollars)"
    }

    var sortName: String { name ?? "\(sire) \(dam)" }
    /// Winners count ten times a placed horse; graded adds one more.
    var sortBlackType: Int {
        guard let winners = familyStakesWinners else { return -1 }
        return winners * 10 + (familyStakesPlaced ?? 0) + (familyGraded ?? 0)
    }
    var sortFoaling: Date { foalingDate ?? .distantFuture }
    var sortScore: Double { agentScore ?? -1 }
    var sortSireSW: Double { sirePctStakesWinners ?? -1 }
    var sortBandMedian: Double { bandIsReliable ? (bandMedian ?? -1) : -1 }
    var sortFamily: Double { femaleLineScore ?? -1 }
    var sortProduceMedian: Double { produceMedian ?? -1 }
    var sortPrice: Double { result == "sold" ? (price ?? -1) : -1 }

    /// Names that help handwriting recognition spell this hip's horses and farms.
    var recognitionWords: [String] {
        [name, sire, dam, damsire, coveringSire, consignor]
            .compactMap { $0?.capitalized }
    }
}

extension Double {
    /// $250K, $1.48M
    var shortDollars: String {
        if self >= 1_000_000 { return String(format: "$%.2fM", self / 1_000_000) }
        if self >= 1_000 { return "$\(Int((self / 1_000).rounded()))K" }
        return "$\(Int(self))"
    }
}
