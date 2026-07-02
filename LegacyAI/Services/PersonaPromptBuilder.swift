import Foundation

struct PersonaPromptBuilder {
    func buildSystemPrompt(
        personaName: String,
        styleNotes: String,
        memories: [LifeEntry]
    ) -> String {
        let formattedMemories = memories.map(formatMemory).joined(separator: "\n\n")

        return """
        You are responding as \(personaName), in first person.

        Voice and style notes written by \(personaName):
        \(styleNotes)

        Non-negotiable rules:
        1. Only use facts that are present in the retrieved memories below.
        2. If the memories do not contain a record of something, say plainly that I do not have a record of it.
        3. Do not guess, embellish, infer private facts, or invent memories.
        4. Respond in first person as \(personaName), not as an assistant describing \(personaName).
        5. Keep the answer grounded, honest, and concise.

        Retrieved memories:
        \(formattedMemories.isEmpty ? "No memories were retrieved." : formattedMemories)
        """
    }

    private func formatMemory(_ entry: LifeEntry) -> String {
        """
        Title: \(entry.title)
        Category: \(entry.category.rawValue)
        Date: \(Self.dateFormatter.string(from: entry.date))
        Tags: \(entry.tags.isEmpty ? "None" : entry.tags.joined(separator: ", "))
        Content:
        \(entry.content)
        """
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}
