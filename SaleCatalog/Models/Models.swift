import Foundation
import SwiftData

@Model
final class Sale {
    var saleId: String
    var name: String
    var house: String
    var importedAt: Date
    /// File name of the imported catalog PDF inside the app's Documents folder.
    var pdfFileName: String?
    @Relationship(deleteRule: .cascade, inverse: \Hip.sale) var hips: [Hip] = []

    init(saleId: String, name: String, house: String) {
        self.saleId = saleId
        self.name = name
        self.house = house
        self.importedAt = .now
    }
}

@Model
final class Hip {
    // Catalog facts
    var hipNumber: Int
    var book: Int?
    var session: Int?
    var name: String?
    var sire: String
    var dam: String
    var damsire: String?
    var sex: String?
    var crop: Int?
    var foalingDate: Date?
    var consignor: String?
    var soldAs: String?
    var coveringSire: String?
    var bcEligible: Bool = false
    var pdfPageIndex: Int?

    // Quantified attributes (Timbercreek database, later also read from the PDF page)
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
    var thirdDamStakesWinners: Int?
    /// Black type anywhere under the first dam (produce, grand-produce, siblings).
    var familyStakesWinners: Int?
    var familyStakesPlaced: Int?
    /// Stakes winners whose entry names a graded race (the race may be a placing).
    var familyGraded: Int?
    var familyG1: Int?
    /// "winner" or "placed" when the dam herself earned black type.
    var damBlackType: String?
    var sireCrops: Int?
    var sireFoals: Int?
    var sireStarters: Int?
    var sireBlackTypeWinners: Int?
    var sireWinners: Int?
    /// The sire's first foals are not yet racing age, so he has no figures.
    var sireFirstCrop: Bool = false
    var coverBandMedian: Double?
    var coverBandCount: Int?
    // Mares: her own race and produce record
    var earned: Double?
    var ownProduceStakesWinners: Int?
    var ownProduceStakesPlaced: Int?
    var pregnant: Bool?

    // Team marks
    var isFavorite: Bool = false
    var isShortlisted: Bool = false
    var rating: Int = 0
    var bidCeiling: Double?
    /// From the rest of the team, filled in by sync.
    var teamFavoriteCount: Int = 0
    var teamRatingAverage: Double?

    // Sale result: "sold", "rna" or "out" (withdrawn)
    var result: String?
    var price: Double?
    var buyer: String?
    var resultAt: Date?
    /// "feed" from the results reader, "manual" when typed in.
    var resultSource: String?

    var needsSync: Bool = false
    var sale: Sale?
    @Relationship(deleteRule: .cascade, inverse: \HipNote.hip) var notes: [HipNote] = []
    @Relationship(deleteRule: .cascade, inverse: \MediaItem.hip) var media: [MediaItem] = []

    init(hipNumber: Int, sire: String, dam: String) {
        self.hipNumber = hipNumber
        self.sire = sire
        self.dam = dam
    }
}

@Model
final class HipNote {
    var uuid: UUID
    var author: String
    /// "card" for the hip card's ink pad, or "page:<index>" for ink on a catalog page.
    var location: String
    var createdAt: Date
    var updatedAt: Date
    /// PencilKit drawing, kept so the original ink is never lost.
    var drawingData: Data
    var recognizedText: String
    var correctedText: String?
    var needsSync: Bool
    /// File name in storage once uploaded.
    var drawingPath: String?
    var hip: Hip?

    init(author: String, location: String) {
        self.uuid = UUID()
        self.author = author
        self.location = location
        self.createdAt = .now
        self.updatedAt = .now
        self.drawingData = Data()
        self.recognizedText = ""
        self.needsSync = true
    }

    var text: String { correctedText ?? recognizedText }

    var locationLabel: String {
        if location.hasPrefix("page:"), let page = Int(location.dropFirst(5)) {
            return "Catalog p. \(page + 1)"
        }
        return "Card"
    }
}

@Model
final class MediaItem {
    var uuid: UUID
    var author: String
    /// "photo" or "video"
    var kind: String
    var fileName: String
    var createdAt: Date
    var needsSync: Bool
    var hip: Hip?

    init(author: String, kind: String, fileName: String) {
        self.uuid = UUID()
        self.author = author
        self.kind = kind
        self.fileName = fileName
        self.createdAt = .now
        self.needsSync = true
    }

    var url: URL { AppFiles.url(fileName) }
}
