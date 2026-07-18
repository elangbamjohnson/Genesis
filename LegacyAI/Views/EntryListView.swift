import SwiftUI

struct EntryListView: View {
    @EnvironmentObject private var archiveStore: ArchiveStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var sessionManager: SessionManager

    @State private var searchText = ""
    @State private var isShowingAddEntry = false
    @State private var isShowingImport = false
    @State private var deleteError: String?

    private var filteredEntries: [LifeEntry] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return archiveStore.entries
        }

        return archiveStore.entries.filter { entry in
            let searchable = [
                entry.title,
                entry.content,
                entry.category.rawValue,
                entry.tags.joined(separator: " ")
            ].joined(separator: " ").lowercased()

            return searchable.contains(searchText.lowercased())
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredEntries) { entry in
                    NavigationLink {
                        EntryDetailView(entry: entry)
                    } label: {
                        EntryRow(entry: entry)
                    }
                }
                .onDelete(perform: delete)
            }
            .searchable(text: $searchText, prompt: "Search memories")
            .navigationTitle("Archive")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Add memory", systemImage: "square.and.pencil") {
                            isShowingAddEntry = true
                        }

                        Button("Import files", systemImage: "doc.badge.plus") {
                            isShowingImport = true
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $isShowingAddEntry) {
                AddEntryView()
            }
            .sheet(isPresented: $isShowingImport) {
                ImportEntriesView()
            }
            .alert("Delete Failed", isPresented: Binding(
                get: { deleteError != nil },
                set: { if !$0 { deleteError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                if let deleteError {
                    Text(deleteError)
                }
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        let ids = Set(offsets.map { filteredEntries[$0].id })
        Task {
            do {
                try await archiveStore.deleteEntries(withIDs: ids, baseURL: settings.backendBaseURL, authToken: sessionManager.currentSession?.token ?? "")
            } catch {
                deleteError = "Failed to delete from backend: \(error.localizedDescription)"
            }
        }
    }
}

private struct EntryRow: View {
    let entry: LifeEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.title)
                .font(.headline)

            Text("\(entry.category.rawValue) · \(entry.date.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(entry.content)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}

private struct EntryDetailView: View {
    let entry: LifeEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(entry.title)
                    .font(.title2.bold())

                Text("\(entry.category.rawValue) · \(entry.date.formatted(date: .long, time: .omitted))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if !entry.tags.isEmpty {
                    Text(entry.tags.map { "#\($0)" }.joined(separator: " "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text(entry.content)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
        .navigationTitle("Memory")
        .navigationBarTitleDisplayMode(.inline)
    }
}
