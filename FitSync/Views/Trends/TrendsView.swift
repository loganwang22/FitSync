import SwiftUI
import Charts

struct TrendsView: View {
    @State var viewModel: TrendsViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Type filter
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            TypeChip(label: "All", isSelected: viewModel.selectedType == nil) {
                                viewModel.selectType(nil)
                            }
                            ForEach(WorkoutType.allCases) { type in
                                TypeChip(label: type.label, isSelected: viewModel.selectedType == type) {
                                    viewModel.selectType(type)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }

                    if let type = viewModel.selectedType {
                        perSportSections(type: type)
                    } else {
                        allSections
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Trends")
            .onAppear { viewModel.load() }
        }
    }

    // MARK: - All tab

    @ViewBuilder
    private var allSections: some View {
        InteractiveStackedWeeklyDurationChart(entries: viewModel.durationBySport)
        InteractiveVO2MaxChart(
            samples: viewModel.vo2MaxSamples,
            latest: viewModel.latestVO2Max,
            delta: viewModel.vo2MaxDelta
        )
        InteractiveRestingHRChart(
            samples: viewModel.restingHRSamples,
            latest: viewModel.latestRestingHR,
            delta: viewModel.restingHRDelta
        )
        InteractiveHRVChart(
            samples: viewModel.hrvSamples,
            latest: viewModel.latestHRV,
            delta: viewModel.hrvDelta
        )
    }

    // MARK: - Per-sport tab

    @ViewBuilder
    private func perSportSections(type: WorkoutType) -> some View {
        InteractiveWeeklyBarChart(
            title: "Weekly Distance",
            unit: "km",
            data: viewModel.weeklyData.map { .init(weekStart: $0.weekStart, value: $0.totalDistanceKm) },
            color: .accentColor,
            format: { String(format: "%.1f", $0) }
        )

        InteractiveWeeklyBarChart(
            title: "Weekly Duration",
            unit: "min",
            data: viewModel.weeklyData.map { .init(weekStart: $0.weekStart, value: $0.totalDurationMinutes) },
            color: .green,
            format: { String(format: "%.0f", $0) }
        )

        switch type {
        case .running:
            InteractiveMetricLineChart(
                title: "Cadence",
                unit: "spm",
                data: viewModel.runningCadence,
                color: .orange,
                format: { String(format: "%.0f", $0) }
            )
            InteractiveMetricLineChart(
                title: "Ground Contact Time",
                unit: "ms",
                data: viewModel.runningGCT,
                color: .purple,
                format: { String(format: "%.0f", $0) }
            )
            InteractiveMetricLineChart(
                title: "Stride Length",
                unit: "m",
                data: viewModel.runningStride,
                color: .pink,
                format: { String(format: "%.2f", $0) }
            )
        case .cycling:
            InteractiveMetricLineChart(
                title: "Avg Power",
                unit: "W",
                data: viewModel.cyclingPower,
                color: .orange,
                format: { String(format: "%.0f", $0) }
            )
            InteractiveMetricLineChart(
                title: "Avg Speed",
                unit: "km/h",
                data: viewModel.cyclingSpeedKmh,
                color: .purple,
                format: { String(format: "%.1f", $0) }
            )
        case .swimming:
            InteractiveMetricLineChart(
                title: "Pace per 100m",
                unit: "/100m",
                data: viewModel.swimmingPacePer100m,
                color: .orange,
                format: formatSwimPace
            )
            InteractiveMetricLineChart(
                title: "Strokes per Workout",
                unit: "",
                data: viewModel.swimmingStrokesPerWorkout,
                color: .purple,
                format: { String(format: "%.0f", $0) }
            )
        }
    }
}

// MARK: - Shared helpers

private func formatSwimPace(_ seconds: Double) -> String {
    let m = Int(seconds) / 60
    let s = Int(seconds) % 60
    return String(format: "%d'%02d\"", m, s)
}

private func formatWeekRange(_ date: Date) -> String {
    let cal = Calendar.current
    guard let interval = cal.dateInterval(of: .weekOfYear, for: date) else {
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
    let end = cal.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
    let startStr = interval.start.formatted(.dateTime.month(.abbreviated).day())
    let endStr = end.formatted(.dateTime.day())
    return "\(startStr)–\(endStr)"
}

// MARK: - Interactive weekly bar chart (single series)

private struct WeekValue: Identifiable {
    var id: TimeInterval { weekStart.timeIntervalSince1970 }
    let weekStart: Date
    let value: Double
}

private struct InteractiveWeeklyBarChart: View {
    let title: String
    let unit: String
    let data: [WeekValue]
    let color: Color
    let format: (Double) -> String

    @State private var selectedDate: Date?

    private var selected: WeekValue? {
        guard let s = selectedDate else { return nil }
        let cal = Calendar.current
        return data.first { cal.isDate($0.weekStart, equalTo: s, toGranularity: .weekOfYear) }
    }

    private var average: Double? {
        let nonzero = data.map(\.value).filter { $0 > 0 }
        guard !nonzero.isEmpty else { return nil }
        return nonzero.reduce(0, +) / Double(nonzero.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer()
                if let s = selected {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(format(s.value)) \(unit)")
                            .font(.subheadline.bold().monospacedDigit())
                        Text(formatWeekRange(s.weekStart))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else if let avg = average {
                    Text("Avg \(format(avg)) \(unit)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)

            if data.isEmpty || data.allSatisfy({ $0.value == 0 }) {
                emptyBox(height: 180)
            } else {
                Chart {
                    ForEach(data) { pt in
                        BarMark(
                            x: .value("Week", pt.weekStart, unit: .weekOfYear),
                            y: .value(title, pt.value)
                        )
                        .foregroundStyle(
                            selected?.id == pt.id
                                ? AnyShapeStyle(color)
                                : AnyShapeStyle(color.opacity(selected == nil ? 1 : 0.35).gradient)
                        )
                        .cornerRadius(4)
                    }
                    if let s = selected {
                        RuleMark(x: .value("Selected", s.weekStart, unit: .weekOfYear))
                            .foregroundStyle(.secondary.opacity(0.4))
                            .lineStyle(StrokeStyle(dash: [4, 3]))
                    }
                }
                .chartYAxisLabel(unit)
                .frame(height: 180)
                .padding(.horizontal)
                .chartGesture { proxy in
                    chartDragGesture(proxy: proxy, bindingDate: $selectedDate)
                }
            }
        }
    }
}

// MARK: - Interactive stacked weekly duration chart (All tab)

private struct InteractiveStackedWeeklyDurationChart: View {
    let entries: [TrendsViewModel.DurationBySport]

    @State private var selectedDate: Date?

    private var selectedWeekTotals: [(type: WorkoutType, minutes: Double)]? {
        guard let s = selectedDate else { return nil }
        let cal = Calendar.current
        let matching = entries.filter { cal.isDate($0.weekStart, equalTo: s, toGranularity: .weekOfYear) }
        guard !matching.isEmpty else { return nil }
        return WorkoutType.allCases.compactMap { type -> (WorkoutType, Double)? in
            let total = matching.filter { $0.type == type }.map(\.minutes).reduce(0, +)
            return total > 0 ? (type, total) : nil
        }
    }

    private var selectedWeekStart: Date? {
        guard let s = selectedDate,
              let first = entries.first(where: { Calendar.current.isDate($0.weekStart, equalTo: s, toGranularity: .weekOfYear) }) else {
            return nil
        }
        return first.weekStart
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Weekly Duration").font(.headline)
                Spacer()
                if let week = selectedWeekStart, let totals = selectedWeekTotals {
                    VStack(alignment: .trailing, spacing: 0) {
                        HStack(spacing: 6) {
                            ForEach(totals, id: \.type) { entry in
                                HStack(spacing: 3) {
                                    Circle()
                                        .fill(color(for: entry.type))
                                        .frame(width: 6, height: 6)
                                    Text("\(Int(entry.minutes))")
                                        .font(.caption.bold().monospacedDigit())
                                }
                            }
                        }
                        Text(formatWeekRange(week))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal)

            if entries.isEmpty {
                emptyBox(height: 200)
            } else {
                Chart {
                    ForEach(entries) { entry in
                        BarMark(
                            x: .value("Week", entry.weekStart, unit: .weekOfYear),
                            y: .value("Duration", entry.minutes)
                        )
                        .foregroundStyle(by: .value("Sport", entry.type.label))
                        .opacity(selectedDate == nil || Calendar.current.isDate(entry.weekStart, equalTo: selectedDate ?? .now, toGranularity: .weekOfYear) ? 1.0 : 0.35)
                    }
                    if let week = selectedWeekStart {
                        RuleMark(x: .value("Selected", week, unit: .weekOfYear))
                            .foregroundStyle(.secondary.opacity(0.4))
                            .lineStyle(StrokeStyle(dash: [4, 3]))
                    }
                }
                .chartForegroundStyleScale([
                    "Running": Color.runningColor,
                    "Cycling": Color.cyclingColor,
                    "Swimming": Color.swimmingColor,
                ])
                .chartYAxisLabel("min")
                .frame(height: 200)
                .padding(.horizontal)
                .chartGesture { proxy in
                    chartDragGesture(proxy: proxy, bindingDate: $selectedDate)
                }
            }
        }
    }

    private func color(for type: WorkoutType) -> Color {
        switch type {
        case .running: return .runningColor
        case .cycling: return .cyclingColor
        case .swimming: return .swimmingColor
        }
    }
}

// MARK: - Interactive metric line chart

private struct InteractiveMetricLineChart: View {
    let title: String
    let unit: String
    let data: [TrendsViewModel.MetricPoint]
    let color: Color
    let format: (Double) -> String

    @State private var selectedDate: Date?

    private var selected: TrendsViewModel.MetricPoint? {
        guard let s = selectedDate, !data.isEmpty else { return nil }
        return data.min(by: {
            abs($0.weekStart.timeIntervalSince(s)) < abs($1.weekStart.timeIntervalSince(s))
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer()
                if let pt = selected {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(format(pt.value))\(unit.isEmpty ? "" : " \(unit)")")
                            .font(.subheadline.bold().monospacedDigit())
                        Text(formatWeekRange(pt.weekStart))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else if let latest = data.last?.value {
                    Text("\(format(latest))\(unit.isEmpty ? "" : " \(unit)")")
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)

            if data.isEmpty {
                Text("No data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            } else {
                let values = data.map(\.value)
                let minV = values.min() ?? 0
                let maxV = values.max() ?? 0
                let pad = max((maxV - minV) * 0.15, maxV * 0.02)

                Chart {
                    ForEach(data) { pt in
                        LineMark(
                            x: .value("Week", pt.weekStart),
                            y: .value(title, pt.value)
                        )
                        .foregroundStyle(color)
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Week", pt.weekStart),
                            y: .value(title, pt.value)
                        )
                        .foregroundStyle(color)
                        .symbolSize(selected?.id == pt.id ? 90 : 30)
                    }
                    if let pt = selected {
                        RuleMark(x: .value("Selected", pt.weekStart))
                            .foregroundStyle(.secondary.opacity(0.4))
                            .lineStyle(StrokeStyle(dash: [4, 3]))
                    }
                }
                .chartYScale(domain: (minV - pad)...(maxV + pad))
                .frame(height: 160)
                .padding(.horizontal)
                .chartGesture { proxy in
                    chartDragGesture(proxy: proxy, bindingDate: $selectedDate)
                }
            }
        }
    }
}

// MARK: - Interactive VO2 max chart

private struct InteractiveVO2MaxChart: View {
    let samples: [HealthKitService.VO2MaxSample]
    let latest: Double?
    let delta: Double?

    @State private var selectedDate: Date?

    private var selected: HealthKitService.VO2MaxSample? {
        guard let s = selectedDate, !samples.isEmpty else { return nil }
        return samples.min(by: {
            abs($0.date.timeIntervalSince(s)) < abs($1.date.timeIntervalSince(s))
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Cardio Fitness").font(.headline)
                Spacer()
                if let pt = selected {
                    VStack(alignment: .trailing, spacing: 0) {
                        HStack(spacing: 4) {
                            Text(String(format: "%.1f", pt.value))
                                .font(.subheadline.bold().monospacedDigit())
                            Text("ml/kg·min")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(pt.date.formatted(.dateTime.month(.abbreviated).day()))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else if let latest {
                    HStack(spacing: 4) {
                        Text(String(format: "%.1f", latest))
                            .font(.subheadline.bold().monospacedDigit())
                        Text("ml/kg·min")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if let delta, abs(delta) >= 0.1 {
                            Text(String(format: "%@%.1f", delta >= 0 ? "+" : "", delta))
                                .font(.caption.bold().monospacedDigit())
                                .foregroundStyle(delta >= 0 ? .green : .orange)
                        }
                    }
                }
            }
            .padding(.horizontal)

            if samples.isEmpty {
                Text("No VO2 max data. Apple Watch records this after qualifying outdoor walks or runs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100, alignment: .center)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            } else {
                let values = samples.map(\.value)
                let minV = (values.min() ?? 0) - 2
                let maxV = (values.max() ?? 0) + 2

                Chart {
                    ForEach(samples) { sample in
                        LineMark(
                            x: .value("Date", sample.date),
                            y: .value("VO2 Max", sample.value)
                        )
                        .foregroundStyle(Color.accentColor)
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Date", sample.date),
                            y: .value("VO2 Max", sample.value)
                        )
                        .foregroundStyle(Color.accentColor)
                        .symbolSize(selected?.id == sample.id ? 90 : 30)
                    }
                    if let pt = selected {
                        RuleMark(x: .value("Selected", pt.date))
                            .foregroundStyle(.secondary.opacity(0.4))
                            .lineStyle(StrokeStyle(dash: [4, 3]))
                    }
                }
                .chartYScale(domain: minV...maxV)
                .chartYAxisLabel("ml/kg·min")
                .frame(height: 200)
                .padding(.horizontal)
                .chartGesture { proxy in
                    chartDragGesture(proxy: proxy, bindingDate: $selectedDate)
                }
            }
        }
    }
}

// MARK: - Interactive Resting Heart Rate chart

private struct InteractiveRestingHRChart: View {
    let samples: [HealthKitService.RestingHRSample]
    let latest: Double?
    let delta: Double?

    @State private var selectedDate: Date?

    private var selected: HealthKitService.RestingHRSample? {
        guard let s = selectedDate, !samples.isEmpty else { return nil }
        return samples.min(by: {
            abs($0.date.timeIntervalSince(s)) < abs($1.date.timeIntervalSince(s))
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Resting Heart Rate").font(.headline)
                Spacer()
                if let pt = selected {
                    VStack(alignment: .trailing, spacing: 0) {
                        HStack(spacing: 4) {
                            Text(String(format: "%.0f", pt.bpm))
                                .font(.subheadline.bold().monospacedDigit())
                            Text("bpm")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(pt.date.formatted(.dateTime.month(.abbreviated).day()))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else if let latest {
                    HStack(spacing: 4) {
                        Text(String(format: "%.0f", latest))
                            .font(.subheadline.bold().monospacedDigit())
                        Text("bpm")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if let delta, abs(delta) >= 1 {
                            // Lower resting HR = better, so negative delta is green
                            Text(String(format: "%@%.0f", delta >= 0 ? "+" : "", delta))
                                .font(.caption.bold().monospacedDigit())
                                .foregroundStyle(delta <= 0 ? .green : .orange)
                        }
                    }
                }
            }
            .padding(.horizontal)

            if samples.isEmpty {
                Text("No resting heart rate data. Apple Watch records this daily.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100, alignment: .center)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            } else {
                let values = samples.map(\.bpm)
                let minV = (values.min() ?? 0) - 3
                let maxV = (values.max() ?? 0) + 3

                Chart {
                    ForEach(samples) { sample in
                        LineMark(
                            x: .value("Date", sample.date),
                            y: .value("BPM", sample.bpm)
                        )
                        .foregroundStyle(.red)
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Date", sample.date),
                            y: .value("BPM", sample.bpm)
                        )
                        .foregroundStyle(.red)
                        .symbolSize(selected?.id == sample.id ? 90 : 20)
                    }
                    if let pt = selected {
                        RuleMark(x: .value("Selected", pt.date))
                            .foregroundStyle(.secondary.opacity(0.4))
                            .lineStyle(StrokeStyle(dash: [4, 3]))
                    }
                }
                .chartYScale(domain: minV...maxV)
                .chartYAxisLabel("bpm")
                .frame(height: 180)
                .padding(.horizontal)
                .chartGesture { proxy in
                    chartDragGesture(proxy: proxy, bindingDate: $selectedDate)
                }
            }
        }
    }
}

// MARK: - Interactive HRV chart

private struct InteractiveHRVChart: View {
    let samples: [HealthKitService.HRVSample]
    let latest: Double?
    let delta: Double?

    @State private var selectedDate: Date?

    private var selected: HealthKitService.HRVSample? {
        guard let s = selectedDate, !samples.isEmpty else { return nil }
        return samples.min(by: {
            abs($0.date.timeIntervalSince(s)) < abs($1.date.timeIntervalSince(s))
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Heart Rate Variability").font(.headline)
                Spacer()
                if let pt = selected {
                    VStack(alignment: .trailing, spacing: 0) {
                        HStack(spacing: 4) {
                            Text(String(format: "%.0f", pt.ms))
                                .font(.subheadline.bold().monospacedDigit())
                            Text("ms")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(pt.date.formatted(.dateTime.month(.abbreviated).day()))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else if let latest {
                    HStack(spacing: 4) {
                        Text(String(format: "%.0f", latest))
                            .font(.subheadline.bold().monospacedDigit())
                        Text("ms")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if let delta, abs(delta) >= 1 {
                            // Higher HRV = better, so positive delta is green
                            Text(String(format: "%@%.0f", delta >= 0 ? "+" : "", delta))
                                .font(.caption.bold().monospacedDigit())
                                .foregroundStyle(delta >= 0 ? .green : .orange)
                        }
                    }
                }
            }
            .padding(.horizontal)

            if samples.isEmpty {
                Text("No HRV data. Apple Watch records this nightly during sleep.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100, alignment: .center)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            } else {
                let values = samples.map(\.ms)
                let minV = max((values.min() ?? 0) - 5, 0)
                let maxV = (values.max() ?? 0) + 5

                Chart {
                    ForEach(samples) { sample in
                        LineMark(
                            x: .value("Date", sample.date),
                            y: .value("HRV", sample.ms)
                        )
                        .foregroundStyle(.purple)
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Date", sample.date),
                            y: .value("HRV", sample.ms)
                        )
                        .foregroundStyle(.purple)
                        .symbolSize(selected?.id == sample.id ? 90 : 20)
                    }
                    if let pt = selected {
                        RuleMark(x: .value("Selected", pt.date))
                            .foregroundStyle(.secondary.opacity(0.4))
                            .lineStyle(StrokeStyle(dash: [4, 3]))
                    }
                }
                .chartYScale(domain: minV...maxV)
                .chartYAxisLabel("ms")
                .frame(height: 180)
                .padding(.horizontal)
                .chartGesture { proxy in
                    chartDragGesture(proxy: proxy, bindingDate: $selectedDate)
                }
            }
        }
    }
}

// MARK: - Shared gesture + helpers

private func chartDragGesture(proxy: ChartProxy, bindingDate: Binding<Date?>) -> some Gesture {
    DragGesture(minimumDistance: 0)
        .onChanged { value in
            let h = abs(value.translation.width)
            let v = abs(value.translation.height)
            // Allow initial tap (translation == .zero), reject clearly vertical drags.
            if value.translation != .zero && v > h * 1.5 { return }
            if let date: Date = proxy.value(atX: value.location.x) {
                bindingDate.wrappedValue = date
            }
        }
        .onEnded { _ in
            bindingDate.wrappedValue = nil
        }
}

@ViewBuilder
private func emptyBox(height: CGFloat) -> some View {
    Text("No data available")
        .foregroundStyle(.secondary)
        .frame(height: height)
        .frame(maxWidth: .infinity)
}

// MARK: - Type chip

private struct TypeChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(.systemGray5))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
    }
}
