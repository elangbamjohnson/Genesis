import Combine
import Foundation

@MainActor
final class AppSettings: ObservableObject {
    @Published var serverBaseURL: String {
        didSet { save() }
    }

    @Published var backendBaseURL: String {
        didSet { save() }
    }

    @Published var modelName: String {
        didSet { save() }
    }

    @Published var personaName: String {
        didSet { save() }
    }

    @Published var styleNotes: String {
        didSet { save() }
    }

    private enum Key {
        static let serverBaseURL = "serverBaseURL"
        static let backendBaseURL = "backendBaseURL"
        static let modelName = "modelName"
        static let personaName = "personaName"
        static let styleNotes = "styleNotes"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        serverBaseURL = defaults.string(forKey: Key.serverBaseURL) ?? "http://192.168.29.164:8080"
        backendBaseURL = defaults.string(forKey: Key.backendBaseURL) ?? "http://192.168.29.164:8090"

        let normalizedModelName = ModelSettings.normalizedModelName(
            defaults.string(forKey: Key.modelName) ?? ""
        )
        if normalizedModelName.isEmpty {
            modelName = ModelSettings.defaultModelName
            defaults.set(ModelSettings.defaultModelName, forKey: Key.modelName)
        } else {
            modelName = normalizedModelName
            defaults.set(normalizedModelName, forKey: Key.modelName)
        }

        personaName = defaults.string(forKey: Key.personaName) ?? "Me"
        styleNotes = defaults.string(forKey: Key.styleNotes) ?? "Answer calmly, directly, and in my own first-person voice."
    }

    private func save() {
        defaults.set(serverBaseURL, forKey: Key.serverBaseURL)
        defaults.set(backendBaseURL, forKey: Key.backendBaseURL)
        defaults.set(modelName, forKey: Key.modelName)
        defaults.set(personaName, forKey: Key.personaName)
        defaults.set(styleNotes, forKey: Key.styleNotes)
    }
}
