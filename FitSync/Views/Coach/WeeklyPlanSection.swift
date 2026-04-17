import SwiftUI

struct WeeklyPlanSection: View {
    let block: TrainingPlan.WeeklyBlock
    let isCurrentWeek: Bool

    private static let dayNames = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text(isCurrentWeek ? "This Week's Plan" : "Week \(block.weekNumber)")
                    .font(.headline)
                if block.isDeloadWeek {
                    Text("RECOVERY")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.2))
                        .foregroundStyle(.green)
                        .clipShape(Capsule())
                }
                Spacer()
                if isCurrentWeek, let completed = block.completedSessions {
                    Text("\(completed)/\(block.targetSessions)")
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            // Targets summary
            HStack(spacing: 16) {
                if block.targetRunKm > 0 {
                    targetBadge(icon: "figure.run", value: String(format: "%.0f km", block.targetRunKm))
                }
                if block.targetCycleKm > 0 {
                    targetBadge(icon: "figure.outdoor.cycle", value: String(format: "%.0f km", block.targetCycleKm))
                }
                if block.targetSwimM > 0 {
                    targetBadge(icon: "figure.pool.swim", value: String(format: "%.0f m", block.targetSwimM))
                }
            }

            // Daily workouts
            ForEach(block.workoutTargets) { target in
                workoutTargetRow(target)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func targetBadge(icon: String, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(value)
                .font(.caption.bold().monospacedDigit())
        }
        .foregroundStyle(.secondary)
    }

    private func workoutTargetRow(_ target: TrainingPlan.WorkoutTarget) -> some View {
        HStack(spacing: 10) {
            // Day label
            Text(Self.dayNames[safe: target.dayOfWeek] ?? "?")
                .font(.caption.bold())
                .frame(width: 32)
                .foregroundStyle(.secondary)

            // Intensity dot
            Circle()
                .fill(intensityColor(target.intensity))
                .frame(width: 8, height: 8)

            // Workout info
            VStack(alignment: .leading, spacing: 1) {
                Text(target.name)
                    .font(.subheadline.bold())
                HStack(spacing: 8) {
                    if let dist = target.targetDistanceMeters {
                        let formatted = target.typeRawValue == WorkoutType.swimming.rawValue
                            ? String(format: "%.0f m", dist)
                            : String(format: "%.1f km", dist / 1000)
                        Text(formatted)
                    }
                    if let mins = target.targetDurationMinutes {
                        Text("\(mins) min")
                    }
                    if let pace = target.targetPaceSecondsPerKm {
                        let m = Int(pace) / 60
                        let s = Int(pace) % 60
                        Text(String(format: "%d'%02d\"/km", m, s))
                    }
                    if let zone = target.targetHRZone {
                        Text(zone)
                            .foregroundStyle(zoneColor(zone))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }

    private func intensityColor(_ intensity: TrainingPlan.WorkoutTarget.Intensity) -> Color {
        switch intensity {
        case .easy: return .green
        case .moderate: return .orange
        case .hard: return .red
        }
    }

    private func zoneColor(_ zone: String) -> Color {
        switch zone {
        case "easy": return .green
        case "aerobic": return .blue
        case "threshold": return .orange
        default: return .secondary
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
