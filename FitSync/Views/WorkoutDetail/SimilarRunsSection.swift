import SwiftUI
import Charts

struct SimilarRunsSection: View {
    let similarWorkouts: [Workout]
    let currentWorkout: Workout

    private static let previewCount = 5

    private var allRuns: [Workout] {
        (similarWorkouts + [currentWorkout]).sorted { $0.startDate > $1.startDate }
    }

    /// PR = fastest pace (sec/km), not lowest total duration — distances vary
    /// within the similarity window so comparing raw duration is apples-to-oranges.
    private var prWorkout: Workout? {
        allRuns.compactMap { w -> (Workout, Double)? in
            guard let pace = pacePerKm(w) else { return nil }
            return (w, pace)
        }
        .min { $0.1 < $1.1 }?.0
    }

    private var currentRank: Int? {
        let byPace = allRuns
            .compactMap { w -> (Workout, Double)? in
                guard let p = pacePerKm(w) else { return nil }
                return (w, p)
            }
            .sorted { $0.1 < $1.1 }
        return byPace.firstIndex { $0.0.healthKitUUID == currentWorkout.healthKitUUID }.map { $0 + 1 }
    }

    private var rankableCount: Int {
        allRuns.filter { pacePerKm($0) != nil }.count
    }

    private func pacePerKm(_ w: Workout) -> Double? {
        if let p = w.avgPaceSecondsPerKm { return p }
        guard let m = w.distanceMeters, m > 0 else { return nil }
        return w.durationSeconds / (m / 1000.0)
    }

    private var previewRuns: [Workout] {
        let past = allRuns.filter { $0.healthKitUUID != currentWorkout.healthKitUUID }
        return Array(past.prefix(Self.previewCount))
    }

    private var hasMoreThanPreview: Bool {
        similarWorkouts.count > Self.previewCount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            statsRow

            Divider()

            VStack(spacing: 0) {
                ForEach(previewRuns, id: \.healthKitUUID) { run in
                    NavigationLink(value: run) {
                        runCard(run: run, isPR: run.healthKitUUID == prWorkout?.healthKitUUID)
                    }
                    .buttonStyle(.plain)

                    if run.healthKitUUID != previewRuns.last?.healthKitUUID {
                        Divider().padding(.leading, 12)
                    }
                }
            }

            if hasMoreThanPreview {
                NavigationLink {
                    AllSimilarRunsView(
                        similarWorkouts: similarWorkouts,
                        currentWorkout: currentWorkout,
                        prWorkoutUUID: prWorkout?.healthKitUUID
                    )
                } label: {
                    HStack {
                        Text("See all \(similarWorkouts.count) similar runs")
                            .font(.subheadline.bold())
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                    }
                    .foregroundStyle(Color.accentColor)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: "repeat")
                .foregroundStyle(Color.accentColor)
            Text("Similar Runs")
                .font(.headline)
            Spacer()
            Text("\(similarWorkouts.count)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.accentColor)
                .clipShape(Capsule())
        }
    }

    // MARK: - Stats row

    private var statsRow: some View {
        HStack(spacing: 12) {
            if let rank = currentRank, rankableCount > 1 {
                statCell(
                    label: "Pace rank",
                    value: "\(ordinal(rank))",
                    sub: "of \(rankableCount)",
                    tint: rank == 1 ? .yellow : Color.accentColor
                )
            }
            if let pr = prWorkout, let prPace = pacePerKm(pr) {
                statCell(
                    label: "Best pace",
                    value: formatPace(prPace),
                    sub: pr.startDate.formatted(.dateTime.month(.abbreviated).day().year(.twoDigits)),
                    tint: .yellow
                )
            }
            statCell(
                label: "This run",
                value: pacePerKm(currentWorkout).map { formatPace($0) } ?? "–",
                sub: formatDuration(currentWorkout.durationSeconds),
                tint: Color.accentColor
            )
        }
    }

    private func statCell(label: String, value: String, sub: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title3, design: .rounded).bold().monospacedDigit())
                .foregroundStyle(tint)
            Text(sub)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Run card (list row)

    private func runCard(run: Workout, isPR: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(run.startDate.formatted(.dateTime.month(.abbreviated).day().year(.twoDigits)))
                        .font(.subheadline.bold())
                    if isPR {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                }
                HStack(spacing: 10) {
                    if let pace = run.avgPaceSecondsPerKm {
                        Label(formatPace(pace), systemImage: "speedometer")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let hr = run.cachedAvgHeartRate {
                        Label(String(format: "%.0f", hr), systemImage: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatDuration(run.durationSeconds))
                    .font(.subheadline.bold().monospacedDigit())
                if let runPace = pacePerKm(run), let curPace = pacePerKm(currentWorkout) {
                    let delta = runPace - curPace
                    Text(formatPaceDelta(delta))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(delta <= 0 ? .green : .orange)
                }
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 2)
        .contentShape(Rectangle())
    }

    // MARK: - Formatting

    fileprivate static func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    fileprivate static func formatPace(_ secsPerKm: Double) -> String {
        let m = Int(secsPerKm) / 60
        let s = Int(secsPerKm) % 60
        return String(format: "%d'%02d\"/km", m, s)
    }

    fileprivate static func formatPaceDelta(_ secsPerKm: Double) -> String {
        let sign = secsPerKm <= 0 ? "" : "+"
        let a = abs(Int(secsPerKm.rounded()))
        let m = a / 60
        let s = a % 60
        let suffix = "/km"
        if m > 0 { return String(format: "%@%d:%02d%@", sign, m, s, suffix) }
        return String(format: "%@%ds%@", sign, s, suffix)
    }

    private func formatDuration(_ seconds: Double) -> String { Self.formatDuration(seconds) }
    private func formatPace(_ secsPerKm: Double) -> String { Self.formatPace(secsPerKm) }
    private func formatPaceDelta(_ secsPerKm: Double) -> String { Self.formatPaceDelta(secsPerKm) }

    private func ordinal(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .ordinal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

// MARK: - Full list screen

struct AllSimilarRunsView: View {
    let similarWorkouts: [Workout]
    let currentWorkout: Workout
    let prWorkoutUUID: String?

    enum SortOrder: String, CaseIterable, Identifiable {
        case recent = "Most recent"
        case fastestPace = "Fastest pace"
        case slowestPace = "Slowest pace"
        var id: String { rawValue }
    }

    @State private var sort: SortOrder = .recent

    private var allRuns: [Workout] {
        similarWorkouts + [currentWorkout]
    }

    private func pacePerKm(_ w: Workout) -> Double? {
        if let p = w.avgPaceSecondsPerKm { return p }
        guard let m = w.distanceMeters, m > 0 else { return nil }
        return w.durationSeconds / (m / 1000.0)
    }

    private var sortedRuns: [Workout] {
        switch sort {
        case .recent:
            return similarWorkouts.sorted { $0.startDate > $1.startDate }
        case .fastestPace:
            return similarWorkouts.sorted {
                (pacePerKm($0) ?? .greatestFiniteMagnitude) < (pacePerKm($1) ?? .greatestFiniteMagnitude)
            }
        case .slowestPace:
            return similarWorkouts.sorted {
                (pacePerKm($0) ?? 0) > (pacePerKm($1) ?? 0)
            }
        }
    }

    var body: some View {
        List {
            if allRuns.count > 1 {
                Section {
                    chart
                        .frame(height: 180)
                        .padding(.vertical, 8)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                } header: {
                    Text("Duration over time")
                }
            }

            Section {
                HStack {
                    Image(systemName: "flag.checkered")
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("This Run")
                            .font(.caption.bold())
                            .foregroundStyle(Color.accentColor)
                        Text(currentWorkout.startDate.formatted(.dateTime.month(.abbreviated).day().year()))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(SimilarRunsSection.formatDuration(currentWorkout.durationSeconds))
                        .font(.subheadline.bold().monospacedDigit())
                }
            }

            Section {
                ForEach(sortedRuns, id: \.healthKitUUID) { run in
                    NavigationLink(value: run) {
                        row(run: run)
                    }
                }
            } header: {
                HStack {
                    Text("\(similarWorkouts.count) similar runs")
                    Spacer()
                    Picker("", selection: $sort) {
                        ForEach(SortOrder.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
            }
        }
        .navigationTitle("Similar Runs")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var chart: some View {
        Chart {
            ForEach(allRuns, id: \.healthKitUUID) { w in
                let isCurrent = w.healthKitUUID == currentWorkout.healthKitUUID
                let isPR = w.healthKitUUID == prWorkoutUUID

                PointMark(
                    x: .value("Date", w.startDate),
                    y: .value("Duration", w.durationSeconds / 60)
                )
                .foregroundStyle(
                    isCurrent ? Color.accentColor :
                    (isPR ? Color.yellow : Color.secondary.opacity(0.55))
                )
                .symbol(isPR ? .asterisk : .circle)
                .symbolSize(isCurrent ? 160 : (isPR ? 200 : 70))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let m = value.as(Double.self) {
                        Text("\(Int(m))m").font(.caption2)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
                    .font(.caption2)
            }
        }
    }

    private func row(run: Workout) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(run.startDate.formatted(.dateTime.month(.abbreviated).day().year(.twoDigits)))
                        .font(.subheadline.bold())
                    if run.healthKitUUID == prWorkoutUUID {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                }
                HStack(spacing: 10) {
                    if let pace = run.avgPaceSecondsPerKm {
                        Text(SimilarRunsSection.formatPace(pace))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let hr = run.cachedAvgHeartRate {
                        Label(String(format: "%.0f", hr), systemImage: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(SimilarRunsSection.formatDuration(run.durationSeconds))
                    .font(.subheadline.bold().monospacedDigit())
                if let runPace = pacePerKm(run), let curPace = pacePerKm(currentWorkout) {
                    let delta = runPace - curPace
                    Text(SimilarRunsSection.formatPaceDelta(delta))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(delta <= 0 ? .green : .orange)
                }
            }
        }
    }
}
