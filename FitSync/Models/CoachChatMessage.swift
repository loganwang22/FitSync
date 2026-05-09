import Foundation

/// A single message in a coach chat session. Mirrors both Claude and the
/// OpenAI-compatible schemas: each message has a role and some content, plus
/// optional tool invocations.
struct CoachChatMessage: Identifiable, Equatable, Hashable, Codable {
    let id: UUID
    let role: Role
    var text: String
    var toolCalls: [ToolCall]
    var toolResults: [ToolResult]
    var isStreaming: Bool
    /// Provider-specific reasoning / thinking content. Kimi's thinking model
    /// requires this to be echoed back alongside tool-call assistant messages.
    var reasoningContent: String?

    enum Role: String, Codable {
        case user
        case assistant
        case system
        case tool
    }

    struct ToolCall: Equatable, Hashable, Identifiable, Codable {
        let id: String
        let name: String
        let arguments: String // JSON string
    }

    struct ToolResult: Equatable, Hashable, Identifiable, Codable {
        let id: String // matches the tool_call id
        let name: String
        let content: String
    }

    init(
        role: Role,
        text: String = "",
        toolCalls: [ToolCall] = [],
        toolResults: [ToolResult] = [],
        isStreaming: Bool = false,
        reasoningContent: String? = nil
    ) {
        self.id = UUID()
        self.role = role
        self.text = text
        self.toolCalls = toolCalls
        self.toolResults = toolResults
        self.isStreaming = isStreaming
        self.reasoningContent = reasoningContent
    }
}
