import Foundation
import Testing
@testable import Genesis

@MainActor
struct ChatStoreTests {
    @Test
    func historyForAPIExcludesCurrentQuestionAndCapsTurns() {
        let defaults = UserDefaults(suiteName: "ChatStoreTests")!
        defaults.removePersistentDomain(forName: "ChatStoreTests")
        let store = ChatStore(defaults: defaults)

        for index in 0..<5 {
            store.appendUserMessage("question \(index)")
            store.appendAssistantMessage("answer \(index)")
        }

        let history = store.historyForAPI()
        assert(history.count == ChatStore.maxHistoryTurns)
        assert(history.first?.content == "question 1")
        assert(history.last?.content == "answer 4")
    }

    @Test
    func historyUsesBackendTurnShape() {
        let defaults = UserDefaults(suiteName: "ChatStoreTestsRoles")!
        defaults.removePersistentDomain(forName: "ChatStoreTestsRoles")
        let store = ChatStore(defaults: defaults)

        store.appendUserMessage("tell me about your college")
        store.appendAssistantMessage("school answer")

        let history = store.historyForAPI()
        assert(history.count == 2)
        assert(history[0].role == "user")
        assert(history[0].content == "tell me about your college")
        assert(history[1].role == "assistant")
        assert(history[1].content == "school answer")
    }
}
