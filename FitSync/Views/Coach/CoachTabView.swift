import SwiftUI

struct CoachTabView: View {
    @State var viewModel: CoachViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let goal = viewModel.goal {
                        goalBadge(goal)
                        weeklyLoadSection(goal)

                        // Training plan
                        if let plan = viewModel.trainingPlan {
                            // Current week plan
                            if let currentWeek = plan.weeklyBlocks.first {
                                WeeklyPlanSection(block: currentWeek, isCurrentWeek: true)
                            }

                            // Upcoming weeks
                            ForEach(plan.weeklyBlocks.dropFirst()) { block in
                                WeeklyPlanSection(block: block, isCurrentWeek: false)
                            }

                            // Monthly milestones
                            if !plan.monthlyMilestones.isEmpty {
                                MonthlyMilestonesSection(milestones: plan.monthlyMilestones)
                            }
                        }
                    } else {
                        emptyGoalState
                    }

                    if !viewModel.suggestedWorkouts.isEmpty {
                        upNextSection
                    }

                    if !viewModel.recentInsights.isEmpty {
                        recentInsightsSection
                    }
                }
                .padding()
            }
            .navigationTitle("Coach")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.showSettingsSheet = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        viewModel.showGoalSheet = true
                    } label: {
                        Image(systemName: "target")
                    }
                }
            }
            .sheet(isPresented: $viewModel.showGoalSheet) {
                viewModel.load()
            } content: {
                GoalSelectionSheet(selectedGoal: Binding(
                    get: { viewModel.goal },
                    set: { viewModel.goal = $0 }
                ))
            }
            .sheet(isPresented: $viewModel.showSettingsSheet) {
                CoachSettingsSheet()
            }
            .task { viewModel.load() }
        }
    }

    // MARK: - Goal Badge

    private func goalBadge(_ goal: TrainingGoal) -> some View {
        HStack(spacing: 12) {
            Image(systemName: goal.systemImage)
                .font(.title2.bold())
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(goal.label)
                    .font(.headline)
                Text(goal.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Change") {
                viewModel.showGoalSheet = true
            }
            .font(.caption)
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Weekly Load

    private func weeklyLoadSection(_ goal: TrainingGoal) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This Week")
                .font(.headline)

            let targets = goal.weeklyTargets

            progressRow(
                label: "Sessions",
                value: Double(viewModel.sessionsThisWeek),
                target: Double(targets.sessionsPerWeek),
                format: { "\(Int($0))/\(targets.sessionsPerWeek)" }
            )

            if targets.runKm > 0 {
                progressRow(
                    label: "Running",
                    value: viewModel.runKmThisWeek,
                    target: targets.runKm,
                    format: { String(format: "%.1f/%.0f km", $0, targets.runKm) }
                )
            }

            if targets.cycleKm > 0 {
                progressRow(
                    label: "Cycling",
                    value: viewModel.cycleKmThisWeek,
                    target: targets.cycleKm,
                    format: { String(format: "%.0f/%.0f km", $0, targets.cycleKm) }
                )
            }

            if targets.swimM > 0 {
                progressRow(
                    label: "Swimming",
                    value: viewModel.swimMThisWeek,
                    target: targets.swimM,
                    format: { String(format: "%.0f/%.0f m", $0, targets.swimM) }
                )
            }

            HStack {
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
                Text(String(format: "%.0f min total", viewModel.totalDurationMinThisWeek))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func progressRow(
        label: String,
        value: Double,
        target: Double,
        format: (Double) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.subheadline)
                Spacer()
                Text(format(value))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(value, target), total: target)
                .tint(value >= target ? .green : .blue)
        }
    }

    // MARK: - Up Next

    private var upNextSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Up Next")
                .font(.headline)

            ForEach(viewModel.suggestedWorkouts) { suggestion in
                HStack(spacing: 12) {
                    Circle()
                        .fill(intensityColor(suggestion.intensity))
                        .frame(width: 8, height: 8)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.name)
                            .font(.subheadline.bold())
                        Text(suggestion.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if let mins = suggestion.durationMinutes {
                        Text("\(mins)m")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Recent Insights

    private var recentInsightsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Insights")
                .font(.headline)

            ForEach(viewModel.recentInsights, id: \.workout.healthKitUUID) { item in
                HStack(spacing: 12) {
                    WorkoutIcon(type: item.workout.type, size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.workout.type.label)
                            .font(.subheadline.bold())
                        Text(item.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(item.workout.startDate.shortFormatted)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Empty State

    private var emptyGoalState: some View {
        VStack(spacing: 16) {
            Image(systemName: "target")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Set a Training Goal")
                .font(.title3.bold())
            Text("Choose a goal to get personalized training insights and workout suggestions.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                viewModel.showGoalSheet = true
            } label: {
                Text("Choose Goal")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 40)
    }

    private func intensityColor(_ intensity: CoachAnalysis.SuggestedWorkout.Intensity) -> Color {
        switch intensity {
        case .easy: return .green
        case .moderate: return .orange
        case .hard: return .red
        }
    }
}
