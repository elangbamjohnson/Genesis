import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var archiveStore: ArchiveStore
    @EnvironmentObject private var settings: AppSettings

    @State private var messages: [ChatMessage] = []
    @State private var draft = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var statusMessage = ""
    @State private var sendTask: Task<Void, Never>?
    @FocusState private var isInputFocused: Bool

    private let retrievalEngine = RetrievalEngine()
    private let promptBuilder = PersonaPromptBuilder()
    private let chatService = MLXChatService()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if archiveStore.entries.isEmpty && messages.isEmpty {
                    emptyState
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
            .navigationTitle("Legacy Chat")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "archivebox")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)

            Text("Add memories first")
                .font(.title3.bold())

            Text("Use the Archive tab to write memories or import .txt/.md files. Answers are grounded only in saved memories.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(messages) { message in
                        ChatBubble(message: message)
                            .id(message.id)
                    }

                    if isLoading {
                        ProgressView(statusMessage.isEmpty ? "Asking local model..." : statusMessage)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomAnchorID)
                }
                .padding()
            }
            .onChange(of: messages.count) { _ in
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
            .onChange(of: isInputFocused) { focused in
                guard focused else { return }
                Task {
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    scrollToBottom(proxy: proxy, animated: true)
                }
            }
            .onAppear {
                scrollToBottom(proxy: proxy, animated: false)
            }
        }
    }

    private static let bottomAnchorID = "bottom-anchor"

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
        }
    }

    private var inputBar: some View {
        HStack(alignment: .center, spacing: 8) {
            TextField("Ask about your life...", text: $draft)
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

        errorMessage = nil
        draft = ""
        isLoading = true
        statusMessage = "Checking local server..."
        defer {
            isLoading = false
            statusMessage = ""
            sendTask = nil
        }

        let intent = ConversationIntentClassifier.classify(question)

        let retrievedEntries: [LifeEntry]
        if intent == .smallTalk {
            retrievedEntries = []
        } else {
            retrievedEntries = retrievalEngine.retrieveRelevantEntries(
                for: question,
                from: archiveStore.entries
            )
        }
        let sourceTitles = retrievedEntries.map(\.title)

        messages.append(ChatMessage(role: .user, content: question))

        if intent == .informationRequest, retrievedEntries.isEmpty {
            messages.append(
                ChatMessage(
                    role: .assistant,
                    content: missingMemoryResponse()
                )
            )
            return
        }

        let systemPrompt: String
        if intent == .smallTalk {
            systemPrompt = promptBuilder.buildSmallTalkSystemPrompt(
                personaName: settings.personaName,
                styleNotes: settings.styleNotes
            )
        } else {
            systemPrompt = promptBuilder.buildSystemPrompt(
                personaName: settings.personaName,
                styleNotes: settings.styleNotes,
                memories: retrievedEntries
            )
        }
        let userPrompt: String
        if intent == .smallTalk {
            userPrompt = promptBuilder.buildSmallTalkUserPrompt(question: question)
        } else {
            userPrompt = promptBuilder.buildUserPrompt(question: question)
        }
        let history = Array(messages.dropLast())

        do {
            statusMessage = "Waiting for local model. First response can take a while..."
            let answer = try await chatService.send(
                question: userPrompt,
                systemPrompt: systemPrompt,
                history: history,
                baseURL: settings.serverBaseURL,
                modelName: settings.modelName,
                maxTokens: 400,
                timeoutInterval: 120
            )
            messages.append(
                ChatMessage(
                    role: .assistant,
                    content: answer,
                    sourceEntryTitles: sourceTitles
                )
            )
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

    private func missingMemoryResponse() -> String {
        "I could not find a saved memory that answers that yet. If you add or retag a memory about it in the Archive, I can answer from that record."
    }
}

private struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 40)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(message.content)
                    .foregroundStyle(message.role == .user ? .white : .primary)

                if message.role == .assistant, !message.sourceEntryTitles.isEmpty {
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
