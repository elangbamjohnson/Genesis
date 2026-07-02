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
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(messages) { message in
                    ChatBubble(message: message)
                }

                if isLoading {
                    ProgressView(statusMessage.isEmpty ? "Asking local model..." : statusMessage)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Ask about your life...", text: $draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .disabled(isLoading)

            if isLoading {
                Button("Cancel", role: .cancel) {
                    cancelSend()
                }
            } else {
                Button {
                    sendTask = Task {
                        await send()
                    }
                } label: {
                    Text("Send")
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .background(.bar)
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

        let retrievedEntries = retrievalEngine.retrieveRelevantEntries(
            for: question,
            from: archiveStore.entries
        )
        let sourceTitles = retrievedEntries.map(\.title)
        let systemPrompt = promptBuilder.buildSystemPrompt(
            personaName: settings.personaName,
            styleNotes: settings.styleNotes,
            memories: retrievedEntries
        )
        let userPrompt = promptBuilder.buildUserPrompt(question: question)

        messages.append(ChatMessage(role: .user, content: question))

        do {
            statusMessage = "Waiting for local model. First response can take a while..."
            let answer = try await chatService.send(
                question: userPrompt,
                systemPrompt: systemPrompt,
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
