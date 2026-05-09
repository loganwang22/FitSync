import SwiftUI
import Charts

// MARK: - Routes

enum TrendChartRoute: Hashable {
    case weeklyDurationStacked
    case vo2Max
    case restingHR
    case hrv
    case weeklyDistance(WorkoutType)
    case weeklyDuration(WorkoutType)
    case runningCadence
    case runningGCT
    case runningStride
    case cyclingPower
    case cyclingSpeed
    case swimmingPace
    case swimmingStrokes
}

// MARK: - TrendsView

struct TrendsView: View {
    @State var viewModel: TrendsViewModel

    /// Number of weeks shown in the overview. Detail view shows the full window.
    private static let overviewWeeks = 6

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
            .navigationDestination(for: TrendChartRoute.self) { route in
                TrendChartDetailView(route: route, viewModel: viewModel)
            }
            .onAppear { viewModel.load() }
        }
    }

    // MARK: - All tab (overview)

    @ViewBuilder
    private var allSections: some View {
        previewLink(route: .weeklyDurationStacked) {
            StackedWeeklyDurationChart(
                entries: recentWeeks(viewModel.durationBySport, weeks: Self.overviewWeeks),
                interactive: false
            )
        }
        previewLink(route: .vo2Max) {
            VO2MaxChart(
                samples: recentSamples(viewModel.vo2MaxSamples, months: 3),
                latest: viewModel.latestVO2Max,
                delta: viewModel.vo2MaxDelta,
                interactive: false
            )
        }
        previewLink(route: .restingHR) {
            RestingHRChart(
                samples: recentSamples(viewModel.restingHRSamples, months: 3),
                latest: viewModel.latestRestingHR,
                delta: viewModel.restingHRDelta,
                interactive: false
            )
        }
        previewLink(route: .hrv) {
            HRVChart(
                samples: recentSamples(viewModel.hrvSamples, months: 3),
                latest: viewModel.latestHRV,
                delta: viewModel.hrvDelta,
                interactive: false
            )
        }
    }

    // MARK: - Per-sport tab (overview)

    @ViewBuilder
    private func perSportSections(type: WorkoutType) -> some View {
        previewLink(route: .weeklyDistance(type)) {
            WeeklyBarChart(
                title: "Weekly Distance",
                unit: "km",
                data: recentWeekValues(
                    viewModel.weeklyData.map { WeekValue(weekStart: $0.weekStart, value: $0.totalDistanceKm) },
                    weeks: Self.overviewWeeks
                ),
                color: .accentColor,
                format: { String(format: "%.1f", $0) },
                interactive: false
            )
        }

        previewLink(route: .weeklyDuration(type)) {
            WeeklyBarChart(
                title: "Weekly Duration",
                unit: "min",
                data: recentWeekValues(
                    viewModel.weeklyData.map { WeekValue(weekStart: $0.weekStart, value: $0.totalDurationMinutes) },
                    weeks: Self.overviewWeeks
                ),
                color: .green,
                format: { String(format: "%.0f", $0) },
                interactive: false
            )
        }

        switch type {
        case .running:
            previewLink(route: .runningCadence) {
                MetricLineChart(title: "Cadence", unit: "spm",
                                data: recentMetric(viewModel.runningCadence, weeks: Self.overviewWeeks),
                                color: .orange, format: { String(format: "%.0f", $0) }, interactive: false)
            }
            previewLink(route: .runningGCT) {
                MetricLineChart(title: "Ground Contact Time", unit: "ms",
                                data: recentMetric(viewModel.runningGCT, weeks: Self.overviewWeeks),
                                color: .purple, format: { String(format: "%.0f", $0) }, interactive: false)
            }
            previewLink(route: .runningStride) {
                MetricLineChart(title: "Stride Length", unit: "m",
                                data: recentMetric(viewModel.runningStride, weeks: Self.overviewWeeks),
                                color: .pink, format: { String(format: "%.2f", $0) }, interactive: false)
            }
        case .cycling:
            previewLink(route: .cyclingPower) {
                MetricLineChart(title: "Avg Power", unit: "W",
                                data: recentMetric(viewModel.cyclingPower, weeks: Self.overviewWeeks),
                                color: .orange, format: { String(format: "%.0f", $0) }, interactive: false)
            }
            previewLink(route: .cyclingSpeed) {
                MetricLineChart(title: "Avg Speed", unit: "km/h",
                                data: recentMetric(viewModel.cyclingSpeedKmh, weeks: Self.overviewWeeks),
                                color: .purple, format: { String(format: "%.1f", $0) }, interactive: false)
            }
        case .swimming:
            previewLink(route: .swimmingPace) {
                MetricLineChart(title: "Pace per 100m", unit: "/100m",
                                data: recentMetric(viewModel.swimmingPacePer100m, weeks: Self.overviewWeeks),
                                color: .orange, format: formatSwimPace, interactive: false)
            }
            previewLink(route: .swimmingStrokes) {
                MetricLineChart(title: "Strokes per Workout", unit: "",
                                data: recentMetric(viewModel.swimmingStrokesPerWorkout, weeks: Self.overviewWeeks),
                                color: .purple, format: { String(format: "%.0f", $0) }, interactive: false)
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func previewLink<Content: View>(route: TrendChartRoute, @ViewBuilder content: () -> Content) -> some View {
        NavigationLink(value: route) {
            VStack(spacing: 0) {
                content()
                    .padding(.top, 12)
                HStack(spacing: 4) {
                    Spacer()
                    Text("View details")
                        .font(.caption.weight(.semibold))
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.accentColor.opacity(0.08))
            }
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color(.separator), lineWidth: 0.5)
            )
            .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
    }

    private func recentWeeks(_ entries: [TrendsViewModel.DurationBySport], weeks: Int) -> [TrendsViewModel.DurationBySport] {
        guard let cutoff = Calendar.current.date(byAdding: .weekOfYear, value: -(weeks - 1), to: Date.now) else { return entries }
        let start = Calendar.current.dateInterval(of: .weekOfYear, for: cutoff)?.start ?? cutoff
        return entries.filter { $0.weekStart >= start }
    }

    private func recentWeekValues(_ values: [WeekValue], weeks: Int) -> [WeekValue] {
        Array(values.suffix(weeks))
    }

    private func recentMetric(_ points: [TrendsViewModel.MetricPoint], weeks: Int) -> [TrendsViewModel.MetricPoint] {
        Array(points.suffix(weeks))
    }

    private func recentSamples<T>(_ samples: [T], months: Int) -> [T] where T: DatedSample {
        guard let cutoff = Calendar.current.date(byAdding: .month, value: -months, to: Date.now) else { return samples }
        return samples.filter { $0.sampleDate >= cutoff }
    }
}

// MARK: - DatedSample (for filtering)

protocol DatedSample { var sampleDate: Date { get } }
extension HealthKitService.VO2MaxSample: DatedSample { var sampleDate: Date { date } }
extension HealthKitService.RestingHRSample: DatedSample { var sampleDate: Date { date } }
extension HealthKitService.HRVSample: DatedSample { var sampleDate: Date { date } }

// MARK: - Shared helpers

fileprivate func formatSwimPace(_ seconds: Double) -> String {
    let m = Int(seconds) / 60
    let s = Int(seconds) % 60
    return String(format: "%d'%02d\"", m, s)
}

fileprivate func formatWeekRange(_ date: Date) -> String {
    let cal = Calendar.current
    guard let interval = cal.dateInterval(of: .weekOfYear, for: date) else {
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
    let end = cal.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
    let startStr = interval.start.formatted(.dateTime.month(.abbreviated).day())
    let endStr = end.formatted(.dateTime.day())
    return "\(startStr)–\(endStr)"
}

// MARK: - Week value (shared)

struct WeekValue: Identifiable {
    var id: TimeInterval { weekStart.timeIntervalSince1970 }
    let weekStart: Date
    let value: Double
}

// MARK: - Weekly bar chart

struct WeeklyBarChart: View {
    let title: String
    let unit: String
    let data: [WeekValue]
    let color: Color
    let format: (Double) -> String
    var interactive: Bool = true
    var height: CGFloat = 180
    var visibleDomain: TimeInterval? = nil
    var scrollInitialX: Date? = nil

    @State private var selectedDate: Date?

    private var selected: WeekValue? {
        guard interactive, let s = selectedDate else { return nil }
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
                if let avg = average {
                    Text("Avg \(format(avg)) \(unit)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .frame(height: 24, alignment: .bottom)

            if data.isEmpty || data.allSatisfy({ $0.value == 0 }) {
                emptyBox(height: height)
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
                        PointMark(
                            x: .value("Week", s.weekStart, unit: .weekOfYear),
                            y: .value(title, s.value)
                        )
                        .foregroundStyle(color)
                        .symbolSize(0)
                        .annotation(position: .top, alignment: .center, spacing: 4,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            ChartAnnotationBubble(
                                value: "\(format(s.value)) \(unit)",
                                date: formatWeekRange(s.weekStart)
                            )
                        }
                    }
                }
                .chartYAxisLabel(unit)
                .frame(height: height)
                .padding(.horizontal)
                .modifier(ScrollableDomain(visibleDomain: visibleDomain, initialScrollX: scrollInitialX))
                .modifier(ConditionalChartGesture(enabled: interactive, selectedDate: $selectedDate))
            }
        }
    }
}

// MARK: - Stacked weekly duration chart

struct StackedWeeklyDurationChart: View {
    let entries: [TrendsViewModel.DurationBySport]
    var interactive: Bool = true
    var height: CGFloat = 200
    var visibleDomain: TimeInterval? = nil
    var scrollInitialX: Date? = nil

    @State private var selectedDate: Date?

    private var selectedWeekTotals: [(type: WorkoutType, minutes: Double)]? {
        guard interactive, let s = selectedDate else { return nil }
        let cal = Calendar.current
        let matching = entries.filter { cal.isDate($0.weekStart, equalTo: s, toGranularity: .weekOfYear) }
        guard !matching.isEmpty else { return nil }
        return WorkoutType.allCases.compactMap { type -> (WorkoutType, Double)? in
            let total = matching.filter { $0.type == type }.map(\.minutes).reduce(0, +)
            return total > 0 ? (type, total) : nil
        }
    }

    private var selectedWeekStart: Date? {
        guard interactive, let s = selectedDate,
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
            }
            .padding(.horizontal)
            .frame(height: 24, alignment: .bottom)

            if entries.isEmpty {
                emptyBox(height: height)
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
                    if let week = selectedWeekStart, let totals = selectedWeekTotals {
                        RuleMark(x: .value("Selected", week, unit: .weekOfYear))
                            .foregroundStyle(.secondary.opacity(0.4))
                            .lineStyle(StrokeStyle(dash: [4, 3]))
                        PointMark(
                            x: .value("Week", week, unit: .weekOfYear),
                            y: .value("Duration", totals.map(\.minutes).reduce(0, +))
                        )
                        .foregroundStyle(.clear)
                        .symbolSize(0)
                        .annotation(position: .top, alignment: .center, spacing: 4,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            stackedAnnotation(week: week, totals: totals)
                        }
                    }
                }
                .chartForegroundStyleScale([
                    "Running": Color.runningColor,
                    "Cycling": Color.cyclingColor,
                    "Swimming": Color.swimmingColor,
                ])
                .chartYAxisLabel("min")
                .frame(height: height)
                .padding(.horizontal)
                .modifier(ScrollableDomain(visibleDomain: visibleDomain, initialScrollX: scrollInitialX))
                .modifier(ConditionalChartGesture(enabled: interactive, selectedDate: $selectedDate))
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

    @ViewBuilder
    private func stackedAnnotation(week: Date, totals: [(type: WorkoutType, minutes: Double)]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                ForEach(totals, id: \.type) { entry in
                    HStack(spacing: 3) {
                        Circle().fill(color(for: entry.type)).frame(width: 6, height: 6)
                        Text("\(Int(entry.minutes))").font(.caption.bold().monospacedDigit())
                    }
                }
            }
            Text(formatWeekRange(week))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
    }
}

// MARK: - Metric line chart

struct MetricLineChart: View {
    let title: String
    let unit: String
    let data: [TrendsViewModel.MetricPoint]
    let color: Color
    let format: (Double) -> String
    var interactive: Bool = true
    var height: CGFloat = 160
    var visibleDomain: TimeInterval? = nil
    var scrollInitialX: Date? = nil

    @State private var selectedDate: Date?

    private var selected: TrendsViewModel.MetricPoint? {
        guard interactive, let s = selectedDate, !data.isEmpty else { return nil }
        return data.min(by: {
            abs($0.weekStart.timeIntervalSince(s)) < abs($1.weekStart.timeIntervalSince(s))
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer()
                if let latest = data.last?.value {
                    Text("\(format(latest))\(unit.isEmpty ? "" : " \(unit)")")
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .frame(height: 24, alignment: .bottom)

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
                        PointMark(
                            x: .value("Week", pt.weekStart),
                            y: .value(title, pt.value)
                        )
                        .foregroundStyle(color)
                        .symbolSize(0)
                        .annotation(position: .top, alignment: .center, spacing: 4,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            ChartAnnotationBubble(
                                value: "\(format(pt.value))\(unit.isEmpty ? "" : " \(unit)")",
                                date: formatWeekRange(pt.weekStart)
                            )
                        }
                    }
                }
                .chartYScale(domain: (minV - pad)...(maxV + pad))
                .frame(height: height)
                .padding(.horizontal)
                .modifier(ScrollableDomain(visibleDomain: visibleDomain, initialScrollX: scrollInitialX))
                .modifier(ConditionalChartGesture(enabled: interactive, selectedDate: $selectedDate))
            }
        }
    }
}

// MARK: - VO2 max chart

struct VO2MaxChart: View {
    let samples: [HealthKitService.VO2MaxSample]
    let latest: Double?
    let delta: Double?
    var interactive: Bool = true
    var height: CGFloat = 200
    var visibleDomain: TimeInterval? = nil
    var scrollInitialX: Date? = nil

    @State private var selectedDate: Date?

    private var selected: HealthKitService.VO2MaxSample? {
        guard interactive, let s = selectedDate, !samples.isEmpty else { return nil }
        return samples.min(by: {
            abs($0.date.timeIntervalSince(s)) < abs($1.date.timeIntervalSince(s))
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Cardio Fitness").font(.headline)
                Spacer()
                if let latest {
                    HStack(spacing: 4) {
                        Text(String(format: "%.1f", latest))
                            .font(.subheadline.bold().monospacedDigit())
                        Text("ml/kg·min")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal)
            .frame(height: 24, alignment: .bottom)

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
                        PointMark(
                            x: .value("Date", pt.date),
                            y: .value("VO2 Max", pt.value)
                        )
                        .foregroundStyle(Color.accentColor)
                        .symbolSize(0)
                        .annotation(position: .top, alignment: .center, spacing: 4,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            ChartAnnotationBubble(
                                value: String(format: "%.1f ml/kg·min", pt.value),
                                date: pt.date.formatted(.dateTime.month(.abbreviated).day())
                            )
                        }
                    }
                }
                .chartYScale(domain: minV...maxV)
                .chartYAxisLabel("ml/kg·min")
                .frame(height: height)
                .padding(.horizontal)
                .modifier(ScrollableDomain(visibleDomain: visibleDomain, initialScrollX: scrollInitialX))
                .modifier(ConditionalChartGesture(enabled: interactive, selectedDate: $selectedDate))
            }
        }
    }
}

// MARK: - Resting heart rate chart

struct RestingHRChart: View {
    let samples: [HealthKitService.RestingHRSample]
    let latest: Double?
    let delta: Double?
    var interactive: Bool = true
    var height: CGFloat = 180
    var visibleDomain: TimeInterval? = nil
    var scrollInitialX: Date? = nil

    @State private var selectedDate: Date?

    private var selected: HealthKitService.RestingHRSample? {
        guard interactive, let s = selectedDate, !samples.isEmpty else { return nil }
        return samples.min(by: {
            abs($0.date.timeIntervalSince(s)) < abs($1.date.timeIntervalSince(s))
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Resting Heart Rate").font(.headline)
                Spacer()
                if let latest {
                    HStack(spacing: 4) {
                        Text(String(format: "%.0f", latest))
                            .font(.subheadline.bold().monospacedDigit())
                        Text("bpm")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal)
            .frame(height: 24, alignment: .bottom)

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
                        PointMark(
                            x: .value("Date", pt.date),
                            y: .value("BPM", pt.bpm)
                        )
                        .foregroundStyle(.red)
                        .symbolSize(0)
                        .annotation(position: .top, alignment: .center, spacing: 4,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            ChartAnnotationBubble(
                                value: String(format: "%.0f bpm", pt.bpm),
                                date: pt.date.formatted(.dateTime.month(.abbreviated).day())
                            )
                        }
                    }
                }
                .chartYScale(domain: minV...maxV)
                .chartYAxisLabel("bpm")
                .frame(height: height)
                .padding(.horizontal)
                .modifier(ScrollableDomain(visibleDomain: visibleDomain, initialScrollX: scrollInitialX))
                .modifier(ConditionalChartGesture(enabled: interactive, selectedDate: $selectedDate))
            }
        }
    }
}

// MARK: - HRV chart

struct HRVChart: View {
    let samples: [HealthKitService.HRVSample]
    let latest: Double?
    let delta: Double?
    var interactive: Bool = true
    var height: CGFloat = 180
    var visibleDomain: TimeInterval? = nil
    var scrollInitialX: Date? = nil

    @State private var selectedDate: Date?

    private var selected: HealthKitService.HRVSample? {
        guard interactive, let s = selectedDate, !samples.isEmpty else { return nil }
        return samples.min(by: {
            abs($0.date.timeIntervalSince(s)) < abs($1.date.timeIntervalSince(s))
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Heart Rate Variability").font(.headline)
                Spacer()
                if let latest {
                    HStack(spacing: 4) {
                        Text(String(format: "%.0f", latest))
                            .font(.subheadline.bold().monospacedDigit())
                        Text("ms")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal)
            .frame(height: 24, alignment: .bottom)

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
                        PointMark(
                            x: .value("Date", pt.date),
                            y: .value("HRV", pt.ms)
                        )
                        .foregroundStyle(.purple)
                        .symbolSize(0)
                        .annotation(position: .top, alignment: .center, spacing: 4,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            ChartAnnotationBubble(
                                value: String(format: "%.0f ms", pt.ms),
                                date: pt.date.formatted(.dateTime.month(.abbreviated).day())
                            )
                        }
                    }
                }
                .chartYScale(domain: minV...maxV)
                .chartYAxisLabel("ms")
                .frame(height: height)
                .padding(.horizontal)
                .modifier(ScrollableDomain(visibleDomain: visibleDomain, initialScrollX: scrollInitialX))
                .modifier(ConditionalChartGesture(enabled: interactive, selectedDate: $selectedDate))
            }
        }
    }
}

// MARK: - Gesture + helpers

struct ScrollableDomain: ViewModifier {
    let visibleDomain: TimeInterval?
    var initialScrollX: Date? = nil

    func body(content: Content) -> some View {
        if let domain = visibleDomain {
            if let initial = initialScrollX {
                content
                    .chartScrollableAxes(.horizontal)
                    .chartXVisibleDomain(length: domain)
                    .chartScrollPosition(initialX: initial)
            } else {
                content
                    .chartScrollableAxes(.horizontal)
                    .chartXVisibleDomain(length: domain)
            }
        } else {
            content
        }
    }
}

private struct ConditionalChartGesture: ViewModifier {
    let enabled: Bool
    @Binding var selectedDate: Date?

    func body(content: Content) -> some View {
        if enabled {
            content.chartGesture { proxy in
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let h = abs(value.translation.width)
                        let v = abs(value.translation.height)
                        if value.translation != .zero && v > h * 1.5 { return }
                        if let date: Date = proxy.value(atX: value.location.x) {
                            selectedDate = date
                        }
                    }
                    .onEnded { _ in
                        selectedDate = nil
                    }
            }
        } else {
            content.allowsHitTesting(false)
        }
    }
}

@ViewBuilder
fileprivate func emptyBox(height: CGFloat) -> some View {
    Text("No data available")
        .foregroundStyle(.secondary)
        .frame(height: height)
        .frame(maxWidth: .infinity)
}

// MARK: - Annotation bubble (shown on selected point)

struct ChartAnnotationBubble: View {
    let value: String
    let date: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.caption.bold().monospacedDigit())
            Text(date)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
    }
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
