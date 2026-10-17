import Foundation
import SwiftData

/// The hip data format. The shared server will serve this; for now it is
/// bundled (SampleSale.json) or imported from a file.
struct SaleFile: Codable {
    var saleId: String
    var name: String
    var house: String
    var hips: [HipRecord]
}

struct HipRecord: Codable {
    var hip: Int
    var book: Int?
    var session: Int?
    var name: String?
    var sire: String
    var dam: String
    var damsire: String?
    var sex: String?
    var crop: Int?
    var foalingDate: String?
    var consignor: String?
    var soldAs: String?
    var coveringSire: String?
    var bcEligible: Bool?
    var agentScore: Double?
    var agentTier: String?
    var femaleLineScore: Double?
    var sirePctStakesWinners: Double?
    var sireGradedWinners: Int?
    var sireFee: Double?
    var bandQ1: Double?
    var bandMedian: Double?
    var bandQ3: Double?
    var bandCount: Int?
    var bandYear: Int?
    var produceSold: Int?
    var produceMedian: Double?
    var damFoals: Int?
    var damRunners: Int?
    var damWinners: Int?
    var damStakesWinners: Int?
    var damStakesPlaced: Int?
    var secondDamStakesWinners: Int?
}

@MainActor
enum SaleImporter {
    static func loadSampleIfNeeded(into context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<Sale>())) ?? 0
        guard count == 0,
              let url = Bundle.main.url(forResource: "SampleSale", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return }
        try? importSale(data, into: context)
    }

    /// Adds or refreshes a sale. Catalog facts and numbers are replaced;
    /// the team's marks, notes and results are kept.
    @discardableResult
    static func importSale(_ data: Data, into context: ModelContext) throws -> Sale {
        let file = try JSONDecoder().decode(SaleFile.self, from: data)
        let saleId = file.saleId
        let existing = try context.fetch(FetchDescriptor<Sale>(predicate: #Predicate { $0.saleId == saleId })).first
        let sale = existing ?? Sale(saleId: file.saleId, name: file.name, house: file.house)
        if existing == nil { context.insert(sale) }
        sale.name = file.name

        var byNumber = Dictionary(sale.hips.map { ($0.hipNumber, $0) }, uniquingKeysWith: { first, _ in first })
        for record in file.hips {
            let hip = byNumber[record.hip] ?? {
                let new = Hip(hipNumber: record.hip, sire: record.sire, dam: record.dam)
                context.insert(new)
                new.sale = sale
                return new
            }()
            byNumber[record.hip] = hip
            apply(record, to: hip)
        }
        try context.save()
        return sale
    }

    private static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static func apply(_ r: HipRecord, to hip: Hip) {
        hip.book = r.book
        hip.session = r.session
        hip.name = r.name
        hip.sire = r.sire
        hip.dam = r.dam
        hip.damsire = r.damsire
        hip.sex = r.sex
        hip.crop = r.crop
        hip.foalingDate = r.foalingDate.flatMap { dayFormat.date(from: $0) }
        hip.consignor = r.consignor
        hip.soldAs = r.soldAs
        hip.coveringSire = r.coveringSire
        hip.bcEligible = r.bcEligible ?? false
        hip.agentScore = r.agentScore
        hip.agentTier = r.agentTier
        hip.femaleLineScore = r.femaleLineScore
        hip.sirePctStakesWinners = r.sirePctStakesWinners
        hip.sireGradedWinners = r.sireGradedWinners
        hip.sireFee = r.sireFee
        hip.bandQ1 = r.bandQ1
        hip.bandMedian = r.bandMedian
        hip.bandQ3 = r.bandQ3
        hip.bandCount = r.bandCount
        hip.bandYear = r.bandYear
        hip.produceSold = r.produceSold
        hip.produceMedian = r.produceMedian
        hip.damFoals = r.damFoals
        hip.damRunners = r.damRunners
        hip.damWinners = r.damWinners
        hip.damStakesWinners = r.damStakesWinners
        hip.damStakesPlaced = r.damStakesPlaced
        hip.secondDamStakesWinners = r.secondDamStakesWinners
    }
}
