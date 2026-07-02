import Foundation

struct LifeEntry: Identifiable, Codable, Equatable {
    enum Category: String, CaseIterable, Codable, Identifiable {
        case childhood = "Childhood"
        case family = "Family"
        case career = "Career"
        case values = "Values"
        case advice = "Advice"
        case relationships = "Relationships"
        case imported = "Imported"
        case other = "Other"

        var id: String { rawValue }
    }

    var id: UUID
    var title: String
    var content: String
    var category: Category
    var tags: [String]
    var date: Date

    init(
        id: UUID = UUID(),
        title: String,
        content: String,
        category: Category,
        tags: [String] = [],
        date: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.category = category
        self.tags = tags
        self.date = date
    }
}
