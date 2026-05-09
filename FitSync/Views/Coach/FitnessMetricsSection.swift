import SwiftUI

struct FitnessMetricsSection: View {
    let metrics: FitnessMetrics

    private var hasAnyMetric: Bool {
        metrics.cyclingFTP != nil ||
        metrics.cyclingLTHR != nil ||
        metrics.cyclingWattsPerKg != nil ||
        metrics.runningLTHR != nil ||
        metrics.runningThresholdPaceSecPerKm != nil
    }

    var body: some View {
        if hasAnyMetric {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "bolt.heart.fill")
                    .foregroundStyle(Color.accentColor)
                Text("Fitness Metrics")
                    .font(.headline)
                Spacer()
                Text("Estimated")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if metrics.cyclingFTP != nil
                || metrics.cyclingLTHR != nil
                || metrics.cyclingWattsPerKg != nil {
                sportBlock(
                    title: "Cycling",
                    icon: "bicycle",
                    rows: [
                        ("FTP", metrics.cyclingFTP.map { formatWatts($0.value) }, metrics.cyclingFTP),
                        ("Power-to-weight", metrics.cyclingWattsPerKg.map { formatWPerKg($0.value) }, metrics.cyclingWattsPerKg),
                        ("LTHR", metrics.cyclingLTHR.map { formatBpm($0.value) }, metrics.cyclingLTHR),
                    ]
                )
            }

            if metrics.runningLTHR != nil
                || metrics.runningThresholdPaceSecPerKm != nil {
                sportBlock(
                    title: "Running",
                    icon: "figure.run",
                    rows: [
                        ("Threshold pace", metrics.runningThresholdPaceSecPerKm.map { formatPace($0.value) }, metrics.runningThresholdPaceSecPerKm),
                        ("LTHR", metrics.runningLTHR.map { formatBpm($0.value) }, metrics.runningLTHR),
                    ]
                )
            }

            if metrics.cyclingWattsPerKg == nil, metrics.cyclingFTP != nil {
                Text("Add a body-mass sample in Health to see power-to-weight.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text("Estimates use your hardest sustained efforts from the last 8 weeks. Quality depends on how hard those efforts were — not a substitute for a lab test.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func sportBlock(
        title: String,
        icon: String,
        rows: [(label: String, value: String?, estimate: FitnessMetrics.Estimate?)]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
            }
            ForEach(rows.compactMap { row in
                row.value.map { (row.label, $0, row.estimate) }
            }, id: \.0) { label, value, estimate in
                metricRow(label: label, value: value, estimate: estimate)
            }
        }
    }

    private func metricRow(
        label: String,
        value: String,
        estimate: FitnessMetrics.Estimate?
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.subheadline)
                Spacer()
                Text(value)
                    .font(.subheadline.monospacedDigit().bold())
                if let conf = estimate?.confidence {
                    confidenceBadge(conf)
                }
            }
            if let method = estimate?.method {
                Text(method)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func confidenceBadge(_ confidence: FitnessMetrics.Confidence) -> some View {
        let color: Color = {
            switch confidence {
            case .high: .green
            case .medium: .orange
            case .low: .secondary
            }
        }()
        return Text(confidence.label)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.18))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // MARK: - Formatting

    private func formatWatts(_ w: Double) -> String { String(format: "%.0f W", w) }
    private func formatBpm(_ bpm: Double) -> String { String(format: "%.0f bpm", bpm) }
    private func formatWPerKg(_ r: Double) -> String { String(format: "%.2f W/kg", r) }
    private func formatPace(_ secsPerKm: Double) -> String {
        let m = Int(secsPerKm) / 60
        let s = Int(secsPerKm) % 60
        return String(format: "%d'%02d\"/km", m, s)
    }
}
