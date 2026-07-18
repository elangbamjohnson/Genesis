import Combine
import Foundation
import UniformTypeIdentifiers

struct ImportSummary: Equatable {
    var importedCount: Int
    var failedFileNames: [String]
}

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

    func addEntry(
        title: String,
        content: String,
        category: LifeEntry.Category,
        tags: [String],
        date: Date,
        baseURL: String,
        authToken: String
    ) async throws {
        let entry = LifeEntry(
            title: title,
            content: content,
            category: category,
            tags: tags,
            date: date
        )

        let created = try await client.createMemory(entry, baseURL: baseURL, authToken: authToken)
        entries.insert(created, at: 0)
        saveLocalCache(entries)
    }

    func deleteEntries(withIDs ids: Set<LifeEntry.ID>, baseURL: String, authToken: String) async throws {
        for id in ids {
            try await client.deleteMemory(id: id, baseURL: baseURL, authToken: authToken)
        }
        entries.removeAll { ids.contains($0.id) }
        saveLocalCache(entries)
    }

    func importFiles(from urls: [URL], baseURL: String, authToken: String) async -> ImportSummary {
        var importedEntries: [LifeEntry] = []
        var failedFileNames: [String] = []

        for url in urls {
            let didStartAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                let title = url.deletingPathExtension().lastPathComponent
                let entry = LifeEntry(
                    title: title,
                    content: content,
                    category: .imported,
                    tags: [],
                    date: Date()
                )
                let created = try await client.createMemory(entry, baseURL: baseURL, authToken: authToken)
                importedEntries.append(created)
            } catch {
                failedFileNames.append(url.lastPathComponent)
            }
        }

        entries.insert(contentsOf: importedEntries, at: 0)
        saveLocalCache(entries)

        return ImportSummary(
            importedCount: importedEntries.count,
            failedFileNames: failedFileNames
        )
    }

    @discardableResult
    func importSeedEntries(baseURL: String, authToken: String) async throws -> Int {
        let seedEntries = try loadSeedEntries()
        let existingIDs = Set(entries.map(\.id))
        let newEntries = seedEntries.filter { !existingIDs.contains($0.id) }

        guard !newEntries.isEmpty else {
            return 0
        }

        let result = try await client.importEntries(newEntries, baseURL: baseURL, overwrite: false, authToken: authToken)
        
        // Reload all to get updated list
        await load(baseURL: baseURL)
        return result.imported
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
