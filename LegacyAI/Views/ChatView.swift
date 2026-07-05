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

    private let backendClient = BackendClient()

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
            .navigationTitle("Project Genesis")
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
        statusMessage = "Asking Genesis..."
        defer {
            isLoading = false
            statusMessage = ""
            sendTask = nil
        }

        // Build history BEFORE appending the new question -- the backend
        // treats `question` as the current turn and `history` as everything
        // that came before it.
        let history = messages.map {
            BackendClient.ChatTurn(role: $0.role.rawValue, content: $0.content)
        }

        messages.append(ChatMessage(role: .user, content: question))

        do {
            let reply = try await backendClient.sendChat(
                question: question,
                history: history,
                baseURL: settings.backendBaseURL
            )
            messages.append(
                ChatMessage(
                    role: .assistant,
                    content: reply.answer,
                    sourceEntryTitles: reply.sourceTitles
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
