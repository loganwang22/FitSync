import SwiftUI

struct GoalSelectionSheet: View {
    @Binding var selectedGoal: TrainingGoal?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(TrainingGoal.allCases) { goal in
                Button {
                    selectedGoal = goal
                    dismiss()
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: goal.systemImage)
                            .font(.title2)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 36)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(goal.label)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text(goal.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if selectedGoal == goal {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Training Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
