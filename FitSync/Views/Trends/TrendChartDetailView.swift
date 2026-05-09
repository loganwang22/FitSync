import SwiftUI

/// Interactive detail page for a single trend chart.
///
/// The overview cards on the Trends tab are static previews. Tapping one
/// navigates here, where the chart is full-width, scrubs on drag, scrolls
/// horizontally when zoomed, and pinches to change the visible window.
struct TrendChartDetailView: View {
    let route: TrendChartRoute
    let viewModel: TrendsViewModel

    /// Zoom factor applied on top of the chart's default visible window.
    /// 1.0 = default window (e.g. 90 days for cardio). >1 = zoomed in;
    /// <1 = zoomed out, up to the full available data range.
    @State private var zoomScale: CGFloat = 1.0
    @GestureState private var pinchScale: CGFloat = 1.0

    /// Orientation-aware — in landscape the parent TabBar overlaps the
    /// bottom of the scroll content, so we hide it via `toolbar(.hidden)` on
    /// this detail view only.
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// Landscape = compact vertical size class on iPhone.
    private var isLandscape: Bool { verticalSizeClass == .compact }

    var body: some View {
        GeometryReader { geo in
            if isLandscape {
                // Landscape: fill the available height so values are visible
                // without scrolling. Footnote is hidden to save vertical space.
                let h = max(geo.size.height - 40, 160)
                chartView(height: h)
                    .padding(.top, 8)
                    .gesture(magnifyGesture)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        chartView(height: defaultPortraitHeight)
                            .padding(.top, 8)
                            .gesture(magnifyGesture)
                        footnote
                            .padding(.horizontal)
                            .padding(.bottom, 16)
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(isLandscape ? .hidden : .automatic, for: .tabBar)
        .toolbar {
            if abs(zoomScale - 1.0) > 0.05 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Reset") { zoomScale = 1.0 }
                        .font(.caption)
                }
            }
        }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .updating($pinchScale) { value, state, _ in
                state = value.magnification
            }
            .onEnded { value in
                let minZoom = minZoomScale
                let next = zoomScale * value.magnification
                zoomScale = min(max(next, minZoom), 8.0)
            }
    }

    // MARK: - Zoom math

    /// Default visible window when zoomScale == 1.0. Cardio metrics default to
    /// 90 days; all other charts default to the full data range (nil → no
    /// scrolling/visibleDomain constraint).
    private var defaultVisibleSeconds: TimeInterval? {
        switch route {
        case .vo2Max, .restingHR, .hrv:
            return 90 * 86400
        default:
            return nil
        }
    }

    /// Minimum zoom scale. For charts with a default window we let the user
    /// pinch out far enough to see everything available.
    private var minZoomScale: CGFloat {
        guard let total = totalSpan, let base = defaultVisibleSeconds, total > base else {
            return 1.0
        }
        return max(CGFloat(base / total), 0.1)
    }

    private var effectiveZoom: CGFloat {
        let raw = zoomScale * pinchScale
        return min(max(raw, minZoomScale), 8.0)
    }

    /// Total time span in seconds for the chart's data. Returns nil when
    /// there's not enough data to make zooming meaningful.
    private var totalSpan: TimeInterval? {
        switch route {
        case .weeklyDurationStacked:
            return span(viewModel.durationBySport.map(\.weekStart))
        case .vo2Max:
            return span(viewModel.vo2MaxSamples.map(\.date))
        case .restingHR:
            return span(viewModel.restingHRSamples.map(\.date))
        case .hrv:
            return span(viewModel.hrvSamples.map(\.date))
        case .weeklyDistance, .weeklyDuration:
            return span(viewModel.weeklyData.map(\.weekStart))
        case .runningCadence:
            return span(viewModel.runningCadence.map(\.weekStart))
        case .runningGCT:
            return span(viewModel.runningGCT.map(\.weekStart))
        case .runningStride:
            return span(viewModel.runningStride.map(\.weekStart))
        case .cyclingPower:
            return span(viewModel.cyclingPower.map(\.weekStart))
        case .cyclingSpeed:
            return span(viewModel.cyclingSpeedKmh.map(\.weekStart))
        case .swimmingPace:
            return span(viewModel.swimmingPacePer100m.map(\.weekStart))
        case .swimmingStrokes:
            return span(viewModel.swimmingStrokesPerWorkout.map(\.weekStart))
        }
    }

    private func span(_ dates: [Date]) -> TimeInterval? {
        guard let first = dates.min(), let last = dates.max(), last > first else { return nil }
        // Pad by a week on each side so bars don't clip against the axes.
        return last.timeIntervalSince(first) + 14 * 86400
    }

    /// nil → show full range; otherwise a shorter visible window producing
    /// horizontal scrolling.
    private var visibleDomain: TimeInterval? {
        guard let total = totalSpan else { return nil }
        if let base = defaultVisibleSeconds {
            let target = base / Double(effectiveZoom)
            // Clamp to the actual data span — going wider than `total` has no
            // effect but distorts the axis, so cap it.
            return min(target, total)
        }
        // Non-cardio: only scroll when zoomed in past 1x.
        guard effectiveZoom > 1.01 else { return nil }
        return total / Double(effectiveZoom)
    }

    /// Latest data point on the x-axis for this route. Used to anchor the
    /// scrollable chart to the right edge so users see the most recent data
    /// by default rather than the oldest.
    private var latestDate: Date? {
        switch route {
        case .weeklyDurationStacked: return viewModel.durationBySport.map(\.weekStart).max()
        case .vo2Max: return viewModel.vo2MaxSamples.map(\.date).max()
        case .restingHR: return viewModel.restingHRSamples.map(\.date).max()
        case .hrv: return viewModel.hrvSamples.map(\.date).max()
        case .weeklyDistance, .weeklyDuration: return viewModel.weeklyData.map(\.weekStart).max()
        case .runningCadence: return viewModel.runningCadence.map(\.weekStart).max()
        case .runningGCT: return viewModel.runningGCT.map(\.weekStart).max()
        case .runningStride: return viewModel.runningStride.map(\.weekStart).max()
        case .cyclingPower: return viewModel.cyclingPower.map(\.weekStart).max()
        case .cyclingSpeed: return viewModel.cyclingSpeedKmh.map(\.weekStart).max()
        case .swimmingPace: return viewModel.swimmingPacePer100m.map(\.weekStart).max()
        case .swimmingStrokes: return viewModel.swimmingStrokesPerWorkout.map(\.weekStart).max()
        }
    }

    /// Leading edge of the initial visible window. Set so the window's
    /// trailing edge sits at the latest data point.
    private var scrollInitialX: Date? {
        guard let domain = visibleDomain, let latest = latestDate else { return nil }
        // Pad trailing edge by ~3 days so the latest marker isn't flush with
        // the axis wall.
        return latest.addingTimeInterval(-domain + 3 * 86400)
    }

    // MARK: - Chart routing

    /// Default chart height in portrait orientation.
    private var defaultPortraitHeight: CGFloat {
        switch route {
        case .weeklyDurationStacked, .vo2Max, .restingHR, .hrv,
             .weeklyDistance, .weeklyDuration:
            return 320
        default:
            return 300
        }
    }

    @ViewBuilder
    private func chartView(height h: CGFloat) -> some View {
        switch route {
        case .weeklyDurationStacked:
            StackedWeeklyDurationChart(
                entries: viewModel.durationBySport,
                height: h,
                visibleDomain: visibleDomain,
                scrollInitialX: scrollInitialX
            )

        case .vo2Max:
            VO2MaxChart(
                samples: viewModel.vo2MaxSamples,
                latest: viewModel.latestVO2Max,
                delta: viewModel.vo2MaxDelta,
                height: h,
                visibleDomain: visibleDomain,
                scrollInitialX: scrollInitialX
            )

        case .restingHR:
            RestingHRChart(
                samples: viewModel.restingHRSamples,
                latest: viewModel.latestRestingHR,
                delta: viewModel.restingHRDelta,
                height: h,
                visibleDomain: visibleDomain,
                scrollInitialX: scrollInitialX
            )

        case .hrv:
            HRVChart(
                samples: viewModel.hrvSamples,
                latest: viewModel.latestHRV,
                delta: viewModel.hrvDelta,
                height: h,
                visibleDomain: visibleDomain,
                scrollInitialX: scrollInitialX
            )

        case .weeklyDistance:
            WeeklyBarChart(
                title: "Weekly Distance",
                unit: "km",
                data: viewModel.weeklyData.map { WeekValue(weekStart: $0.weekStart, value: $0.totalDistanceKm) },
                color: .accentColor,
                format: { String(format: "%.1f", $0) },
                height: h,
                visibleDomain: visibleDomain,
                scrollInitialX: scrollInitialX
            )

        case .weeklyDuration:
            WeeklyBarChart(
                title: "Weekly Duration",
                unit: "min",
                data: viewModel.weeklyData.map { WeekValue(weekStart: $0.weekStart, value: $0.totalDurationMinutes) },
                color: .green,
                format: { String(format: "%.0f", $0) },
                height: h,
                visibleDomain: visibleDomain,
                scrollInitialX: scrollInitialX
            )

        case .runningCadence:
            MetricLineChart(title: "Cadence", unit: "spm",
                            data: viewModel.runningCadence, color: .orange,
                            format: { String(format: "%.0f", $0) },
                            height: h, visibleDomain: visibleDomain, scrollInitialX: scrollInitialX)

        case .runningGCT:
            MetricLineChart(title: "Ground Contact Time", unit: "ms",
                            data: viewModel.runningGCT, color: .purple,
                            format: { String(format: "%.0f", $0) },
                            height: h, visibleDomain: visibleDomain, scrollInitialX: scrollInitialX)

        case .runningStride:
            MetricLineChart(title: "Stride Length", unit: "m",
                            data: viewModel.runningStride, color: .pink,
                            format: { String(format: "%.2f", $0) },
                            height: h, visibleDomain: visibleDomain, scrollInitialX: scrollInitialX)

        case .cyclingPower:
            MetricLineChart(title: "Avg Power", unit: "W",
                            data: viewModel.cyclingPower, color: .orange,
                            format: { String(format: "%.0f", $0) },
                            height: h, visibleDomain: visibleDomain, scrollInitialX: scrollInitialX)

        case .cyclingSpeed:
            MetricLineChart(title: "Avg Speed", unit: "km/h",
                            data: viewModel.cyclingSpeedKmh, color: .purple,
                            format: { String(format: "%.1f", $0) },
                            height: h, visibleDomain: visibleDomain, scrollInitialX: scrollInitialX)

        case .swimmingPace:
            MetricLineChart(title: "Pace per 100m", unit: "/100m",
                            data: viewModel.swimmingPacePer100m, color: .orange,
                            format: detailFormatSwimPace,
                            height: h, visibleDomain: visibleDomain, scrollInitialX: scrollInitialX)

        case .swimmingStrokes:
            MetricLineChart(title: "Strokes per Workout", unit: "",
                            data: viewModel.swimmingStrokesPerWorkout, color: .purple,
                            format: { String(format: "%.0f", $0) },
                            height: h, visibleDomain: visibleDomain, scrollInitialX: scrollInitialX)
        }
    }

    // MARK: - Metadata

    private var title: String {
        switch route {
        case .weeklyDurationStacked: return "Weekly Duration"
        case .vo2Max: return "Cardio Fitness"
        case .restingHR: return "Resting Heart Rate"
        case .hrv: return "Heart Rate Variability"
        case .weeklyDistance: return "Weekly Distance"
        case .weeklyDuration: return "Weekly Duration"
        case .runningCadence: return "Cadence"
        case .runningGCT: return "Ground Contact Time"
        case .runningStride: return "Stride Length"
        case .cyclingPower: return "Avg Power"
        case .cyclingSpeed: return "Avg Speed"
        case .swimmingPace: return "Pace per 100m"
        case .swimmingStrokes: return "Strokes per Workout"
        }
    }

    @ViewBuilder
    private var footnote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Drag across the chart to inspect values.")
            Text("Pinch to zoom; scroll horizontally when zoomed. Rotate your device for a wider view.")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private func detailFormatSwimPace(_ seconds: Double) -> String {
    let m = Int(seconds) / 60
    let s = Int(seconds) % 60
    return String(format: "%d'%02d\"", m, s)
}
