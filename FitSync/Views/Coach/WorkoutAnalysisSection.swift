import SwiftUI

struct WorkoutAnalysisSection: View {
    let workout: Workout
    let repository: WorkoutRepository
    @Environment(CoachTaskManager.self) private var coachTaskManager
    @State private var analysis: CoachAnalysis?
    @State private var followUps: [FollowUp] = []
    @State private var followUpInput: String = ""
    @State private var isAsking = false
    @State private var errorMessage: String?
    @State private var showSettingsSheet = false
    @FocusState private var followUpFocused: Bool

    struct FollowUp: Identifiable {
        let id = UUID()
        let question: String
        var answer: String?
    }

    private var isEnhancing: Bool {
        coachTaskManager.isEnhancing(workout.healthKitUUID)
    }

    private var hasAPIKey: Bool {
        AICoachService.hasAPIKey
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.accentColor)
                Text("AI Coach")
                    .font(.headline)
                Spacer()
                if isEnhancing {
                    ProgressView().controlSize(.small)
                }
            }

            if !hasAPIKey {
                noAPIKeyState
            } else if let analysis {
                analysisContent(analysis)
            } else if isEnhancing {
                Text("Analyzing workout…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                generateButton
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task { await loadCached() }
        .onChange(of: coachTaskManager.inProgress) { old, new in
            let uuid = workout.healthKitUUID
            if old.contains(uuid) && !new.contains(uuid) {
                if let updated = workout.cachedCoachAnalysis {
                    analysis = updated
                }
                errorMessage = coachTaskManager.lastError(for: uuid)
            }
        }
        .sheet(isPresented: $showSettingsSheet) {
            CoachSettingsSheet()
        }
    }

    // MARK: - States

    private var noAPIKeyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Set up an API key to get AI analysis of this workout and ask follow-up questions.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                showSettingsSheet = true
            } label: {
                Label("Configure AI Coach", systemImage: "gearshape")
                    .font(.subheadline)
            }
        }
    }

    private var generateButton: some View {
        Button {
            enhanceWithAI()
        } label: {
            Label("Generate AI Analysis", systemImage: "brain")
                .font(.subheadline)
        }
        .disabled(isEnhancing)
    }

    @ViewBuilder
    private func analysisContent(_ analysis: CoachAnalysis) -> some View {
        if !analysis.observations.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(analysis.observations) { obs in
                    observationRow(obs)
                }
            }
        }

        if !analysis.recommendations.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                ForEach(analysis.recommendations) { rec in
                    recommendationRow(rec)
                }
            }
        }

        if !analysis.suggestedWorkouts.isEmpty {
            Divider()
            Text("Suggested Next")
                .font(.subheadline.bold())
            ForEach(analysis.suggestedWorkouts) { suggestion in
                suggestedRow(suggestion)
            }
        }

        Divider()
        HStack {
            Button {
                enhanceWithAI()
            } label: {
                Label("Regenerate", systemImage: "arrow.clockwise")
                    .font(.caption)
            }
            .disabled(isEnhancing)
            Spacer()
            Text("Generated \(analysis.generatedDate.shortFormatted)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }

        Divider()
        followUpSection
    }

    // MARK: - Loading

    @MainActor
    private func loadCached() async {
        errorMessage = coachTaskManager.lastError(for: workout.healthKitUUID)
        if let cached = workout.cachedCoachAnalysis {
            analysis = cached
        }
    }

    private func enhanceWithAI() {
        errorMessage = nil
        let recentWorkouts = repository.fetchWorkouts(limit: 20)
        let goal: TrainingGoal? = {
            guard let raw = UserDefaults.standard.object(forKey: "trainingGoalRawValue") as? Int else { return nil }
            return TrainingGoal(rawValue: raw)
        }()

        coachTaskManager.enhance(
            workout: workout,
            recentWorkouts: recentWorkouts,
            goal: goal
        )
    }

    // MARK: - Follow-up Q&A

    private var followUpSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "bubble.left.and.bubble.right")
                    .foregroundStyle(Color.accentColor)
                Text("Ask more")
                    .font(.subheadline.bold())
                Spacer()
            }

            ForEach(followUps) { qa in
                VStack(alignment: .leading, spacing: 6) {
                    Text(qa.question)
                        .font(.subheadline)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    if let answer = qa.answer {
                        Text(answer)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.systemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Thinking…").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(10)
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("Ask a follow-up question…", text: $followUpInput, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .focused($followUpFocused)
                    .disabled(isAsking)
                    .onSubmit { Task { await submitFollowUp() } }

                Button {
                    Task { await submitFollowUp() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(canSubmit ? Color.accentColor : Color.secondary)
                }
                .disabled(!canSubmit)
            }
        }
    }

    private var canSubmit: Bool {
        !isAsking && !followUpInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @MainActor
    private func submitFollowUp() async {
        let question = followUpInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isAsking, let priorAnalysis = analysis else { return }

        followUpInput = ""
        followUpFocused = false
        errorMessage = nil
        isAsking = true

        let entry = FollowUp(question: question, answer: nil)
        followUps.append(entry)
        let entryID = entry.id

        let recentWorkouts = repository.fetchWorkouts(limit: 20)
        let goal: TrainingGoal? = {
            guard let raw = UserDefaults.standard.object(forKey: "trainingGoalRawValue") as? Int else { return nil }
            return TrainingGoal(rawValue: raw)
        }()

        let priorQAs: [(question: String, answer: String)] = followUps
            .dropLast()
            .compactMap { qa in qa.answer.map { (qa.question, $0) } }

        do {
            let answer = try await AICoachService.shared.askFollowUp(
                workout: workout,
                priorAnalysis: priorAnalysis,
                priorQAs: priorQAs,
                newQuestion: question,
                recentWorkouts: recentWorkouts,
                goal: goal
            )
            if let idx = followUps.firstIndex(where: { $0.id == entryID }) {
                followUps[idx] = FollowUp(question: question, answer: answer.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        } catch {
            followUps.removeAll { $0.id == entryID }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isAsking = false
    }

    // MARK: - Row Views

    private func observationRow(_ obs: CoachAnalysis.Observation) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(sentimentColor(obs.sentiment))
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 2) {
                Text(obs.title)
                    .font(.subheadline.bold())
                Text(obs.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func recommendationRow(_ rec: CoachAnalysis.Recommendation) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: recIcon(rec.type))
                .font(.caption)
                .foregroundStyle(Color.accentColor)
                .frame(width: 16)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(rec.title)
                    .font(.subheadline.bold())
                Text(rec.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func suggestedRow(_ s: CoachAnalysis.SuggestedWorkout) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(intensityColor(s.intensity))
                .frame(width: 8, height: 8)
            Text(s.name)
                .font(.subheadline)
            Spacer()
            if let mins = s.durationMinutes {
                Text("\(mins)m")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(s.intensity.rawValue.capitalized)
                .font(.caption2.bold())
                .foregroundStyle(intensityColor(s.intensity))
        }
    }

    // MARK: - Helpers

    private func sentimentColor(_ s: CoachAnalysis.Observation.Sentiment) -> Color {
        switch s {
        case .positive: .green
        case .neutral: .yellow
        case .caution: .orange
        }
    }

    private func recIcon(_ type: CoachAnalysis.Recommendation.RecommendationType) -> String {
        switch type {
        case .nextWorkout: "arrow.right.circle"
        case .technique: "figure.run"
        case .recovery: "bed.double"
        case .goalProgress: "trophy"
        }
    }

    private func intensityColor(_ intensity: CoachAnalysis.SuggestedWorkout.Intensity) -> Color {
        switch intensity {
        case .easy: .green
        case .moderate: .orange
        case .hard: .red
        }
    }
}
