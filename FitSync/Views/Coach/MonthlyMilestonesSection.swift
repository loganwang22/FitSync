import SwiftUI

struct MonthlyMilestonesSection: View {
    let milestones: [TrainingPlan.MonthlyMilestone]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Milestones")
                .font(.headline)

            ForEach(milestones) { milestone in
                milestoneRow(milestone)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func milestoneRow(_ milestone: TrainingPlan.MonthlyMilestone) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 2) {
                Text(milestone.month.formatted(.dateTime.month(.abbreviated)))
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                Image(systemName: milestone.achieved ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(milestone.achieved ? .green : .secondary)
            }
            .frame(width: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(milestone.title)
                    .font(.subheadline.bold())
                Text(milestone.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    if let km = milestone.targetWeeklyKm {
                        Label(String(format: "%.0f km/wk", km), systemImage: "arrow.up.right")
                    }
                    if let lr = milestone.targetLongRunKm {
                        Label(String(format: "%.1f km long", lr), systemImage: "road.lanes")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
