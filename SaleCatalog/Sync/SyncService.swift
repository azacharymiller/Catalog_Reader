import Foundation
import Observation
import Supabase
import SwiftData

/// Keeps this iPad and the team's shared server in step.
///
/// Everything is saved on the iPad first (the `needsSync` flags). Every 15
/// seconds while signed in, changed items go up and the team's changes come
/// down. With no connection the loop just tries again next time.
@MainActor
@Observable
final class SyncService {
    enum Status: Equatable {
        case notConfigured, signedOut, codeSent(String), syncing, synced(Date), failed(String)
    }

    private(set) var status: Status = .notConfigured
    private(set) var teamName: String?
    private var client: SupabaseClient?
    private var teamId: UUID?
    private var lastPull: [String: String] = [:]

    private let defaults = UserDefaults.standard

    init() {
        configure()
    }

    // MARK: Setup and sign-in

    /// The server's address and public key, typed in once in Settings.
    func configure() {
        guard let urlText = defaults.string(forKey: "serverURL"), let url = URL(string: urlText),
              let key = defaults.string(forKey: "serverKey"), !key.isEmpty else {
            client = nil
            status = .notConfigured
            return
        }
        client = SupabaseClient(supabaseURL: url, supabaseKey: key)
        status = .signedOut
    }

    /// Emails a six-digit sign-in code.
    func sendCode(to email: String) async {
        guard let client else { return }
        do {
            try await client.auth.signInWithOTP(email: email, shouldCreateUser: true)
            status = .codeSent(email)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func verify(code: String, email: String) async {
        guard let client else { return }
        do {
            try await client.auth.verifyOTP(email: email, token: code, type: .email)
            try await loadTeam()
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func loadTeam() async throws {
        guard let client else { return }
        let userId = try await client.auth.session.user.id
        let rows: [MemberRow] = try await client.from("team_members")
            .select("team_id, display_name, teams(name)")
            .eq("user_id", value: userId.uuidString.lowercased())
            .execute().value
        guard let row = rows.first else {
            status = .failed("Signed in, but not on a team yet. Ask the team admin to add you.")
            return
        }
        teamId = row.teamId
        teamName = row.teams?.name
        defaults.set(row.displayName, forKey: "authorName")
        status = .synced(.now)
    }

    // MARK: The loop

    func run(context: ModelContext) async {
        if client != nil, (try? await client?.auth.session) != nil, teamId == nil {
            try? await loadTeam()
        }
        while !Task.isCancelled {
            if teamId != nil { await syncNow(context: context) }
            try? await Task.sleep(for: .seconds(15))
        }
    }

    func syncNow(context: ModelContext) async {
        guard let client, let teamId else { return }
        let sales = (try? context.fetch(FetchDescriptor<Sale>())) ?? []
        status = .syncing
        do {
            let me = try await client.auth.session.user.id
            for sale in sales {
                try await push(sale: sale, team: teamId, user: me, client: client)
                try await pull(sale: sale, team: teamId, user: me, client: client, context: context)
            }
            try context.save()
            status = .synced(.now)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    // MARK: Up

    private func push(sale: Sale, team: UUID, user: UUID, client: SupabaseClient) async throws {
        let author = defaults.string(forKey: "authorName") ?? ""
        let dirtyHips = sale.hips.filter(\.needsSync)
        if !dirtyHips.isEmpty {
            try await client.from("hip_marks").upsert(dirtyHips.map {
                HipMarkRow(teamId: team, saleId: sale.saleId, hip: $0.hipNumber,
                           shortlisted: $0.isShortlisted, bidCeiling: $0.bidCeiling, updatedBy: author)
            }).execute()
            try await client.from("personal_marks").upsert(dirtyHips.map {
                PersonalMarkRow(teamId: team, userId: user, saleId: sale.saleId, hip: $0.hipNumber,
                                author: author, favorite: $0.isFavorite, rating: $0.rating)
            }).execute()
            for hip in dirtyHips where hip.resultSource == "manual" {
                guard let result = hip.result else { continue }
                // A result from the feed can't be overwritten; that refusal is fine.
                _ = try? await client.from("results").upsert(
                    ResultRow(saleId: sale.saleId, hip: hip.hipNumber, result: result,
                              price: hip.price, buyer: hip.buyer, source: "manual")
                ).execute()
            }
            dirtyHips.forEach { $0.needsSync = false }
        }

        for hip in sale.hips {
            for note in hip.notes where note.needsSync && note.author == author {
                let path = "\(team.uuidString.lowercased())/\(note.uuid.uuidString.lowercased()).ink"
                try await client.storage.from("ink").upload(path, data: note.drawingData, options: FileOptions(upsert: true))
                try await client.from("notes").upsert(NoteRow(
                    id: note.uuid, teamId: team, saleId: sale.saleId, hip: hip.hipNumber, author: note.author,
                    location: note.location, recognizedText: note.recognizedText,
                    correctedText: note.correctedText, drawingPath: path, updatedAt: nil
                )).execute()
                note.drawingPath = path
                note.needsSync = false
            }
            for item in hip.media where item.needsSync && item.author == author {
                guard let data = try? Data(contentsOf: item.url) else { continue }
                let path = "\(team.uuidString.lowercased())/\(item.fileName)"
                try await client.storage.from("media").upload(path, data: data, options: FileOptions(upsert: true))
                try await client.from("media").upsert(MediaRow(
                    id: item.uuid, teamId: team, saleId: sale.saleId, hip: hip.hipNumber,
                    author: item.author, kind: item.kind, storagePath: path
                )).execute()
                item.needsSync = false
            }
        }
    }

    // MARK: Down

    private func pull(sale: Sale, team: UUID, user: UUID, client: SupabaseClient, context: ModelContext) async throws {
        let byNumber = Dictionary(sale.hips.map { ($0.hipNumber, $0) }, uniquingKeysWith: { a, _ in a })
        let since = lastPull[sale.saleId] ?? "1970-01-01T00:00:00Z"
        var newest = since

        let marks: [HipMarkRow] = try await client.from("hip_marks").select()
            .eq("team_id", value: team.uuidString.lowercased()).eq("sale_id", value: sale.saleId).gt("updated_at", value: since)
            .execute().value
        for mark in marks {
            newest = max(newest, mark.updatedAt ?? since)
            guard let hip = byNumber[mark.hip], !hip.needsSync else { continue }
            hip.isShortlisted = mark.shortlisted
            hip.bidCeiling = mark.bidCeiling
        }

        // Favorites and ratings: small, so recount the whole sale each time.
        let personal: [PersonalMarkRow] = try await client.from("personal_marks").select()
            .eq("team_id", value: team.uuidString.lowercased()).eq("sale_id", value: sale.saleId)
            .execute().value
        let grouped = Dictionary(grouping: personal, by: \.hip)
        for hip in sale.hips {
            let rows = grouped[hip.hipNumber] ?? []
            hip.teamFavoriteCount = rows.filter(\.favorite).count
            let ratings = rows.map(\.rating).filter { $0 > 0 }
            hip.teamRatingAverage = ratings.isEmpty ? nil : Double(ratings.reduce(0, +)) / Double(ratings.count)
        }

        let results: [ResultRow] = try await client.from("results").select()
            .eq("sale_id", value: sale.saleId).gt("updated_at", value: since)
            .execute().value
        for row in results {
            newest = max(newest, row.updatedAt ?? since)
            guard let hip = byNumber[row.hip] else { continue }
            if hip.needsSync && hip.resultSource == "manual" && row.source == "manual" { continue }
            hip.result = row.result
            hip.price = row.price
            hip.buyer = row.buyer
            hip.resultSource = row.source
            hip.resultAt = .now
        }

        let notes: [NoteRow] = try await client.from("notes").select()
            .eq("team_id", value: team.uuidString.lowercased()).eq("sale_id", value: sale.saleId).gt("updated_at", value: since)
            .execute().value
        for row in notes {
            newest = max(newest, row.updatedAt ?? since)
            guard let hip = byNumber[row.hip] else { continue }
            let existing = hip.notes.first { $0.uuid == row.id }
            if existing?.needsSync == true { continue }
            let note = existing ?? {
                let new = HipNote(author: row.author, location: row.location)
                new.uuid = row.id
                context.insert(new)
                new.hip = hip
                return new
            }()
            note.recognizedText = row.recognizedText
            note.correctedText = row.correctedText
            note.updatedAt = .now
            note.needsSync = false
            if let path = row.drawingPath, path != note.drawingPath,
               let data = try? await client.storage.from("ink").download(path: path) {
                note.drawingData = data
                note.drawingPath = path
            }
        }

        let media: [MediaRow] = try await client.from("media").select()
            .eq("team_id", value: team.uuidString.lowercased()).eq("sale_id", value: sale.saleId)
            .execute().value
        for row in media {
            guard let hip = byNumber[row.hip], !hip.media.contains(where: { $0.uuid == row.id }) else { continue }
            let fileName = (row.storagePath as NSString).lastPathComponent
            guard let data = try? await client.storage.from("media").download(path: row.storagePath),
                  (try? data.write(to: AppFiles.url(fileName))) != nil else { continue }
            let item = MediaItem(author: row.author, kind: row.kind, fileName: fileName)
            item.uuid = row.id
            item.needsSync = false
            context.insert(item)
            item.hip = hip
        }

        lastPull[sale.saleId] = newest
    }
}

// MARK: Rows, as stored on the server

private struct MemberRow: Decodable {
    struct Team: Decodable { let name: String }
    let teamId: UUID
    let displayName: String
    let teams: Team?
    enum CodingKeys: String, CodingKey {
        case teamId = "team_id", displayName = "display_name", teams
    }
}

private struct HipMarkRow: Codable {
    let teamId: UUID
    let saleId: String
    let hip: Int
    let shortlisted: Bool
    let bidCeiling: Double?
    let updatedBy: String?
    var updatedAt: String? = nil
    enum CodingKeys: String, CodingKey {
        case teamId = "team_id", saleId = "sale_id", hip, shortlisted
        case bidCeiling = "bid_ceiling", updatedBy = "updated_by", updatedAt = "updated_at"
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(teamId, forKey: .teamId)
        try c.encode(saleId, forKey: .saleId)
        try c.encode(hip, forKey: .hip)
        try c.encode(shortlisted, forKey: .shortlisted)
        try c.encode(bidCeiling, forKey: .bidCeiling)
        try c.encode(updatedBy, forKey: .updatedBy)
    }
}

private struct PersonalMarkRow: Codable {
    let teamId: UUID
    let userId: UUID
    let saleId: String
    let hip: Int
    let author: String
    let favorite: Bool
    let rating: Int
    enum CodingKeys: String, CodingKey {
        case teamId = "team_id", userId = "user_id", saleId = "sale_id", hip, author, favorite, rating
    }
}

private struct ResultRow: Codable {
    let saleId: String
    let hip: Int
    let result: String
    let price: Double?
    let buyer: String?
    let source: String
    var updatedAt: String? = nil
    enum CodingKeys: String, CodingKey {
        case saleId = "sale_id", hip, result, price, buyer, source, updatedAt = "updated_at"
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(saleId, forKey: .saleId)
        try c.encode(hip, forKey: .hip)
        try c.encode(result, forKey: .result)
        try c.encode(price, forKey: .price)
        try c.encode(buyer, forKey: .buyer)
        try c.encode(source, forKey: .source)
    }
}

private struct NoteRow: Codable {
    let id: UUID
    let teamId: UUID
    let saleId: String
    let hip: Int
    let author: String
    let location: String
    let recognizedText: String
    let correctedText: String?
    let drawingPath: String?
    let updatedAt: String?
    enum CodingKeys: String, CodingKey {
        case id, teamId = "team_id", saleId = "sale_id", hip, author, location
        case recognizedText = "recognized_text", correctedText = "corrected_text"
        case drawingPath = "drawing_path", updatedAt = "updated_at"
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(teamId, forKey: .teamId)
        try c.encode(saleId, forKey: .saleId)
        try c.encode(hip, forKey: .hip)
        try c.encode(author, forKey: .author)
        try c.encode(location, forKey: .location)
        try c.encode(recognizedText, forKey: .recognizedText)
        try c.encode(correctedText, forKey: .correctedText)
        try c.encode(drawingPath, forKey: .drawingPath)
    }
}

private struct MediaRow: Codable {
    let id: UUID
    let teamId: UUID
    let saleId: String
    let hip: Int
    let author: String
    let kind: String
    let storagePath: String
    enum CodingKeys: String, CodingKey {
        case id, teamId = "team_id", saleId = "sale_id", hip, author, kind, storagePath = "storage_path"
    }
}
