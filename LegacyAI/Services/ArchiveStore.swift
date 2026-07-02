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
    @Published private(set) var loadError: String?

    private let fileManager: FileManager
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

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
        date: Date
    ) {
        let entry = LifeEntry(
            title: title,
            content: content,
            category: category,
            tags: tags,
            date: date
        )

        entries.insert(entry, at: 0)
        save()
    }

    func deleteEntries(withIDs ids: Set<LifeEntry.ID>) {
        entries.removeAll { ids.contains($0.id) }
        save()
    }

    func importFiles(from urls: [URL]) async -> ImportSummary {
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
                importedEntries.append(
                    LifeEntry(
                        title: title,
                        content: content,
                        category: .imported,
                        tags: [],
                        date: Date()
                    )
                )
            } catch {
                failedFileNames.append(url.lastPathComponent)
            }
        }

        entries.insert(contentsOf: importedEntries, at: 0)
        save()

        return ImportSummary(
            importedCount: importedEntries.count,
            failedFileNames: failedFileNames
        )
    }

    @discardableResult
    func importSeedEntries() throws -> Int {
        let seedEntries = try loadSeedEntries()
        let existingIDs = Set(entries.map(\.id))
        let newEntries = seedEntries.filter { !existingIDs.contains($0.id) }

        guard !newEntries.isEmpty else {
            return 0
        }

        entries.insert(contentsOf: newEntries, at: 0)
        save()

        return newEntries.count
    }

    private func load() async {
        do {
            let archiveURL = try archiveFileURL()
            if fileManager.fileExists(atPath: archiveURL.path) {
                let data = try Data(contentsOf: archiveURL)
                entries = try decoder.decode([LifeEntry].self, from: data)
            } else {
                entries = try loadSeedEntries()
                save()
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func save() {
        do {
            let archiveURL = try archiveFileURL()
            let data = try encoder.encode(entries)
            try data.write(to: archiveURL, options: [.atomic])
        } catch {
            loadError = error.localizedDescription
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
