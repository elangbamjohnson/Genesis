import SwiftUI

/// Entry screen shown when no valid session exists.
/// Offers two flows: Owner Login or Visit Genesis.
struct EntryView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    @EnvironmentObject private var settings: AppSettings

    @State private var mode: EntryMode = .choose
    @State private var ownerToken = ""
    @State private var visitorName = ""

    enum EntryMode {
        case choose
        case ownerLogin
        case visitorRegister
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                // Logo area
                VStack(spacing: 12) {
                    Image(systemName: "brain.head.profile.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.tint)

                    Text("Genesis")
                        .font(.largeTitle.bold())

                    Text("Your digital legacy, preserved.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Mode-specific content
                Group {
                    switch mode {
                    case .choose:
                        chooseView
                    case .ownerLogin:
                        ownerLoginView
                    case .visitorRegister:
                        visitorRegisterView
                    }
                }
                .padding(.horizontal, 24)

                Spacer()

                // Error display
                if let error = sessionManager.authError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 8)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .animation(.easeInOut(duration: 0.25), value: mode)
        }
    }

    // MARK: - Choose mode

    private var chooseView: some View {
        VStack(spacing: 16) {
            Button {
                mode = .ownerLogin
                sessionManager.authError = nil
            } label: {
                Label("Owner Login", systemImage: "person.badge.key.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button {
                mode = .visitorRegister
                sessionManager.authError = nil
            } label: {
                Label("Visit Genesis", systemImage: "person.fill.questionmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    // MARK: - Owner login

    private var ownerLoginView: some View {
        VStack(spacing: 16) {
            SecureField("Enter your author token", text: $ownerToken)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .onSubmit { ownerLogin() }

            Button {
                ownerLogin()
            } label: {
                if sessionManager.isAuthenticating {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Log In")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(ownerToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sessionManager.isAuthenticating)

            Button("Back") {
                mode = .choose
                ownerToken = ""
                sessionManager.authError = nil
            }
            .foregroundStyle(.secondary)
            .disabled(sessionManager.isAuthenticating)

            Text("Enter the token from your backend's `.env` file (`GENESIS_AUTHOR_TOKEN`).")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Visitor registration

    private var visitorRegisterView: some View {
        VStack(spacing: 16) {
            TextField("Your name", text: $visitorName)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.words)
                .submitLabel(.go)
                .onSubmit { visitorRegister() }

            // TODO(phase-2): Relationship field — backend column exists but
            // relationship-based tone/persona shaping is deferred.

            Button {
                visitorRegister()
            } label: {
                if sessionManager.isAuthenticating {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Start Visiting")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(visitorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sessionManager.isAuthenticating)

            Button("Back") {
                mode = .choose
                visitorName = ""
                sessionManager.authError = nil
            }
            .foregroundStyle(.secondary)
            .disabled(sessionManager.isAuthenticating)

            Text("You'll be able to chat with Genesis in read-only mode. Your conversations are private to your session.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Actions

    private func ownerLogin() {
        Task {
            await sessionManager.loginAsOwner(
                token: ownerToken,
                backendBaseURL: settings.backendBaseURL
            )
        }
    }

    private func visitorRegister() {
        Task {
            await sessionManager.registerAsVisitor(
                name: visitorName,
                backendBaseURL: settings.backendBaseURL
            )
        }
    }
}
