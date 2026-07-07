import Combine
import Foundation

/// Persists the on-device chat thread and builds API history for `/v1/chat`.
@MainActor
final class ChatStore: ObservableObject {
    /// Match the backend thread window (~4 back-and-forth exchanges).
    static let maxHistoryTurns = 8

    @Published private(set) var messages: [ChatMessage] = []

    private let defaults: UserDefaults
    private let storageKey = "genesis.chatMessages"
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        load()
    }

    /// Prior turns only — excludes the message about to be sent as `question`.
    func historyForAPI() -> [BackendClient.ChatTurn] {
        messages
            .filter { $0.role == .user || $0.role == .assistant }
            .suffix(Self.maxHistoryTurns)
            .map { BackendClient.ChatTurn(role: $0.role.rawValue, content: $0.content) }
    }

    func appendUserMessage(_ content: String) {
        messages.append(ChatMessage(role: .user, content: content))
        save()
    }

    func appendAssistantMessage(_ content: String, sourceTitles: [String] = []) {
        messages.append(
            ChatMessage(
                role: .assistant,
                content: content,
                sourceEntryTitles: sourceTitles
            )
        )
        save()
    }

    func clear() {
        messages = []
        defaults.removeObject(forKey: storageKey)
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey) else { return }
        do {
            messages = try decoder.decode([ChatMessage].self, from: data)
        } catch {
            messages = []
        }
    }

    private func save() {
        guard let data = try? encoder.encode(messages) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
