import SwiftUI
import UniformTypeIdentifiers

struct ImportEntriesView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var archiveStore: ArchiveStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var sessionManager: SessionManager

    @State private var isShowingImporter = false
    @State private var importSummary: ImportSummary?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Import plain text or markdown files. Each file becomes one memory entry, and the filename becomes the title.")
                    .foregroundStyle(.secondary)

                Button("Choose files") {
                    isShowingImporter = true
                }
                .buttonStyle(.borderedProminent)

                if let importSummary {
                    Text("Imported \(importSummary.importedCount) file(s).")
                        .font(.headline)

                    if !importSummary.failedFileNames.isEmpty {
                        Text("Failed: \(importSummary.failedFileNames.joined(separator: ", "))")
                            .foregroundStyle(.red)
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Import Files")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .fileImporter(
                isPresented: $isShowingImporter,
                allowedContentTypes: supportedTypes,
                allowsMultipleSelection: true
            ) { result in
                Task {
                    await handleImport(result)
                }
            }
        }
    }

    private var supportedTypes: [UTType] {
        var types: [UTType] = [.plainText, .text]
        if let markdown = UTType(filenameExtension: "md") {
            types.append(markdown)
        }
        if let markdown = UTType(filenameExtension: "markdown") {
            types.append(markdown)
        }
        return types
    }

    @MainActor
    private func handleImport(_ result: Result<[URL], Error>) async {
        do {
            let urls = try result.get()
            importSummary = await archiveStore.importFiles(from: urls, baseURL: settings.backendBaseURL, authToken: sessionManager.currentSession?.token ?? "")
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
