import SwiftUI

struct WorkoutRowView: View {
    let workout: Workout

    var body: some View {
        HStack(spacing: 12) {
            WorkoutIcon(type: workout.type)

            VStack(alignment: .leading, spacing: 4) {
                Text(workout.type.label)
                    .font(.headline)
                Text(workout.startDate.shortFormatted)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if let dist = workout.distanceMeters {
                    Text(workout.type == .swimming ? dist.formattedDistanceM : dist.formattedDistanceKm)
                        .font(.subheadline.bold())
                }
                Text(workout.durationSeconds.formattedDuration)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct WorkoutFilterBar: View {
    @Binding var selectedType: WorkoutType?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(label: "All", isSelected: selectedType == nil) {
                    selectedType = nil
                }
                ForEach(WorkoutType.allCases) { type in
                    FilterChip(
                        label: type.label,
                        icon: type.systemImage,
                        isSelected: selectedType == type
                    ) {
                        selectedType = type
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

private struct FilterChip: View {
    let label: String
    var icon: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption)
                }
                Text(label)
                    .font(.subheadline)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : Color(.systemGray5))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
    }
}

struct WorkoutListView: View {
    @State var viewModel: WorkoutListViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                WorkoutFilterBar(selectedType: Binding(
                    get: { viewModel.selectedType },
                    set: { viewModel.filterBy($0) }
                ))
                .padding(.vertical, 8)

                if viewModel.isLoading && viewModel.workouts.isEmpty {
                    ProgressView("Syncing workouts...")
                        .frame(maxHeight: .infinity)
                } else if viewModel.workouts.isEmpty {
                    EmptyStateView(
                        icon: "figure.run",
                        title: "No Workouts",
                        message: "Your workouts from Apple Health will appear here."
                    )
                } else {
                    List(viewModel.workouts, id: \.healthKitUUID) { workout in
                        NavigationLink(value: workout) {
                            WorkoutRowView(workout: workout)
                        }
                    }
                    .listStyle(.plain)
                    .refreshable {
                        await viewModel.load()
                    }
                }
            }
            .navigationTitle("Activity")
            .navigationDestination(for: Workout.self) { workout in
                WorkoutDetailView(workout: workout)
            }
            .task {
                await viewModel.load()
            }
        }
    }
}
