import SwiftUI

struct FilteredWorkoutListView: View {
    let workoutType: WorkoutType
    let range: DateRange
    let date: Date
    let repository: WorkoutRepository

    private var workouts: [Workout] {
        repository.fetchWorkouts(in: range, from: date, type: workoutType)
    }

    private var title: String {
        workoutType.label
    }

    private var subtitle: String {
        let interval = range.interval(from: date)
        let start = interval.start
        switch range {
        case .week:
            let end = Calendar.current.date(byAdding: .day, value: 6, to: start) ?? start
            let startStr = start.formatted(.dateTime.month(.abbreviated).day())
            let endStr = end.formatted(.dateTime.month(.abbreviated).day())
            return "\(startStr) – \(endStr)"
        case .month:
            return start.formatted(.dateTime.month(.wide).year())
        case .year:
            return start.formatted(.dateTime.year())
        }
    }

    var body: some View {
        Group {
            if workouts.isEmpty {
                EmptyStateView(
                    icon: "figure.run",
                    title: "No Workouts",
                    message: "No \(workoutType.label.lowercased()) workouts in this period."
                )
            } else {
                List(workouts, id: \.healthKitUUID) { workout in
                    NavigationLink(value: workout) {
                        WorkoutRowView(workout: workout)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}
