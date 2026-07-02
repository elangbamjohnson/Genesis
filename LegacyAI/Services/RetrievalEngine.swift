import Foundation

struct RetrievalEngine {
    private let maxResults: Int

    init(maxResults: Int = 4) {
        self.maxResults = maxResults
    }

    func retrieveRelevantEntries(for query: String, from entries: [LifeEntry]) -> [LifeEntry] {
        let coreQueryTerms = tokenize(query)
        let expandedQueryTerms = expandedQueryTerms(for: coreQueryTerms)

        let scoredEntries = entries.compactMap { entry -> (entry: LifeEntry, score: Int)? in
            let score = scoreEntry(
                entry,
                coreQueryTerms: coreQueryTerms,
                expandedQueryTerms: expandedQueryTerms
            )
            guard score > 0 else { return nil }
            return (entry, score)
        }

        return scoredEntries
            .sorted {
                if $0.score == $1.score {
                    return $0.entry.date > $1.entry.date
                }

                return $0.score > $1.score
            }
            .prefix(maxResults)
            .map(\.entry)
    }
    
    /// For broad, open-ended questions ("tell me about yourself") rather than
    /// a specific fact lookup — pulls a diverse cross-section: the most recent
    /// entry from each distinct category, rather than trying to keyword-match.
    func retrieveOverviewEntries(from entries: [LifeEntry], maxResults: Int = 6) -> [LifeEntry] {
        guard !entries.isEmpty else { return [] }

        var seenCategories = Set<LifeEntry.Category>()
        var overview: [LifeEntry] = []

        for entry in entries.sorted(by: { $0.date > $1.date }) {
            guard !seenCategories.contains(entry.category) else { continue }
            seenCategories.insert(entry.category)
            overview.append(entry)
            if overview.count >= maxResults { break }
        }

        return overview
    }

    private func scoreEntry(
        _ entry: LifeEntry,
        coreQueryTerms: [String],
        expandedQueryTerms: [String]
    ) -> Int {
        guard !coreQueryTerms.isEmpty else { return 0 }

        let searchableText = [
            entry.title,
            entry.content,
            entry.category.rawValue,
            entry.tags.joined(separator: " ")
        ].joined(separator: " ")

        let entryTerms = tokenize(searchableText)
        let frequencies = Dictionary(entryTerms.map { ($0, 1) }, uniquingKeysWith: +)

        let directScore = coreQueryTerms.reduce(0) { partialResult, term in
            partialResult + (frequencies[term] ?? 0)
        }
        let expandedOnlyTerms = expandedQueryTerms.filter { !coreQueryTerms.contains($0) }
        let expandedScore = expandedOnlyTerms.reduce(0) { partialResult, term in
            partialResult + min(frequencies[term] ?? 0, 1)
        }
        let isBroadChildhoodQuery = coreQueryTerms.contains("childhood")
        let childhoodBoost = isBroadChildhoodQuery && entry.category == .childhood ? 15 : 0
        let canUseRelatedOnlyMatch = isBroadChildhoodQuery
            && entry.category == .childhood
            && expandedScore > 0

        guard directScore > 0 || childhoodBoost > 0 || canUseRelatedOnlyMatch else {
            return 0
        }

        return directScore * 10 + childhoodBoost + expandedScore
    }

    private func expandedQueryTerms(for terms: [String]) -> [String] {
        var expandedTerms = Set(terms)

        for term in terms {
            for relatedTerm in Self.relatedTerms[term, default: []] {
                expandedTerms.insert(relatedTerm)
            }
        }

        return Array(expandedTerms)
    }

    private func tokenize(_ text: String) -> [String] {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map(normalizedToken)
            .filter { token in
                token.count > 2 && !Self.stopwords.contains(token)
            }
    }

    private func normalizedToken(_ token: String) -> String {
        switch token {
        case "grew", "growing", "grown":
            return "grow"
        default:
            if token.hasSuffix("ies"), token.count > 4 {
                return String(token.dropLast(3)) + "y"
            }

            if token.hasSuffix("s"), token.count > 4 {
                return String(token.dropLast())
            }

            return token
        }
    }

    private static let relatedTerms: [String: Set<String>] = [
        "childhood": ["child", "kid", "young", "small", "school", "grow", "home"],
        "child": ["childhood", "kid", "young", "small", "school", "grow"],
        "kid": ["childhood", "child", "young", "small", "school", "grow"],
        "young": ["childhood", "child", "kid", "small", "school", "grow"],
        "school": ["childhood", "child", "kid", "young"],
        "grow": ["childhood", "child", "kid", "young", "home"]
    ]

    private static let stopwords: Set<String> = [
        "about", "after", "again", "also", "and", "are", "because", "but",
        "can", "could", "did", "does", "for", "from", "had", "has", "have",
        "her", "him", "his", "how", "into", "its", "just", "like", "not",
        "me", "memory", "my", "our", "recall", "recalled", "recollect",
        "remember", "she", "should", "story", "tell", "that", "the",
        "their", "them", "then", "there", "these", "they", "this", "was",
        "were", "what", "when", "where", "which", "who", "why", "with",
        "would", "you", "your"
    ]
}
