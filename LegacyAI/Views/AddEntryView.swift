import SwiftUI

struct AddEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var archiveStore: ArchiveStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var sessionManager: SessionManager

    @State private var title = ""
    @State private var category = LifeEntry.Category.other
    @State private var date = Date()
    @State private var content = ""
    @State private var tags = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }

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
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        
        Task {
            do {
                try await archiveStore.addEntry(
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    content: content.trimmingCharacters(in: .whitespacesAndNewlines),
                    category: category,
                    tags: parsedTags,
                    date: date,
                    baseURL: settings.backendBaseURL,
                    authToken: sessionManager.currentSession?.token ?? ""
                )
                dismiss()
            } catch {
                errorMessage = "Failed to save: \(error.localizedDescription)"
                isSaving = false
            }
        }
    }

    private var parsedTags: [String] {
        tags
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
