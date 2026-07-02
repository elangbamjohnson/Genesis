import Foundation
import Testing
@testable import Genesis

struct GenesisTests {
    @MainActor
    @Test func retrievesChildhoodEntriesByCategory() {
        let childhoodEntry = LifeEntry(
            title: "A lane near home",
            content: "I remember running home after school with friends.",
            category: .childhood,
            date: Date(timeIntervalSince1970: 100)
        )
        let careerEntry = LifeEntry(
            title: "First office",
            content: "I learned how to work with a team.",
            category: .career,
            date: Date(timeIntervalSince1970: 200)
        )

        let results = RetrievalEngine().retrieveRelevantEntries(
            for: "Tell me about my childhood memories",
            from: [careerEntry, childhoodEntry]
        )

        #expect(results.first?.id == childhoodEntry.id)
    }

    @MainActor
    @Test func retrievesChildhoodEntriesByRelatedWording() {
        let entry = LifeEntry(
            title: "Growing up near the river",
            content: "When I was young, evenings by the river felt peaceful.",
            category: .childhood
        )

        let results = RetrievalEngine().retrieveRelevantEntries(
            for: "What do you remember from childhood?",
            from: [entry]
        )

        #expect(results.map(\.id) == [entry.id])
    }

    @MainActor
    @Test func returnsNoEntriesWhenNothingMatches() {
        let entry = LifeEntry(
            title: "Work lesson",
            content: "I learned to prepare carefully before meetings.",
            category: .career
        )

        let results = RetrievalEngine().retrieveRelevantEntries(
            for: "What did I love eating as a child?",
            from: [entry]
        )

        #expect(results.isEmpty)
    }

    @MainActor
    @Test func retrievesDirectSchoolMemory() {
        let schoolEntry = LifeEntry(
            title: "School assembly",
            content: "I remember standing in the school assembly line on rainy mornings.",
            category: .childhood
        )
        let unrelatedEntry = LifeEntry(
            title: "Young days at home",
            content: "When I was young, evenings at home were quiet.",
            category: .childhood
        )

        let results = RetrievalEngine().retrieveRelevantEntries(
            for: "Tell me about your school memory",
            from: [unrelatedEntry, schoolEntry]
        )

        #expect(results.first?.id == schoolEntry.id)
    }

    @MainActor
    @Test func doesNotUseBroadChildhoodMatchForSpecificSchoolQuestion() {
        let unrelatedEntry = LifeEntry(
            title: "Young days at home",
            content: "When I was young, evenings at home were quiet.",
            category: .childhood
        )

        let results = RetrievalEngine().retrieveRelevantEntries(
            for: "Tell me about your school memory",
            from: [unrelatedEntry]
        )

        #expect(results.isEmpty)
    }

    @Test func classifiesGreetingsAsSmallTalk() {
        #expect(ConversationIntentClassifier.classify("hi") == .smallTalk)
        #expect(ConversationIntentClassifier.classify("Hello!") == .smallTalk)
        #expect(ConversationIntentClassifier.classify("good morning") == .smallTalk)
    }

    @Test func classifiesHiGenesisAsSmallTalk() {
        #expect(ConversationIntentClassifier.classify("hi genesis") == .smallTalk)
        #expect(ConversationIntentClassifier.classify("hey there") == .smallTalk)
    }

    @Test func classifiesMemoryQuestionsAsInformationRequest() {
        #expect(
            ConversationIntentClassifier.classify("tell me about my childhood") == .informationRequest
        )
        #expect(
            ConversationIntentClassifier.classify("what school did I attend") == .informationRequest
        )
    }

    @Test func classifiesEmptyStringAsSmallTalk() {
        #expect(ConversationIntentClassifier.classify("   ") == .smallTalk)
    }
}
