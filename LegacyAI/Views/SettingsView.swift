import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var archiveStore: ArchiveStore
    @EnvironmentObject private var settings: AppSettings

    @State private var isTestingConnection = false
    @State private var isTestingChat = false
    @State private var connectionMessage: String?
    @State private var connectionSucceeded = false

    private let chatService = MLXChatService()

    var body: some View {
        NavigationStack {
            Form {
                Section("Persona") {
                    TextField("Persona name", text: $settings.personaName)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Voice and style notes")
                        TextEditor(text: $settings.styleNotes)
                            .frame(minHeight: 140)
                    }
                }

                Section("Local model server") {
                    TextField("Server address", text: $settings.serverBaseURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)

                    Picker("Chat model", selection: $settings.modelName) {
                        ForEach(ModelSettings.supportedModels) { model in
                            Text(model.displayName)
                                .tag(model.id)
                        }
                    }
                    .pickerStyle(.menu)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(selectedModel.description)
                            .foregroundStyle(.secondary)

                        Text(settings.modelName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    LabeledContent("Chat endpoint", value: chatEndpointText)
                        .font(.footnote)

                    Button {
                        Task {
                            await testConnection()
                        }
                    } label: {
                        if isTestingConnection {
                            ProgressView()
                        } else {
                            Text("Test connection")
                        }
                    }
                    .disabled(isTestingConnection)

                    Button {
                        Task {
                            await testChatResponse()
                        }
                    } label: {
                        if isTestingChat {
                            ProgressView()
                        } else {
                            Text("Test chat response")
                        }
                    }
                    .disabled(isTestingChat)

                    if let connectionMessage {
                        Text(connectionMessage)
                            .font(.footnote)
                            .foregroundStyle(connectionSucceeded ? .green : .red)
                    }

                    Text("Your iPhone and Mac must be on the same Wi-Fi network. On the Mac, open System Settings > Wi-Fi > Details, or run `ipconfig getifaddr en0` in Terminal to find the LAN IP. Use it like `http://192.168.1.23:8080`. Do not use `127.0.0.1` on a real iPhone; that points to the phone, not the Mac. The selected chat model must match the model used to start the MLX server.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Archive") {
                    LabeledContent("Memory entries", value: "\(archiveStore.entries.count)")
                }
            }
            .navigationTitle("Settings")
        }
    }

    private var chatEndpointText: String {
        chatService.chatCompletionsURLDescription(baseURL: settings.serverBaseURL)
    }

    private var selectedModel: ModelSettings.SupportedModel {
        ModelSettings.supportedModel(for: settings.modelName)
    }

    @MainActor
    private func testConnection() async {
        isTestingConnection = true
        connectionMessage = nil
        defer { isTestingConnection = false }

        do {
            connectionMessage = try await chatService.testConnection(
                baseURL: settings.serverBaseURL,
                modelName: settings.modelName
            )
            connectionSucceeded = true
        } catch {
            connectionMessage = error.localizedDescription
            connectionSucceeded = false
        }
    }

    @MainActor
    private func testChatResponse() async {
        isTestingChat = true
        connectionMessage = nil
        defer { isTestingChat = false }

        do {
            connectionMessage = try await chatService.testChatCompletion(
                baseURL: settings.serverBaseURL,
                modelName: settings.modelName
            )
            connectionSucceeded = true
        } catch {
            connectionMessage = error.localizedDescription
            connectionSucceeded = false
        }
    }
}
