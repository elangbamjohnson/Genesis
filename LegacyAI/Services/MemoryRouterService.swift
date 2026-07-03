//
//  MemoryRouterService.swift
//  Genesis
//
//  Created by Johnson Elangbam on 02/07/26.
//

import Foundation

struct MemoryRouteDecision {
    let intent: ConversationIntent
    let relevantEntryIDs: [UUID]
}

/// Uses the local LLM itself to judge intent and memory relevance, replacing
/// brittle keyword/phrase-list matching with real language understanding.
/// Falls back to nil (never throws) if the model's response can't be parsed,
/// so callers can gracefully drop back to the keyword-based system.
enum MemoryRouterService {

    static func route(
        question: String,
        entries: [LifeEntry],
        chatService: MLXChatService,
        baseURL: String,
        modelName: String
    ) async -> MemoryRouteDecision? {
        guard !entries.isEmpty else {
            return nil
        }

        let index = entries.map { entry in
            "- id: \(entry.id.uuidString) | title: \(entry.title) | category: \(entry.category.rawValue) | tags: \(entry.tags.joined(separator: ", "))"
        }.joined(separator: "\n")

        let systemPrompt = """
        You are a routing assistant for a personal memory archive. You do not answer the question yourself — you only decide how to handle it.

        Given the message and the index of saved memories below (titles, categories, and tags only), respond with ONLY a JSON object, no other text, no code fences, no explanation, in exactly this shape:

        {"intent": "small_talk" | "specific" | "broad_overview" | "time_query" | "date_query" | "no_match", "relevant_ids": ["id1", "id2"]}

        Rules:
        - "small_talk": greetings, thanks, casual chat — no request for personal information.
        - "specific": a question about one or a few particular facts, stories, or topics. Put only the ids of memories genuinely relevant to what was asked in "relevant_ids".
        - "broad_overview": an open-ended request for a general picture of the person (e.g. "tell me about yourself", "tell me everything you remember", "who are you"). Include a diverse spread of relevant ids across different categories, up to 8.
        - "time_query": the user is asking what the current real-world time is right now, however it's phrased (e.g. "what time is it", "check the time", "got the time?", "current time please"). This is never about a stored memory. Return an empty "relevant_ids" array.
        - "date_query": the user is asking what today's real-world date or day is, however it's phrased. Never about a stored memory. Return an empty "relevant_ids" array.
        - "no_match": a specific question, but nothing in the index relates to it. Return an empty "relevant_ids" array.
        - Only ever include ids that literally appear in the index below. Never invent an id.

        Memory index:
        \(index)
        """

        guard let rawResponse = try? await chatService.send(
            question: question,
            systemPrompt: systemPrompt,
            baseURL: baseURL,
            modelName: modelName,
            maxTokens: 300,
            timeoutInterval: 60,
            performsPreflight: false
        ) else {
            return nil
        }

        guard let decision = parseDecision(from: rawResponse) else {
            return nil
        }

        let validIDs = Set(entries.map(\.id))
        let filteredIDs = decision.relevantEntryIDs.filter { validIDs.contains($0) }
        return MemoryRouteDecision(intent: decision.intent, relevantEntryIDs: filteredIDs)
    }

    static func parseDecision(from raw: String) -> MemoryRouteDecision? {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        struct RawDecision: Decodable {
            let intent: String
            let relevant_ids: [String]
        }

        guard
            let data = cleaned.data(using: .utf8),
            let decoded = try? JSONDecoder().decode(RawDecision.self, from: data)
        else {
            return nil
        }

        let intent: ConversationIntent
        let relevantIDs: [UUID]
        switch decoded.intent {
        case "small_talk":
            intent = .smallTalk
            relevantIDs = []
        case "broad_overview":
            intent = .broadOverview
            relevantIDs = decoded.relevant_ids.compactMap { UUID(uuidString: $0) }
        case "time_query":
            intent = .currentTime
            relevantIDs = []
        case "date_query":
            intent = .currentDate
            relevantIDs = []
        case "no_match":
            intent = .informationRequest
            relevantIDs = []
        default:
            intent = .informationRequest
            relevantIDs = decoded.relevant_ids.compactMap { UUID(uuidString: $0) }
        }

        return MemoryRouteDecision(intent: intent, relevantEntryIDs: relevantIDs)
    }
}
