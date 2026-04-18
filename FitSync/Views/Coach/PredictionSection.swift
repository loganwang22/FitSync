import SwiftUI
import Charts

struct PredictionSection: View {
    let goal: TrainingGoal
    let prediction: RacePredictor.Prediction?
    let baselineAgeDays: Int?
    let history: [RacePredictor.WeeklyPrediction]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let prediction {
                predictionCard(prediction)
                breakdownRow(prediction)
                if !history.isEmpty {
                    progressChart
                }
                confidenceCaption
            } else {
                emptyState
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "stopwatch")
                .foregroundStyle(Color.accentColor)
            Text("Predicted \(goal.label) Time")
                .font(.headline)
            Spacer()
        }
    }

    // MARK: - Prediction card

    private func predictionCard(_ p: RacePredictor.Prediction) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(formatTime(p.predictedSeconds))
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.accentColor)
            Text(String(format: "for %.1f km", p.targetDistanceKm))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func breakdownRow(_ p: RacePredictor.Prediction) -> some View {
        HStack(spacing: 16) {
            breakdownItem(
                label: "Target pace",
                value: formatPace(p.predictedSeconds / p.targetDistanceKm)
            )
            breakdownItem(
                label: "Halfway",
                value: formatTime(p.predictedSeconds / 2)
            )
            breakdownItem(
                label: "Per 5 km",
                value: formatTime(p.predictedSeconds * 5 / p.targetDistanceKm)
            )
        }
    }

    private func breakdownItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.bold().monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Progress chart

    private var progressChart: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Trend (last \(history.count) weeks)")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            Chart(history) { point in
                LineMark(
                    x: .value("Week", point.weekEnd),
                    y: .value("Predicted", point.predictedSeconds / 60)
                )
                .foregroundStyle(Color.accentColor)
                .interpolationMethod(.monotone)

                PointMark(
                    x: .value("Week", point.weekEnd),
                    y: .value("Predicted", point.predictedSeconds / 60)
                )
                .foregroundStyle(Color.accentColor)
                .symbolSize(40)
            }
            .frame(height: 110)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let minutes = value.as(Double.self) {
                            Text("\(Int(minutes))m").font(.caption2)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
                        .font(.caption2)
                }
            }
        }
    }

    // MARK: - Confidence caption

    private var confidenceCaption: some View {
        Group {
            if let p = prediction, let ageDays = baselineAgeDays {
                let baseLabel = String(
                    format: "Based on your fastest %.1f km in the last %d days",
                    p.baseline.distanceKm, max(1, ageDays)
                )
                let freshnessWarning = ageDays > 21
                    ? " — baseline is a bit old, try a hard effort to refresh."
                    : ""
                Text(baseLabel + freshnessWarning)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Not enough data yet")
                .font(.subheadline.bold())
            Text("Do a hard run of 5 km or more in the last 6 weeks to see a predicted \(goal.label.lowercased()) time.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Formatting

    private func formatTime(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    private func formatPace(_ secsPerKm: Double) -> String {
        let m = Int(secsPerKm) / 60
        let s = Int(secsPerKm) % 60
        return String(format: "%d'%02d\"/km", m, s)
    }
}
