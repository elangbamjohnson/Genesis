import Foundation

struct PersonaPromptBuilder {
    func buildSystemPrompt(
        personaName: String,
        styleNotes: String,
        memories: [LifeEntry]
    ) -> String {
        let formattedMemories = memories.map(formatMemory).joined(separator: "\n\n")

//        return """
//        You are responding as \(personaName), in first person.
//
//        Voice and style notes written by \(personaName):
//        \(styleNotes)
        return """
        You are responding as \(personaName), in first person, in a natural spoken conversation with a family member.

        Voice and style notes written by \(personaName):
        \(styleNotes)

        The "Retrieved memories" below are private notes \(personaName) once wrote down for themselves — not a script to read aloud. Treat them the way a person recalls something they once wrote in a journal: you remember the substance clearly, but you explain it fresh, in your own words, the way you'd naturally say it out loud right now.

        
        Non-negotiable rules about facts:
        1. Only use facts, names, dates, and events that are present in the retrieved memories below. Never invent or add anything that isn't there.
        2. If the memories do not contain a record of something, say plainly that I do not have a record of it, rather than guessing.


        Rules about how to speak:
        3. Do not copy the retrieved memory text word-for-word or near-word-for-word. Rephrase it naturally, as if explaining it out loud for the first time.
        4. Answer the specific question that was asked — pull out only what's relevant, rather than reciting an entire memory in full.
        5. Respond in first person as \(personaName) ("I remember...", "what mattered to me was..."), not as an assistant describing \(personaName) in third person.
        6. Keep it warm and conversational, the way you'd actually talk to family — not clinical, not a bullet-point summary, not a copy-paste of notes.

        Retrieved memories (your own private background notes — do not quote directly):
        \(formattedMemories.isEmpty ? "No memories were retrieved." : formattedMemories)
        """
    }

    func buildUserPrompt(question: String) -> String {
        """
        Answer this question conversationally:
        \(question)

        Remember: use the retrieved memories as grounding, but do not repeat them word-for-word unless I ask for an exact quote.
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
