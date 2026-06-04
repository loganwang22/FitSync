import SwiftUI
import MapKit
import Charts
import LinkPresentation

struct WorkoutDetailView: View {
    @State private var viewModel: WorkoutDetailViewModel
    @State private var isRendering = false
    private let repository: WorkoutRepository?

    init(workout: Workout, repository: WorkoutRepository? = nil) {
        let vm = WorkoutDetailViewModel(workout: workout)
        if let repository { vm.setRepository(repository) }
        _viewModel = State(initialValue: vm)
        self.repository = repository
    }

    private var workout: Workout { viewModel.workout }

    var body: some View {
        ScrollView {
            detailContent
        }
        .task { await viewModel.load() }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    if isRendering {
                        ProgressView()
                    } else {
                        Menu {
                            Button {
                                Task { await shareCard() }
                            } label: {
                                Label("Share Card", systemImage: "rectangle.portrait.on.rectangle.portrait")
                            }
                            Button {
                                snapshotAndShare()
                            } label: {
                                Label("Share Full Details", systemImage: "doc.richtext")
                            }
                            Button {
                                exportDataForAI()
                            } label: {
                                Label("Export Data for AI", systemImage: "text.alignleft")
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }

                    Menu {
                        Button {
                            Task { await viewModel.resync() }
                        } label: {
                            Label("Re-sync from Health", systemImage: "arrow.triangle.2.circlepath")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }

    private var detailContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                WorkoutIcon(type: workout.type, size: 48)
                VStack(alignment: .leading) {
                    Text(workout.type.label)
                        .font(.title2.bold())
                    Text(workout.startDate.shortFormatted)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)

            // Stats Grid
            WorkoutStatsGrid(workout: workout, viewModel: viewModel)
                .padding(.horizontal)

            // Time-series chart
            if viewModel.hasHeartRateSeries || viewModel.hasElevationSeries || viewModel.hasPowerSeries {
                TimeSeriesChart(
                    hrPoints: viewModel.heartRatePoints,
                    elevPoints: viewModel.elevationPoints,
                    powerPoints: viewModel.powerPoints,
                    totalDuration: workout.durationSeconds
                )
                .padding(.horizontal)
            }

            // Splits breakdown
            if !viewModel.segments.isEmpty {
                SegmentBreakdownView(
                    segments: viewModel.segments,
                    workoutType: workout.type
                )
                .padding(.horizontal)
            }

            // Route Map
            if viewModel.hasRoute {
                RouteMapSection(routePoints: viewModel.cachedRoutePoints)
                    .padding(.horizontal)
            }

            // Similar Runs (Matched Runs)
            if !viewModel.similarWorkouts.isEmpty {
                SimilarRunsSection(
                    similarWorkouts: viewModel.similarWorkouts,
                    currentWorkout: workout
                )
                .padding(.horizontal)
            }

            // Coach Analysis
            if let repository {
                WorkoutAnalysisSection(workout: workout, repository: repository)
                    .padding(.horizontal)
            }
        }
        .padding(.horizontal, 0)
        .padding(.top, 8)
        .padding(.bottom, 32)
    }

    @MainActor
    private func shareCard() async {
        isRendering = true
        let scale = UIScreen.main.scale

        // Render map snapshot
        let mapImage = await MapSnapshotter.snapshot(
            routePoints: viewModel.cachedRoutePoints
        )

        let card = WorkoutShareCard(
            mapImage: mapImage ?? UIImage(),
            workout: workout,
            avgHeartRate: viewModel.avgHeartRate,
            elevationGain: workout.elevationGainMeters
        )

        let renderer = ImageRenderer(content: card)
        renderer.scale = scale
        guard let image = renderer.uiImage else {
            isRendering = false
            return
        }
        isRendering = false
        presentShareSheet(image: image)
    }

    @MainActor
    private func snapshotAndShare() {
        isRendering = true
        let screenWidth = UIScreen.main.bounds.width
        let scale = UIScreen.main.scale

        let snapshot = WorkoutSnapshot(
            typeName: workout.type.label,
            typeIcon: workout.type,
            dateStr: workout.startDate.shortFormatted,
            statsView: WorkoutStatsGrid(workout: workout, viewModel: viewModel),
            hrPoints: viewModel.heartRatePoints,
            elevPoints: viewModel.elevationPoints,
            powerPoints: viewModel.powerPoints,
            totalDuration: workout.durationSeconds,
            segments: viewModel.segments,
            workoutType: workout.type,
            routePoints: viewModel.cachedRoutePoints
        )

        let renderer = ImageRenderer(content:
            snapshot
                .frame(width: screenWidth)
                .background(Color(.systemBackground))
        )
        renderer.scale = scale
        guard let image = renderer.uiImage else {
            isRendering = false
            return
        }
        isRendering = false
        presentShareSheet(image: image)
    }

    @MainActor
    private func exportDataForAI() {
        let text = WorkoutDataExporter.export(workout: workout, viewModel: viewModel)
        presentShareSheet(text: text)
    }

    @MainActor
    private func presentShareSheet(text: String) {
        let activityVC = UIActivityViewController(
            activityItems: [text],
            applicationActivities: nil
        )

        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first,
              let rootVC = windowScene.windows.first?.rootViewController else { return }

        var presenter = rootVC
        while let presented = presenter.presentedViewController {
            presenter = presented
        }

        activityVC.popoverPresentationController?.sourceView = presenter.view
        activityVC.popoverPresentationController?.sourceRect = CGRect(
            x: presenter.view.bounds.midX, y: 0, width: 0, height: 0
        )

        presenter.present(activityVC, animated: true)
    }

    @MainActor
    private func presentShareSheet(image: UIImage) {
        let itemSource = WorkoutImageItemSource(
            image: image,
            title: "\(workout.type.label) – \(workout.startDate.shortFormatted)"
        )
        let activityVC = UIActivityViewController(
            activityItems: [itemSource],
            applicationActivities: nil
        )

        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first,
              let rootVC = windowScene.windows.first?.rootViewController else { return }

        var presenter = rootVC
        while let presented = presenter.presentedViewController {
            presenter = presented
        }

        activityVC.popoverPresentationController?.sourceView = presenter.view
        activityVC.popoverPresentationController?.sourceRect = CGRect(
            x: presenter.view.bounds.midX, y: 0, width: 0, height: 0
        )

        presenter.present(activityVC, animated: true)
    }
}

/// Provides a titled preview in the share sheet.
private class WorkoutImageItemSource: NSObject, UIActivityItemSource {
    let image: UIImage
    let title: String

    init(image: UIImage, title: String) {
        self.image = image
        self.title = title
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        image
    }

    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        image
    }

    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        title
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = title
        let provider = NSItemProvider(object: image)
        metadata.imageProvider = provider
        metadata.iconProvider = provider
        return metadata
    }
}

/// Self-contained view for ImageRenderer snapshot — no @Observable references,
/// all data passed as plain values so the renderer can produce a UIImage.
private struct WorkoutSnapshot: View {
    let typeName: String
    let typeIcon: WorkoutType
    let dateStr: String
    let statsView: WorkoutStatsGrid
    let hrPoints: [WorkoutDetailViewModel.HeartRatePoint]
    let elevPoints: [WorkoutDetailViewModel.ElevationPoint]
    let powerPoints: [WorkoutDetailViewModel.PowerPoint]
    let totalDuration: Double
    let segments: [WorkoutDetailViewModel.WorkoutSegment]
    let workoutType: WorkoutType
    let routePoints: [RoutePoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                WorkoutIcon(type: typeIcon, size: 48)
                VStack(alignment: .leading) {
                    Text(typeName)
                        .font(.title2.bold())
                    Text(dateStr)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)

            statsView
                .padding(.horizontal)

            if !hrPoints.isEmpty || !elevPoints.isEmpty || !powerPoints.isEmpty {
                TimeSeriesChart(
                    hrPoints: hrPoints,
                    elevPoints: elevPoints,
                    powerPoints: powerPoints,
                    totalDuration: totalDuration
                )
                .padding(.horizontal)
            }

            if !segments.isEmpty {
                SegmentBreakdownView(
                    segments: segments,
                    workoutType: workoutType
                )
                .padding(.horizontal)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 32)
    }
}

struct WorkoutStatsGrid: View {
    let workout: Workout
    let viewModel: WorkoutDetailViewModel

    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
        ], spacing: 16) {
            if let dist = workout.distanceMeters {
                StatCard(title: "Distance", value: workout.type == .swimming ? dist.formattedDistanceM : dist.formattedDistanceKm, icon: "arrow.left.and.right")
            }

            StatCard(title: "Duration", value: workout.durationSeconds.formattedDuration, icon: "clock")

            if let cal = workout.activeEnergyKcal {
                StatCard(title: "Calories", value: cal.formattedCalories, icon: "flame")
            }

            if let pace = workout.avgPaceSecondsPerKm {
                StatCard(title: "Pace", value: pace.formattedPace, icon: "speedometer")
            }

            if workout.type == .cycling, let speed = workout.avgSpeedMps {
                StatCard(title: "Speed", value: speed.formattedSpeed, icon: "gauge.with.dots.needle.67percent")
            }

            if workout.type == .swimming, let pacePer100m = swimmingActivePacePer100m {
                StatCard(title: "Pace", value: pacePer100m.formattedSwimmingPace, icon: "speedometer")
            }

            if let gain = workout.elevationGainMeters,
               workout.type == .running || workout.type == .cycling {
                StatCard(title: "Ascent", value: gain.formattedElevation, icon: "arrow.up.right")
            }

            if let hr = viewModel.avgHeartRate {
                StatCard(title: "Avg HR", value: hr.formattedHeartRate, icon: "heart.fill")
            }
            if let maxHR = viewModel.maxHeartRate {
                StatCard(title: "Max HR", value: maxHR.formattedHeartRate, icon: "heart.fill")
            }

            if let power = viewModel.avgPowerWatts {
                StatCard(title: "Avg Power", value: power.formattedPower, icon: "bolt.fill")
            }
            if let maxPower = viewModel.maxPowerWatts {
                StatCard(title: "Max Power", value: maxPower.formattedPower, icon: "bolt.fill")
            }

            if workout.type == .running {
                if let cadence = viewModel.avgCadenceSpm {
                    StatCard(title: "Cadence", value: cadence.formattedCadence, icon: "metronome")
                }
                if let gct = viewModel.avgGroundContactTimeMs {
                    StatCard(title: "Ground Contact", value: gct.formattedGroundContact, icon: "shoeprints.fill")
                }
                if let stride = viewModel.avgStrideLengthMeters {
                    StatCard(title: "Stride", value: stride.formattedStride, icon: "ruler")
                }
                if let vertical = viewModel.avgVerticalOscillationCm {
                    StatCard(title: "Vert. Oscillation", value: vertical.formattedVerticalOscillation, icon: "arrow.up.and.down")
                }
                if let power = viewModel.avgRunningPowerWatts {
                    StatCard(title: "Power", value: power.formattedPower, icon: "bolt.fill")
                }
            }

            if let strokes = workout.strokeCount {
                StatCard(title: "Strokes", value: "\(strokes)", icon: "drop")
            }

            if let laps = workout.laps {
                StatCard(title: "Laps", value: "\(laps)", icon: "arrow.triangle.2.circlepath")
            }
        }
    }

    /// Active swim pace (seconds per 100m) derived from lap events, excluding
    /// rest time at the wall. Falls back to wall-clock pace when lap events
    /// aren't available.
    private var swimmingActivePacePer100m: Double? {
        let lapSegs = viewModel.segments
        if !lapSegs.isEmpty {
            let totalDist = lapSegs.reduce(0.0) { $0 + $1.distanceMeters }
            let totalDur = lapSegs.reduce(0.0) { $0 + $1.durationSeconds }
            if totalDist > 0, totalDur > 0 {
                return totalDur * (100.0 / totalDist)
            }
        }
        if let speed = workout.avgSpeedMps, speed > 0 {
            return 100.0 / speed
        }
        return nil
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// Two stacked charts sharing the same time domain. The top chart plots heart
/// rate over time; the bottom chart plots elevation. Stacking rather than
/// overlaying lets each metric keep its own y-scale while still allowing the
/// reader to visually correlate HR bumps with climbs.
///
/// Both charts share a single selection state so dragging across either one
/// shows a synchronized vertical rule and value callout on both.
struct TimeSeriesChart: View {
    let hrPoints: [WorkoutDetailViewModel.HeartRatePoint]
    let elevPoints: [WorkoutDetailViewModel.ElevationPoint]
    let powerPoints: [WorkoutDetailViewModel.PowerPoint]
    let totalDuration: Double

    @State private var selectedSeconds: Double?

    private var domain: ClosedRange<Double> {
        0 ... max(totalDuration, 1)
    }

    private var title: String { "Metrics" }

    private var selectedHR: Double? {
        guard let s = selectedSeconds, !hrPoints.isEmpty else { return nil }
        return hrPoints.min(by: { abs($0.secondsFromStart - s) < abs($1.secondsFromStart - s) })?.bpm
    }

    private var selectedElev: Double? {
        guard let s = selectedSeconds, !elevPoints.isEmpty else { return nil }
        return elevPoints.min(by: { abs($0.secondsFromStart - s) < abs($1.secondsFromStart - s) })?.meters
    }

    private var selectedPower: Double? {
        guard let s = selectedSeconds, !powerPoints.isEmpty else { return nil }
        return powerPoints.min(by: { abs($0.secondsFromStart - s) < abs($1.secondsFromStart - s) })?.watts
    }

    /// Whether this is the last (bottom) chart — used to decide which chart shows the x-axis.
    private var lastSeries: String {
        if !elevPoints.isEmpty { return "elev" }
        if !powerPoints.isEmpty { return "power" }
        return "hr"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                if let s = selectedSeconds {
                    HStack(spacing: 8) {
                        Label(Self.formatTime(s), systemImage: "clock")
                            .foregroundStyle(.secondary)
                        if let hr = selectedHR {
                            Label(String(format: "%.0f", hr), systemImage: "heart.fill")
                                .foregroundStyle(.red)
                        }
                        if let pw = selectedPower {
                            Label(String(format: "%.0f W", pw), systemImage: "bolt.fill")
                                .foregroundStyle(.green)
                        }
                        if let elev = selectedElev {
                            Label(String(format: "%.0f m", elev), systemImage: "mountain.2.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                    .font(.caption.bold().monospacedDigit())
                }
            }

            if !hrPoints.isEmpty {
                Label("Heart rate (bpm)", systemImage: "heart.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Chart {
                    ForEach(hrPoints) { point in
                        LineMark(
                            x: .value("Time", point.secondsFromStart),
                            y: .value("BPM", point.bpm)
                        )
                        .foregroundStyle(.red)
                        .interpolationMethod(.monotone)
                    }
                    if let s = selectedSeconds {
                        RuleMark(x: .value("Selected", s))
                            .foregroundStyle(.secondary.opacity(0.5))
                            .lineStyle(StrokeStyle(dash: [4, 3]))
                    }
                }
                .frame(height: 140)
                .chartXScale(domain: domain)
                .chartXAxis {
                    if lastSeries == "hr" {
                        AxisMarks(values: .automatic(desiredCount: 4)) { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let seconds = value.as(Double.self) {
                                    Text(Self.formatTime(seconds))
                                }
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartGesture { proxy in
                    DragGesture(minimumDistance: 16)
                        .onChanged { value in
                            let h = abs(value.translation.width)
                            let v = abs(value.translation.height)
                            guard h > v else { return }
                            if let seconds: Double = proxy.value(atX: value.location.x) {
                                selectedSeconds = seconds.clamped(to: domain)
                            }
                        }
                        .onEnded { _ in selectedSeconds = nil }
                }
            }

            if !powerPoints.isEmpty {
                Label("Power (W)", systemImage: "bolt.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Chart {
                    ForEach(powerPoints) { point in
                        LineMark(
                            x: .value("Time", point.secondsFromStart),
                            y: .value("Watts", point.watts)
                        )
                        .foregroundStyle(.green)
                        .interpolationMethod(.monotone)
                    }
                    if let s = selectedSeconds {
                        RuleMark(x: .value("Selected", s))
                            .foregroundStyle(.secondary.opacity(0.5))
                            .lineStyle(StrokeStyle(dash: [4, 3]))
                    }
                }
                .frame(height: 100)
                .chartXScale(domain: domain)
                .chartXAxis {
                    if lastSeries == "power" {
                        AxisMarks(values: .automatic(desiredCount: 4)) { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let seconds = value.as(Double.self) {
                                    Text(Self.formatTime(seconds))
                                }
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartGesture { proxy in
                    DragGesture(minimumDistance: 16)
                        .onChanged { value in
                            let h = abs(value.translation.width)
                            let v = abs(value.translation.height)
                            guard h > v else { return }
                            if let seconds: Double = proxy.value(atX: value.location.x) {
                                selectedSeconds = seconds.clamped(to: domain)
                            }
                        }
                        .onEnded { _ in selectedSeconds = nil }
                }
            }

            if !elevPoints.isEmpty {
                Label("Elevation (m)", systemImage: "mountain.2.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Chart {
                    ForEach(elevPoints) { point in
                        AreaMark(
                            x: .value("Time", point.secondsFromStart),
                            y: .value("Meters", point.meters)
                        )
                        .foregroundStyle(Color.blue.opacity(0.25))
                        .interpolationMethod(.monotone)

                        LineMark(
                            x: .value("Time", point.secondsFromStart),
                            y: .value("Meters", point.meters)
                        )
                        .foregroundStyle(.blue)
                        .interpolationMethod(.monotone)
                    }
                    if let s = selectedSeconds {
                        RuleMark(x: .value("Selected", s))
                            .foregroundStyle(.secondary.opacity(0.5))
                            .lineStyle(StrokeStyle(dash: [4, 3]))
                    }
                }
                .frame(height: 90)
                .chartXScale(domain: domain)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let seconds = value.as(Double.self) {
                                Text(Self.formatTime(seconds))
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartGesture { proxy in
                    DragGesture(minimumDistance: 16)
                        .onChanged { value in
                            let h = abs(value.translation.width)
                            let v = abs(value.translation.height)
                            guard h > v else { return }
                            if let seconds: Double = proxy.value(atX: value.location.x) {
                                selectedSeconds = seconds.clamped(to: domain)
                            }
                        }
                        .onEnded { _ in selectedSeconds = nil }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private static func formatTime(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

struct SegmentBreakdownView: View {
    let segments: [WorkoutDetailViewModel.WorkoutSegment]
    let workoutType: WorkoutType

    private var unitDistance: Double {
        workoutType == .swimming ? 100.0 : 1000.0
    }

    private var hasHR: Bool {
        segments.contains { $0.avgHeartRate != nil }
    }

    private var hasElevation: Bool {
        workoutType != .swimming && segments.contains { $0.elevationChange != nil }
    }

    private var hasPower: Bool {
        segments.contains { $0.avgPower != nil }
    }

    private var hasStrokes: Bool {
        workoutType == .swimming && segments.contains { $0.strokeCount != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Splits")
                .font(.headline)

            // Header row
            HStack(spacing: 0) {
                Text(workoutType == .swimming ? "Lap" : "km")
                    .frame(width: 44, alignment: .leading)
                    .lineLimit(1)
                if workoutType == .swimming {
                    Text("Time")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text("Pace")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                } else {
                    Text(workoutType == .cycling ? "Speed" : "Pace")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                if hasHR {
                    Text("HR")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                if hasPower {
                    Text("Power")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                if hasStrokes {
                    Text("Strokes")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                if hasElevation {
                    Text("Elev")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .font(.caption.bold())
            .foregroundStyle(.secondary)

            Divider()

            // Data rows
            ForEach(segments) { seg in
                HStack(spacing: 0) {
                    Text(seg.label)
                        .frame(width: 44, alignment: .leading)
                        .lineLimit(1)
                        .fontWeight(.medium)

                    if workoutType == .swimming {
                        Text(formatLapTime(seg.durationSeconds))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Text(swimPacePer100m(for: seg))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    } else {
                        Text(paceOrSpeed(for: seg))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    if hasHR {
                        Text(seg.avgHeartRate.map { String(format: "%.0f", $0) } ?? "–")
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    if hasPower {
                        Text(seg.avgPower.map { String(format: "%.0f W", $0) } ?? "–")
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    if hasStrokes {
                        Text(seg.strokeCount.map { "\($0)" } ?? "–")
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    if hasElevation {
                        Text(seg.elevationChange.map { formatElevChange($0) } ?? "–")
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .font(.subheadline.monospacedDigit())
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func paceOrSpeed(for seg: WorkoutDetailViewModel.WorkoutSegment) -> String {
        guard seg.distanceMeters > 0, seg.durationSeconds > 0 else { return "–" }
        if workoutType == .cycling {
            let kmh = (seg.distanceMeters / seg.durationSeconds) * 3.6
            return String(format: "%.1f km/h", kmh)
        } else {
            let pace = seg.durationSeconds * (unitDistance / seg.distanceMeters)
            let m = Int(pace) / 60
            let s = Int(pace) % 60
            return String(format: "%d'%02d\"", m, s)
        }
    }

    private func formatLapTime(_ seconds: Double) -> String {
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        if m > 0 {
            return String(format: "%d:%02d", m, s)
        }
        return String(format: "0:%02d", s)
    }

    private func swimPacePer100m(for seg: WorkoutDetailViewModel.WorkoutSegment) -> String {
        guard seg.distanceMeters > 0, seg.durationSeconds > 0 else { return "–" }
        let pacePer100m = seg.durationSeconds * (100.0 / seg.distanceMeters)
        let m = Int(pacePer100m) / 60
        let s = Int(pacePer100m) % 60
        return String(format: "%d'%02d\"", m, s)
    }

    private func formatElevChange(_ meters: Double) -> String {
        if meters >= 0 {
            return String(format: "+%.0f m", meters)
        } else {
            return String(format: "%.0f m", meters)
        }
    }
}

private struct RouteMapSection: View {
    let routePoints: [RoutePoint]
    @State private var showFullMap = false

    private var coordinates: [CLLocationCoordinate2D] {
        routePoints.map(\.coordinate)
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text("Route")
                .font(.headline)

            Map(interactionModes: []) {
                MapPolyline(coordinates: coordinates)
                    .stroke(.blue, lineWidth: 4)
            }
            .mapStyle(.standard(elevation: .realistic))
            .frame(height: 250)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: Alignment.topTrailing) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption.bold())
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(8)
            }
            .onTapGesture { showFullMap = true }
        }
        .fullScreenCover(isPresented: $showFullMap) {
            NavigationStack {
                Map {
                    MapPolyline(coordinates: coordinates)
                        .stroke(.blue, lineWidth: 4)
                }
                .mapStyle(.standard(elevation: .realistic))
                .navigationTitle("Route")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showFullMap = false }
                    }
                }
            }
        }
    }
}
