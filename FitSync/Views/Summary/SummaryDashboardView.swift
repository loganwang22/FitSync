import SwiftUI

struct SummaryDashboardView: View {
    @State var viewModel: SummaryViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Period Picker
                    Picker("Period", selection: Binding(
                        get: { viewModel.selectedRange },
                        set: { viewModel.selectRange($0) }
                    )) {
                        ForEach(DateRange.allCases) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    // Period Navigation
                    HStack {
                        Button { viewModel.goBack() } label: {
                            Image(systemName: "chevron.left")
                                .font(.title3.bold())
                        }

                        Spacer()
                        Text(viewModel.periodLabel)
                            .font(.subheadline.bold())
                        Spacer()

                        Button { viewModel.goForward() } label: {
                            Image(systemName: "chevron.right")
                                .font(.title3.bold())
                        }
                        .disabled(!viewModel.canGoForward)
                    }
                    .padding(.horizontal, 24)

                    // Overall Summary
                    if let summary = viewModel.overallSummary, summary.workoutCount > 0 {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Overview")
                                .font(.headline)

                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible()),
                            ], spacing: 12) {
                                MetricCard(title: "Workouts", value: "\(summary.workoutCount)", icon: "flame.fill", color: .red)
                                MetricCard(title: "Distance", value: summary.formattedDistance, icon: "arrow.left.and.right", color: .blue)
                                MetricCard(title: "Duration", value: summary.formattedDuration, icon: "clock.fill", color: .green)
                                MetricCard(title: "Calories", value: summary.formattedCalories, icon: "bolt.fill", color: .orange)
                                if summary.hasElevation {
                                    MetricCard(title: "Ascent", value: summary.formattedElevationGain, icon: "arrow.up.right", color: .purple)
                                }
                            }
                        }
                        .padding(.horizontal)
                    } else {
                        EmptyStateView(
                            icon: "chart.bar",
                            title: "No Data",
                            message: "No workouts found for this period."
                        )
                    }

                    // Per-sport breakdown
                    if !viewModel.sportSummaries.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("By Sport")
                                .font(.headline)
                                .padding(.horizontal)

                            ForEach(viewModel.sportSummaries) { summary in
                                if let type = summary.workoutType {
                                    NavigationLink(value: SportFilterRoute(
                                        workoutType: type,
                                        range: viewModel.selectedRange,
                                        date: viewModel.selectedDate
                                    )) {
                                        SportSummaryRow(type: type, summary: summary)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Summary")
            .navigationDestination(for: SportFilterRoute.self) { route in
                FilteredWorkoutListView(
                    workoutType: route.workoutType,
                    range: route.range,
                    date: route.date,
                    repository: viewModel.repository
                )
            }
            .navigationDestination(for: Workout.self) { workout in
                WorkoutDetailView(workout: workout, repository: viewModel.repository)
            }
            .onAppear { viewModel.load() }
        }
    }
}

struct SportFilterRoute: Hashable {
    let workoutType: WorkoutType
    let range: DateRange
    let date: Date
}

struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(value)
                .font(.title2.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct SportSummaryRow: View {
    let type: WorkoutType
    let summary: WorkoutSummary

    var body: some View {
        HStack {
            WorkoutIcon(type: type, size: 36)
            VStack(alignment: .leading) {
                Text(type.label)
                    .font(.subheadline.bold())
                Text("\(summary.workoutCount) workouts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(summary.formattedDistance)
                    .font(.subheadline.bold())
                Text(summary.formattedDuration)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if summary.hasElevation {
                    Label(summary.formattedElevationGain, systemImage: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
