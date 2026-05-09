import Foundation
import SwiftUI

@MainActor
@Observable
final class CoachChatViewModel {
    let repository: WorkoutRepository
    let healthKit: HealthKitService

    private(set) var session: CoachChatSession
    var messages: [CoachChatMessage] {
        get { session.messages }
        set { session.messages = newValue }
    }
    var input: String = ""
    var isSending: Bool = false
    var currentToolName: String? = nil
    var errorMessage: String? = nil

    private var toolExecutor: CoachToolExecutor

    init(
        repository: WorkoutRepository,
        healthKit: HealthKitService,
        session: CoachChatSession? = nil
    ) {
        self.repository = repository
        self.healthKit = healthKit
        self.session = session ?? CoachChatSession()
        self.toolExecutor = CoachToolExecutor(repository: repository, healthKit: healthKit)
    }

    var canSend: Bool {
        !isSending && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Messages visible to the user: filter out the tool-plumbing turns.
    var displayedMessages: [CoachChatMessage] {
        messages.filter { msg in
            switch msg.role {
            case .user: return true
            case .assistant: return !msg.text.isEmpty
            case .tool, .system: return false
            }
        }
    }

    func send() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }

        input = ""
        errorMessage = nil
        isSending = true
        currentToolName = nil
        defer {
            isSending = false
            currentToolName = nil
        }

        let userMessage = CoachChatMessage(role: .user, text: text)
        messages.append(userMessage)

        toolExecutor.onToolStart = { [weak self] name in self?.currentToolName = name }

        do {
            let newMessages = try await AICoachService.shared.chat(
                history: messages,
                toolExecutor: toolExecutor
            )
            messages.append(contentsOf: newMessages)
            persistSession()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if messages.last?.id == userMessage.id {
                messages.removeLast()
                input = text
            }
        }
    }

    func clearConversation() {
        let oldID = session.id
        session = CoachChatSession()
        errorMessage = nil
        CoachChatStore.shared.delete(id: oldID)
    }

    private func persistSession() {
        session.updatedAt = .now
        session.title = CoachChatSession.derivedTitle(from: session.messages)
        CoachChatStore.shared.save(session)
    }
}
