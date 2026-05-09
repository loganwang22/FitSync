import SwiftUI

struct CoachChatView: View {
    @State private var viewModel: CoachChatViewModel
    @State private var kimiThinking: Bool = AICoachService.kimiThinkingEnabled
    let goal: TrainingGoal?
    @FocusState private var inputFocused: Bool

    init(
        repository: WorkoutRepository,
        healthKit: HealthKitService,
        goal: TrainingGoal?,
        session: CoachChatSession? = nil
    ) {
        _viewModel = State(wrappedValue: CoachChatViewModel(
            repository: repository,
            healthKit: healthKit,
            session: session
        ))
        self.goal = goal
    }

    var body: some View {
        VStack(spacing: 0) {
            messagesList
            inputBar
        }
        .navigationTitle("AI Coach Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 8) {
                    if AICoachService.selectedProvider == .kimi {
                        Menu {
                            Toggle("Thinking Mode", isOn: $kimiThinking)
                                .onChange(of: kimiThinking) { _, val in
                                    AICoachService.kimiThinkingEnabled = val
                                }
                            Text(kimiThinking
                                 ? "Uses kimi-k2.6 — slower, deeper reasoning"
                                 : "Uses kimi-k2-turbo — faster responses")
                        } label: {
                            Image(systemName: kimiThinking ? "brain.head.profile" : "bolt.fill")
                                .font(.caption)
                        }
                    }
                    if !viewModel.messages.isEmpty {
                        Button("Clear") { viewModel.clearConversation() }
                            .font(.caption)
                    }
                }
            }
        }
    }

    // MARK: - Messages

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if viewModel.displayedMessages.isEmpty {
                        emptyState
                    }

                    ForEach(viewModel.displayedMessages) { msg in
                        messageBubble(msg)
                            .id(msg.id)
                    }

                    if viewModel.isSending {
                        thinkingIndicator
                            .id("thinking")
                    }

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                withAnimation {
                    if viewModel.isSending {
                        proxy.scrollTo("thinking", anchor: .bottom)
                    } else if let last = viewModel.displayedMessages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: viewModel.isSending) { _, sending in
                if sending {
                    withAnimation { proxy.scrollTo("thinking", anchor: .bottom) }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ask your AI coach")
                .font(.title3.bold())
            Text("Try one of these:")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                suggestionChip("How did my running go last week?")
                suggestionChip("Compare my pace this month vs last month")
                suggestionChip("Is my resting heart rate trending down?")
                suggestionChip("What should my next workout be?")
            }
        }
        .padding(.top, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func suggestionChip(_ text: String) -> some View {
        Button {
            viewModel.input = text
            inputFocused = true
        } label: {
            HStack {
                Text(text)
                    .font(.subheadline)
                    .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: "arrow.up.left")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(10)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func messageBubble(_ msg: CoachChatMessage) -> some View {
        HStack(alignment: .top) {
            if msg.role == .user { Spacer(minLength: 40) }

            Text(msg.text)
                .font(.body)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(bubbleBackground(for: msg.role))
                .foregroundStyle(bubbleForeground(for: msg.role))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .frame(maxWidth: .infinity, alignment: bubbleAlignment(for: msg.role))

            if msg.role == .assistant { Spacer(minLength: 40) }
        }
    }

    private var thinkingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(currentStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var currentStatus: String {
        guard let tool = viewModel.currentToolName else { return "Thinking…" }
        switch tool {
        case "get_current_date":     return "Checking the date…"
        case "list_workouts":        return "Looking up your workouts…"
        case "get_workout_detail":   return "Reading workout details…"
        case "summarize_period":     return "Summarizing your training…"
        case "get_health_trend":     return "Checking health trends…"
        case "get_training_goal":    return "Reviewing your goal…"
        default:                     return "Checking your data…"
        }
    }

    // MARK: - Input

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask the coach…", text: $viewModel.input, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
                .focused($inputFocused)
                .disabled(viewModel.isSending)
                .onSubmit { Task { await viewModel.send() } }

            Button {
                Task { await viewModel.send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title)
                    .foregroundStyle(viewModel.canSend ? Color.accentColor : Color.secondary)
            }
            .disabled(!viewModel.canSend)
        }
        .padding()
        .background(.thinBackground)
    }

    // MARK: - Bubble styling

    private func bubbleBackground(for role: CoachChatMessage.Role) -> Color {
        switch role {
        case .user: return Color.accentColor
        case .assistant: return Color(.systemGray6)
        default: return Color.clear
        }
    }

    private func bubbleForeground(for role: CoachChatMessage.Role) -> Color {
        switch role {
        case .user: return Color.white
        default: return Color.primary
        }
    }

    private func bubbleAlignment(for role: CoachChatMessage.Role) -> Alignment {
        role == .user ? .trailing : .leading
    }
}

private extension ShapeStyle where Self == Material {
    static var thinBackground: Material { .bar }
}
