import Combine
import Foundation

@MainActor
final class ArchiveStore: ObservableObject {
    @Published private(set) var entries: [LifeEntry] = []
    @Published var loadError: String?

    private let fileManager: FileManager
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let client = BackendClient()

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        Task {
            await load()
        }
    }


    func pushArchiveToBackend(baseURL: String, authToken: String) async throws -> BackendClient.ImportResult {
        let localEntries = try loadLocalCacheEntries()
        let result = try await client.importEntries(localEntries, baseURL: baseURL, overwrite: false, authToken: authToken)
        await load(baseURL: baseURL)
        return result
    }

    func load(baseURL: String? = nil) async {
        if let baseURL = baseURL, !baseURL.isEmpty {
            do {
                let fetched = try await client.fetchMemories(baseURL: baseURL)
                self.entries = fetched
                saveLocalCache(fetched)
                self.loadError = nil
            } catch {
                self.loadError = "Offline mode: \(error.localizedDescription)"
                await loadLocalCache()
            }
        } else {
            await loadLocalCache()
        }
    }

    private func loadLocalCache() async {
        if let local = try? loadLocalCacheEntries() {
            self.entries = local
        } else {
            self.entries = (try? loadSeedEntries()) ?? []
            saveLocalCache(entries)
        }
    }

    private func loadLocalCacheEntries() throws -> [LifeEntry] {
        let archiveURL = try archiveFileURL()
        if fileManager.fileExists(atPath: archiveURL.path) {
            let data = try Data(contentsOf: archiveURL)
            return try decoder.decode([LifeEntry].self, from: data)
        }
        return []
    }

    private func saveLocalCache(_ newEntries: [LifeEntry]) {
        do {
            let archiveURL = try archiveFileURL()
            let data = try encoder.encode(newEntries)
            try data.write(to: archiveURL, options: [.atomic])
        } catch {
            loadError = "Cache write failed: \(error.localizedDescription)"
        }
    }

    private func archiveFileURL() throws -> URL {
        let documentsURL = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        return documentsURL.appendingPathComponent("archive_entries.json")
    }

    private func loadSeedEntries() throws -> [LifeEntry] {
        guard let sampleURL = Bundle.main.url(forResource: "sample_entries", withExtension: "json") else {
            return []
        }

        let data = try Data(contentsOf: sampleURL)
        return try decoder.decode([LifeEntry].self, from: data)
    }
}
