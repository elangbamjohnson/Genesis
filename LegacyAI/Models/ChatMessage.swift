import Foundation

struct ChatMessage: Identifiable, Codable, Equatable {
    enum Role: String, Codable {
        case user
        case assistant
        case system
    }

    var id: UUID
    var role: Role
    var content: String
    var timestamp: Date
    var sourceEntryTitles: [String]

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        timestamp: Date = Date(),
        sourceEntryTitles: [String] = []
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.sourceEntryTitles = sourceEntryTitles
    }
}
