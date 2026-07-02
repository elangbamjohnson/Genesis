//
//  ConversationIntentClassifier.swift
//  Genesis
//
//  Created by Johnson Elangbam on 02/07/26.
//

import Foundation

enum ConversationIntent {
    case smallTalk
    case broadOverview
    case informationRequest
}

/// A lightweight, heuristic classifier — no ML, no network call.
/// It decides whether a message is casual conversation (greetings, thanks,
/// check-ins) versus an actual request for a specific fact or memory.
/// This is intentionally simple; if it ever misclassifies something, extend
/// the word lists below rather than rewriting the approach.
enum ConversationIntentClassifier {

    static func classify(_ rawQuestion: String) -> ConversationIntent {
        let normalized = normalize(rawQuestion)
        guard !normalized.isEmpty else { return .smallTalk }

        if exactSmallTalkPhrases.contains(normalized) {
            return .smallTalk
        }
        
        if broadOverviewPhrases.contains(where: { normalized.contains($0) }) {
                return .broadOverview
        }

        let words = normalized.split(separator: " ").map(String.init)

        // Short greetings like "hi genesis", "hey there", "good morning"
        if words.count <= 4, words.allSatisfy({ smallTalkWords.contains($0) || fillerWords.contains($0) }) {
            return .smallTalk
        }

        // General fallback: if nothing meaningful remains once greeting/filler
        // words are stripped out, treat it as small talk rather than a real
        // information request.
        let meaningfulWords = words.filter { !smallTalkWords.contains($0) && !fillerWords.contains($0) }
        return meaningfulWords.isEmpty ? .smallTalk : .informationRequest
    }

    private static func normalize(_ text: String) -> String {
        let lowered = text.lowercased()
        let allowed = CharacterSet.alphanumerics.union(.whitespaces)
        let stripped = String(lowered.unicodeScalars.filter { allowed.contains($0) })
        return stripped
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static let broadOverviewPhrases: Set<String> = [
        "tell me about yourself", "tell me about you",
        "who are you", "introduce yourself",
        "what are you like", "describe yourself",
        "what is your story", "whats your story", "tell me your story",
        "give me an overview", "sum yourself up"
    ]
    
    private static let exactSmallTalkPhrases: Set<String> = [
        "hi", "holla", "hello", "hey", "hiya", "yo", "howdy", "sup",
        "good morning", "good afternoon", "good evening", "good night",
        "morning", "afternoon", "evening",
        "how are you", "hows it going", "how is it going", "whats up", "what is up",
        "bye", "goodbye", "see you", "see you later", "take care",
        "thanks", "thank you", "ok", "okay", "cool", "nice", "great", "awesome", "lol", "haha"
    ]

    private static let smallTalkWords: Set<String> = [
        "hi", "hello", "hey", "hiya", "yo", "howdy", "sup",
        "morning", "afternoon", "evening", "night",
        "bye", "goodbye", "thanks", "thank", "ok", "okay",
        "cool", "nice", "great", "awesome", "good", "holla"
    ]

    private static let fillerWords: Set<String> = [
        "genesis", "there", "you", "youre", "u", "im", "am", "is", "are",
        "how", "whats", "what", "up", "going", "it", "to", "for", "today",
        "again", "buddy", "friend", "mate", "so", "well",
        "doing", "feeling", "been", "lately", "much"
    ]
}
