import Foundation
import Security
import Combine

// MARK: - Session model

/// The role of the currently authenticated user.
enum UserRole: Codable, Equatable {
    case owner
    case visitor(visitorId: String, visitorName: String)

    var isOwner: Bool {
        if case .owner = self { return true }
        return false
    }

    var isVisitor: Bool {
        if case .visitor = self { return true }
        return false
    }

    var visitorName: String? {
        if case .visitor(_, let name) = self { return name }
        return nil
    }

    var visitorId: String? {
        if case .visitor(let id, _) = self { return id }
        return nil
    }
}

/// A stored session — persisted in Keychain, never UserDefaults.
struct StoredSession: Codable, Equatable {
    let role: UserRole
    let token: String
}

// MARK: - SessionManager

/// Single source of truth for authentication state.
///
/// - Stores token + role in Keychain (survives app relaunch).
/// - Only one session active at a time.
/// - Fail-closed: if Keychain read fails → no session → entry screen.
@MainActor
final class SessionManager: ObservableObject {

    @Published private(set) var currentSession: StoredSession?

    /// True while a login/register network call is in flight.
    @Published var isAuthenticating = false

    /// User-facing error from the last login attempt.
    @Published var authError: String?

    private let keychainKey = "com.genesis.session"
    private let client = BackendClient()

    init() {
        currentSession = loadFromKeychain()
    }

    // MARK: - Public API

    /// Owner login: validate the token against the backend, then store.
    func loginAsOwner(token: String, backendBaseURL: String) async {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            authError = "Token cannot be empty."
            return
        }

        isAuthenticating = true
        authError = nil
        defer { isAuthenticating = false }

        // Validate by hitting /health with the token — if the backend
        // rejects it on a real authenticated endpoint, we catch it.
        // We use /v1/memories (GET, owner-readable) as a lightweight check.
        do {
            let valid = try await client.validateOwnerToken(baseURL: backendBaseURL, token: trimmed)
            if valid {
                let session = StoredSession(role: .owner, token: trimmed)
                saveToKeychain(session)
                currentSession = session
            } else {
                authError = "Invalid token — the backend rejected it."
            }
        } catch {
            authError = "Could not reach backend: \(error.localizedDescription)"
        }
    }

    /// Visitor registration: call self-register, store the returned token.
    func registerAsVisitor(name: String, backendBaseURL: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            authError = "Please enter your name."
            return
        }

        isAuthenticating = true
        authError = nil
        defer { isAuthenticating = false }

        do {
            let result = try await client.selfRegisterVisitor(name: trimmed, baseURL: backendBaseURL)
            let role = UserRole.visitor(visitorId: result.visitorId, visitorName: result.visitorName)
            let session = StoredSession(role: role, token: result.token)
            saveToKeychain(session)
            currentSession = session
        } catch {
            authError = "Registration failed: \(error.localizedDescription)"
        }
    }

    /// Log out: clear Keychain, clear in-memory state.
    /// Pass the ChatStore so we can wipe its history (prevents session bleed).
    func logout(chatStore: ChatStore) {
        deleteFromKeychain()
        chatStore.clear()
        currentSession = nil
        authError = nil
    }

    /// Called when any network request returns 401/403.
    /// Immediately drops the session and returns user to entry screen.
    func handleUnauthorized(chatStore: ChatStore) {
        logout(chatStore: chatStore)
        authError = "Your session has expired. Please log in again."
    }

    // MARK: - Keychain helpers

    private func saveToKeychain(_ session: StoredSession) {
        // Delete any existing entry first
        deleteFromKeychain()

        guard let data = try? JSONEncoder().encode(session) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        SecItemAdd(query as CFDictionary, nil)
    }

    private func loadFromKeychain() -> StoredSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let session = try? JSONDecoder().decode(StoredSession.self, from: data) else {
            // Fail-closed: any Keychain error → no session → entry screen
            return nil
        }

        return session
    }

    private func deleteFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
