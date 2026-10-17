import SwiftUI
import SwiftData

@main
struct SaleCatalogApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [Sale.self, Hip.self, HipNote.self, MediaItem.self])
    }
}

/// Where imported catalogs, photos and videos are kept on the iPad.
enum AppFiles {
    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static func url(_ name: String) -> URL {
        documents.appendingPathComponent(name)
    }
}
