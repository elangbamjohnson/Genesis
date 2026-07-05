import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var archiveStore: ArchiveStore
    @EnvironmentObject private var settings: AppSettings

    @State private var isTestingConnection = false
    @State private var isTestingChat = false
    @State private var connectionMessage: String?
    @State private var connectionSucceeded = false
    
    @State private var isTestingBackend = false
    @State private var backendMessage: String?
    @State private var backendSucceeded = false

    @State private var isPushingArchive = false
    @State private var pushMessage: String?

    private let chatService = MLXChatService()
    private let backendClient = BackendClient()

    var body: some View {
        NavigationStack {
            Form {
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

                Section("Backend Database") {
                    TextField("Backend address", text: $settings.backendBaseURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)

                    Button {
                        Task {
                            await testBackendConnection()
                        }
                    } label: {
                        if isTestingBackend {
                            ProgressView()
                        } else {
                            Text("Test connection")
                        }
                    }
                    .disabled(isTestingBackend)

                    Button {
                        Task {
                            await pushArchiveToBackend()
                        }
                    } label: {
                        if isPushingArchive {
                            ProgressView()
                        } else {
                            Text("Push local archive to backend")
                        }
                    }
                    .disabled(isPushingArchive)

                    if let backendMessage {
                        Text(backendMessage)
                            .font(.footnote)
                            .foregroundStyle(backendSucceeded ? .green : .red)
                    }

                    if let pushMessage {
                        Text(pushMessage)
                            .font(.footnote)
                            .foregroundStyle(.green)
                    }

                    Text("The app communicates directly with the Python/FastAPI server. Use your Mac's LAN IP address with port 8090, e.g., `http://192.168.1.23:8090`.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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

    @MainActor
    private func testBackendConnection() async {
        isTestingBackend = true
        backendMessage = nil
        defer { isTestingBackend = false }

        do {
            let healthy = try await backendClient.checkHealth(baseURL: settings.backendBaseURL)
            if healthy {
                backendMessage = "Connected. Backend is reachable."
                backendSucceeded = true
            } else {
                backendMessage = "Backend connected but health check returned non-200 response."
                backendSucceeded = false
            }
        } catch {
            backendMessage = error.localizedDescription
            backendSucceeded = false
        }
    }

    @MainActor
    private func pushArchiveToBackend() async {
        isPushingArchive = true
        pushMessage = nil
        backendMessage = nil
        defer { isPushingArchive = false }

        do {
            let result = try await archiveStore.pushArchiveToBackend(baseURL: settings.backendBaseURL)
            pushMessage = "Successfully pushed! Imported: \(result.imported), Skipped: \(result.skipped), Failed: \(result.failed)."
        } catch {
            backendMessage = "Failed to push archive: \(error.localizedDescription)"
            backendSucceeded = false
        }
    }
}
