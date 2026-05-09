import SwiftUI

struct CoachChatHistoryView: View {
    let repository: WorkoutRepository
    let healthKit: HealthKitService
    let goal: TrainingGoal?

    @State private var sessions: [CoachChatSession] = []
    @State private var selectedSession: CoachChatSession?
    @State private var startNewChat: Bool = false

    var body: some View {
        List {
            Section {
                Button {
                    selectedSession = nil
                    startNewChat = true
                } label: {
                    Label("New Chat", systemImage: "plus.bubble.fill")
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)
                }
            }

            if sessions.isEmpty {
                Section {
                    Text("Your past conversations will appear here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Past Conversations") {
                    ForEach(sessions) { session in
                        Button {
                            selectedSession = session
                        } label: {
                            sessionRow(session)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: delete)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("AI Coach")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { reload() }
        .navigationDestination(item: $selectedSession) { session in
            CoachChatView(
                repository: repository,
                healthKit: healthKit,
                goal: goal,
                session: session
            )
            .onDisappear { reload() }
        }
        .navigationDestination(isPresented: $startNewChat) {
            CoachChatView(
                repository: repository,
                healthKit: healthKit,
                goal: goal,
                session: nil
            )
            .onDisappear { reload() }
        }
    }

    private func sessionRow(_ session: CoachChatSession) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            if !session.preview.isEmpty {
                Text(session.preview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text(session.updatedAt.formatted(.relative(presentation: .named)))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private func reload() {
        sessions = CoachChatStore.shared.listSessions()
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            CoachChatStore.shared.delete(id: sessions[index].id)
        }
        sessions.remove(atOffsets: offsets)
    }
}

