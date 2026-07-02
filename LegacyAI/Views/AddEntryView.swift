import SwiftUI

struct AddEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var archiveStore: ArchiveStore

    @State private var title = ""
    @State private var category = LifeEntry.Category.other
    @State private var date = Date()
    @State private var content = ""
    @State private var tags = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Memory") {
                    TextField("Title", text: $title)

                    Picker("Category", selection: $category) {
                        ForEach(LifeEntry.Category.allCases) { category in
                            Text(category.rawValue).tag(category)
                        }
                    }

                    DatePicker("Date", selection: $date, displayedComponents: .date)

                    TextField("Tags", text: $tags, prompt: Text("family, work, lesson"))
                }

                Section("Content") {
                    TextEditor(text: $content)
                        .frame(minHeight: 220)
                }
            }
            .navigationTitle("Add Memory")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        archiveStore.addEntry(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            content: content.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category,
            tags: parsedTags,
            date: date
        )
        dismiss()
    }

    private var parsedTags: [String] {
        tags
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
