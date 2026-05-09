import Foundation

struct CoachChatSession: Identifiable, Equatable, Hashable, Codable {
    let id: UUID
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var messages: [CoachChatMessage]

    init(
        id: UUID = UUID(),
        title: String = "New chat",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        messages: [CoachChatMessage] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
    }

    var preview: String {
        if let firstAssistant = messages.first(where: { $0.role == .assistant && !$0.text.isEmpty }) {
            return firstAssistant.text
        }
        if let firstUser = messages.first(where: { $0.role == .user }) {
            return firstUser.text
        }
        return ""
    }

    static func derivedTitle(from messages: [CoachChatMessage]) -> String {
        guard let first = messages.first(where: { $0.role == .user && !$0.text.isEmpty })?.text else {
            return "New chat"
        }
        let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 60 { return trimmed }
        let prefix = trimmed.prefix(60)
        return prefix.trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}
