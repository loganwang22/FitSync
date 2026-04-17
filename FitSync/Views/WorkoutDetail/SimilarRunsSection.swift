import SwiftUI

struct SimilarRunsSection: View {
    let similarWorkouts: [Workout]
    let currentWorkout: Workout

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "repeat")
                    .foregroundStyle(Color.accentColor)
                Text("Similar Runs")
                    .font(.headline)
                Spacer()
                Text("\(similarWorkouts.count) matched")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Current workout reference row
            runRow(workout: currentWorkout, isCurrent: true)

            Divider()

            // Past similar workouts
            ForEach(similarWorkouts.prefix(10), id: \.healthKitUUID) { w in
                NavigationLink(value: w) {
                    runRow(workout: w, isCurrent: false)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func runRow(workout: Workout, isCurrent: Bool) -> some View {
        HStack(spacing: 0) {
            // Date
            VStack(alignment: .leading, spacing: 2) {
                if isCurrent {
                    Text("This Run")
                        .font(.caption.bold())
                        .foregroundStyle(Color.accentColor)
                } else {
                    Text(workout.startDate.formatted(.dateTime.month(.abbreviated).day().year(.twoDigits)))
                        .font(.caption)
                }
            }
            .frame(width: 80, alignment: .leading)

            // Duration
            Text(formatDuration(workout.durationSeconds))
                .font(.subheadline.bold().monospacedDigit())
                .frame(maxWidth: .infinity, alignment: .trailing)

            // Pace
            if let pace = workout.avgPaceSecondsPerKm {
                Text(formatPace(pace))
                    .font(.subheadline.monospacedDigit())
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                Text("–")
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            // Avg HR
            if let hr = workout.cachedAvgHeartRate {
                HStack(spacing: 2) {
                    Image(systemName: "heart.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                    Text(String(format: "%.0f", hr))
                        .font(.subheadline.monospacedDigit())
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                Text("–")
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            // Delta vs current
            if !isCurrent, let currentDur = currentWorkout.durationSeconds as Double? {
                let delta = workout.durationSeconds - currentDur
                Text(formatDelta(delta))
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(delta <= 0 ? .green : .orange)
                    .frame(width: 56, alignment: .trailing)
            } else {
                Color.clear.frame(width: 56)
            }
        }
    }

    // MARK: - Column header

    private func formatDuration(_ seconds: Double) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    private func formatPace(_ secsPerKm: Double) -> String {
        let m = Int(secsPerKm) / 60
        let s = Int(secsPerKm) % 60
        return String(format: "%d'%02d\"/km", m, s)
    }

    private func formatDelta(_ seconds: Double) -> String {
        let sign = seconds <= 0 ? "" : "+"
        let abs = abs(Int(seconds))
        let m = abs / 60
        let s = abs % 60
        if m > 0 {
            return String(format: "%@%d:%02d", sign, m, s)
        }
        return String(format: "%@0:%02d", sign, s)
    }
}
