import Foundation

struct RetrievalEngine {
    private let maxResults: Int

    init(maxResults: Int = 4) {
        self.maxResults = maxResults
    }

    func retrieveRelevantEntries(for query: String, from entries: [LifeEntry]) -> [LifeEntry] {
        let queryTerms = tokenize(query)

        let scoredEntries = entries.compactMap { entry -> (entry: LifeEntry, score: Int)? in
            let score = scoreEntry(entry, queryTerms: queryTerms)
            guard score > 0 else { return nil }
            return (entry, score)
        }

        if scoredEntries.isEmpty {
            return Array(
                entries
                    .sorted { $0.date > $1.date }
                    .prefix(maxResults)
            )
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

    private func scoreEntry(_ entry: LifeEntry, queryTerms: [String]) -> Int {
        guard !queryTerms.isEmpty else { return 0 }

        let searchableText = [
            entry.title,
            entry.content,
            entry.category.rawValue,
            entry.tags.joined(separator: " ")
        ].joined(separator: " ")

        let entryTerms = tokenize(searchableText)
        let frequencies = Dictionary(entryTerms.map { ($0, 1) }, uniquingKeysWith: +)

        return queryTerms.reduce(0) { partialResult, term in
            partialResult + (frequencies[term] ?? 0)
        }
    }

    private func tokenize(_ text: String) -> [String] {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { token in
                token.count > 2 && !Self.stopwords.contains(token)
            }
    }

    private static let stopwords: Set<String> = [
        "about", "after", "again", "also", "and", "are", "because", "but",
        "can", "could", "did", "does", "for", "from", "had", "has", "have",
        "her", "him", "his", "how", "into", "its", "just", "like", "not",
        "our", "she", "should", "that", "the", "their", "them", "then",
        "there", "these", "they", "this", "was", "were", "what", "when",
        "where", "which", "who", "why", "with", "would", "you", "your"
    ]
}
