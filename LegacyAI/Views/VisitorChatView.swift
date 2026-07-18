import SwiftUI

/// Chat view for visitor mode — same chat UI but:
/// - Header shows "Visiting as [Name]"
/// - "Leave" button always accessible
/// - No tabs, no owner-only screens reachable
struct VisitorChatView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var chatStore: ChatStore

    @State private var draft = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var statusMessage = ""
    @State private var sendTask: Task<Void, Never>?
    @FocusState private var isInputFocused: Bool

    private let backendClient = BackendClient()

    @State private var completedTypingIDs = Set<UUID>()

    private var visitorName: String {
        sessionManager.currentSession?.role.visitorName ?? "Visitor"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Visitor mode indicator
                HStack {
                    Image(systemName: "person.fill")
                        .foregroundStyle(.secondary)
                    Text("Visiting as \(visitorName)")
                        .font(.footnote.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(Color(.secondarySystemBackground))

                if chatStore.messages.isEmpty {
                    visitorEmptyState
                } else {
                    messageList
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                }

                inputBar
            }
            .navigationTitle("Genesis")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Leave", role: .destructive) {
                        sessionManager.logout(chatStore: chatStore)
                    }
                }
            }
        }
    }

    // MARK: - Empty state

    private var visitorEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "message")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)

            Text("Welcome, \(visitorName)!")
                .font(.title3.bold())

            Text("Ask Genesis anything about its life, stories, and memories. Your conversation is private to this session.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(chatStore.messages) { message in
                        VisitorChatBubble(
                            message: message,
                            shouldTypewrite: message.role == .assistant && !completedTypingIDs.contains(message.id),
                            onTypingComplete: {
                                completedTypingIDs.insert(message.id)
                            },
                            onTypingUpdate: {
                                scrollToBottom(proxy: proxy, animated: false)
                            }
                        )
                        .id(message.id)
                    }

                    if isLoading {
                        ProgressView(statusMessage.isEmpty ? "Asking Genesis..." : statusMessage)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomAnchorID)
                }
                .padding()
            }
            .onChange(of: chatStore.messages.count) { _ in
                scrollToBottom(proxy: proxy, animated: true)
            }
            .onChange(of: isLoading) { _ in
                scrollToBottom(proxy: proxy, animated: true)
                if !isLoading {
                    Task {
                        try? await Task.sleep(nanoseconds: 150_000_000)
                        isInputFocused = true
                    }
                }
            }
            .onAppear {
                scrollToBottom(proxy: proxy, animated: false)
            }
        }
    }

    private static let bottomAnchorID = "visitor-bottom-anchor"

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
        }
    }

    // MARK: - Input bar

    private var inputBar: some View {
        HStack(alignment: .center, spacing: 8) {
            TextField("Ask about their life...", text: $draft)
                .textFieldStyle(.roundedBorder)
                .disabled(isLoading)
                .focused($isInputFocused)
                .submitLabel(.send)
                .onSubmit {
                    triggerSend()
                }

            if isLoading {
                Button("Cancel", role: .cancel) {
                    cancelSend()
                }
            } else {
                Button {
                    triggerSend()
                } label: {
                    Text("Send")
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .background(.bar)
    }

    // MARK: - Send logic

    private func triggerSend() {
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !isLoading else { return }
        sendTask = Task {
            await send()
        }
    }

    @MainActor
    private func send() async {
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isLoading else { return }

        guard let token = sessionManager.currentSession?.token else {
            sessionManager.handleUnauthorized(chatStore: chatStore)
            return
        }

        errorMessage = nil
        draft = ""
        isLoading = true
        statusMessage = "Asking Genesis..."
        defer {
            isLoading = false
            statusMessage = ""
            sendTask = nil
        }

        let history = chatStore.historyForAPI()
        chatStore.appendUserMessage(question)

        do {
            let reply = try await backendClient.sendChat(
                question: question,
                history: history,
                baseURL: settings.backendBaseURL,
                authToken: token
            )
            chatStore.appendAssistantMessage(reply.answer, sourceTitles: reply.sourceTitles)
        } catch BackendClient.ClientError.unauthorized {
            sessionManager.handleUnauthorized(chatStore: chatStore)
        } catch is CancellationError {
            errorMessage = "The chat request was cancelled."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func cancelSend() {
        statusMessage = "Cancelling..."
        sendTask?.cancel()
    }
}

// MARK: - Chat bubble (visitor version, no owner-specific styling)

private struct VisitorChatBubble: View {
    let message: ChatMessage
    let shouldTypewrite: Bool
    let onTypingComplete: () -> Void
    let onTypingUpdate: () -> Void

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 40)
            }

            VStack(alignment: .leading, spacing: 6) {
                if shouldTypewrite {
                    VisitorTypewriterText(
                        text: message.content,
                        onUpdate: onTypingUpdate,
                        onComplete: onTypingComplete
                    )
                    .foregroundStyle(.primary)
                } else {
                    Text(message.content)
                        .foregroundStyle(message.role == .user ? .white : .primary)
                }

                if message.role == .assistant, !message.sourceEntryTitles.isEmpty, !shouldTypewrite {
                    Text("From: \(message.sourceEntryTitles.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(message.role == .user ? Color.blue : Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if message.role == .assistant {
                Spacer(minLength: 40)
            }
        }
    }
}

private struct VisitorTypewriterText: View {
    let text: String
    var characterDelayNanoseconds: UInt64 = 18_000_000
    var onUpdate: () -> Void = {}
    var onComplete: () -> Void = {}

    @State private var displayedText = ""

    var body: some View {
        Text(displayedText)
            .task(id: text) {
                displayedText = ""
                var charactersSinceUpdate = 0

                for character in text {
                    try? await Task.sleep(nanoseconds: characterDelayNanoseconds)
                    if Task.isCancelled { return }

                    displayedText.append(character)
                    charactersSinceUpdate += 1
                    if charactersSinceUpdate >= 8 {
                        onUpdate()
                        charactersSinceUpdate = 0
                    }
                }

                onUpdate()
                onComplete()
            }
    }
}
