import SwiftUI

struct WorkoutAnalysisSection: View {
    let workout: Workout
    let repository: WorkoutRepository
    @State private var analysis: CoachAnalysis?
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.accentColor)
                Text("Coach")
                    .font(.headline)
                Spacer()
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let analysis {
                // Observations
                if !analysis.observations.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(analysis.observations) { obs in
                            observationRow(obs)
                        }
                    }
                }

                // Recommendations
                if !analysis.recommendations.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(analysis.recommendations) { rec in
                            recommendationRow(rec)
                        }
                    }
                }

                // Suggested next workouts
                if !analysis.suggestedWorkouts.isEmpty {
                    Divider()
                    Text("Suggested Next")
                        .font(.subheadline.bold())
                    ForEach(analysis.suggestedWorkouts) { suggestion in
                        suggestedRow(suggestion)
                    }
                }

                // AI enhancement button
                if analysis.source == .onDevice && AICoachService.hasAPIKey {
                    Divider()
                    Button {
                        Task { await enhanceWithAI() }
                    } label: {
                        Label("Enhance with AI", systemImage: "brain")
                            .font(.subheadline)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task { await loadAnalysis() }
    }

    // MARK: - Loading

    @MainActor
    private func loadAnalysis() async {
        // Check cache
        if let cached = workout.cachedCoachAnalysis,
           let cacheDate = workout.cachedCoachAnalysisDate,
           cacheDate.timeIntervalSinceNow > -86400 { // 24h
            analysis = cached
            return
        }

        isLoading = true
        let recentWorkouts = repository.fetchWorkouts(limit: 20)
        let goal: TrainingGoal? = {
            guard let raw = UserDefaults.standard.object(forKey: "trainingGoalRawValue") as? Int else { return nil }
            return TrainingGoal(rawValue: raw)
        }()

        let analyzer = WorkoutAnalyzer()
        let result = analyzer.analyze(
            workout: workout,
            recentWorkouts: recentWorkouts,
            goal: goal
        )

        workout.cachedCoachAnalysis = result
        workout.cachedCoachAnalysisDate = .now
        analysis = result
        isLoading = false
    }

    @MainActor
    private func enhanceWithAI() async {
        guard let baseAnalysis = analysis else { return }
        isLoading = true

        let recentWorkouts = repository.fetchWorkouts(limit: 20)
        let goal: TrainingGoal? = {
            guard let raw = UserDefaults.standard.object(forKey: "trainingGoalRawValue") as? Int else { return nil }
            return TrainingGoal(rawValue: raw)
        }()

        do {
            let enhanced = try await AICoachService.shared.enhance(
                workout: workout,
                baseAnalysis: baseAnalysis,
                recentWorkouts: recentWorkouts,
                goal: goal
            )
            workout.cachedCoachAnalysis = enhanced
            workout.cachedCoachAnalysisDate = .now
            analysis = enhanced
        } catch {
            // Keep on-device analysis on failure
        }
        isLoading = false
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
