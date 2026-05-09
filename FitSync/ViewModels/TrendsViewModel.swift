import Foundation

@MainActor
@Observable
final class TrendsViewModel {
    private let repository: WorkoutRepository
    private let healthKit: HealthKitService

    static let weeksWindow = 12

    var selectedType: WorkoutType? = nil

    // Per-week stacked duration (All tab)
    struct DurationBySport: Identifiable {
        var id: String { "\(weekStart.timeIntervalSince1970)-\(type.rawValue)" }
        let weekStart: Date
        let minutes: Double
        let type: WorkoutType
    }
    var durationBySport: [DurationBySport] = []

    // Per-sport basic weekly totals (selected sport)
    var weeklyData: [WorkoutRepository.WeeklyData] = []

    // Per-sport granular metrics (selected sport). Each is a weekly avg.
    struct MetricPoint: Identifiable {
        let id = UUID()
        let weekStart: Date
        let value: Double
    }

    // Running
    var runningCadence: [MetricPoint] = []
    var runningGCT: [MetricPoint] = []
    var runningStride: [MetricPoint] = []

    // Cycling
    var cyclingPower: [MetricPoint] = []
    var cyclingSpeedKmh: [MetricPoint] = []

    // Swimming
    var swimmingPacePer100m: [MetricPoint] = []
    var swimmingStrokesPerWorkout: [MetricPoint] = []

    // Cardio health (All tab only)
    var vo2MaxSamples: [HealthKitService.VO2MaxSample] = []
    var restingHRSamples: [HealthKitService.RestingHRSample] = []
    var hrvSamples: [HealthKitService.HRVSample] = []

    var latestVO2Max: Double? { vo2MaxSamples.last?.value }
    var vo2MaxDelta: Double? {
        guard let latest = vo2MaxSamples.last?.value,
              let baseline = vo2MaxSamples.first?.value,
              vo2MaxSamples.count >= 2 else { return nil }
        return latest - baseline
    }

    var latestRestingHR: Double? { restingHRSamples.last?.bpm }
    var restingHRDelta: Double? {
        guard let latest = restingHRSamples.last?.bpm,
              let baseline = restingHRSamples.first?.bpm,
              restingHRSamples.count >= 2 else { return nil }
        return latest - baseline
    }

    var latestHRV: Double? { hrvSamples.last?.ms }
    var hrvDelta: Double? {
        guard let latest = hrvSamples.last?.ms,
              let baseline = hrvSamples.first?.ms,
              hrvSamples.count >= 2 else { return nil }
        return latest - baseline
    }

    init(repository: WorkoutRepository, healthKit: HealthKitService) {
        self.repository = repository
        self.healthKit = healthKit
    }

    func load() {
        reloadForSelection()
    }

    func selectType(_ type: WorkoutType?) {
        selectedType = type
        reloadForSelection()
    }

    private func reloadForSelection() {
        if let type = selectedType {
            durationBySport = []
            weeklyData = repository.weeklyTotals(weeks: Self.weeksWindow, type: type)
            loadSportMetrics(for: type)
            vo2MaxSamples = []
            restingHRSamples = []
            hrvSamples = []
        } else {
            loadDurationBySport()
            weeklyData = []
            clearSportMetrics()
            Task { await loadCardioHealth() }
        }
    }

    // MARK: - All tab

    private func loadDurationBySport() {
        var result: [DurationBySport] = []
        for type in WorkoutType.allCases {
            let data = repository.weeklyTotals(weeks: Self.weeksWindow, type: type)
            for entry in data where entry.totalDurationMinutes > 0 {
                result.append(DurationBySport(
                    weekStart: entry.weekStart,
                    minutes: entry.totalDurationMinutes,
                    type: type
                ))
            }
        }
        durationBySport = result
    }

    private func loadCardioHealth() async {
        let oneYearAgo = Calendar.current.date(byAdding: .month, value: -12, to: .now) ?? .now
        async let vo2 = healthKit.fetchVO2MaxSamples(from: oneYearAgo)
        async let rhr = healthKit.fetchRestingHeartRate(from: oneYearAgo)
        async let hrv = healthKit.fetchHRV(from: oneYearAgo)
        vo2MaxSamples = (try? await vo2) ?? []
        restingHRSamples = (try? await rhr) ?? []
        hrvSamples = (try? await hrv) ?? []
    }

    // MARK: - Per-sport metrics

    private func clearSportMetrics() {
        runningCadence = []
        runningGCT = []
        runningStride = []
        cyclingPower = []
        cyclingSpeedKmh = []
        swimmingPacePer100m = []
        swimmingStrokesPerWorkout = []
    }

    private func loadSportMetrics(for type: WorkoutType) {
        clearSportMetrics()
        let calendar = Calendar.current
        let now = Date.now
        guard let windowStart = calendar.date(byAdding: .weekOfYear, value: -(Self.weeksWindow - 1), to: now) else {
            return
        }
        let startOfWindow = calendar.dateInterval(of: .weekOfYear, for: windowStart)?.start ?? windowStart

        // Single fetch, bucketed client-side.
        let workouts = repository.fetchWorkouts(type: type)
            .filter { $0.startDate >= startOfWindow }

        // Build week buckets
        var buckets: [Date: [Workout]] = [:]
        for w in workouts {
            guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: w.startDate)?.start else { continue }
            buckets[weekStart, default: []].append(w)
        }

        let sortedWeeks = buckets.keys.sorted()

        switch type {
        case .running:
            runningCadence = Self.weeklyAvg(weeks: sortedWeeks, buckets: buckets) { $0.cachedAvgCadenceSpm }
            runningGCT = Self.weeklyAvg(weeks: sortedWeeks, buckets: buckets) { $0.cachedAvgGroundContactTimeMs }
            runningStride = Self.weeklyAvg(weeks: sortedWeeks, buckets: buckets) { $0.cachedAvgStrideLengthMeters }
        case .cycling:
            cyclingPower = Self.weeklyAvg(weeks: sortedWeeks, buckets: buckets) { $0.cachedAvgPowerWatts }
            cyclingSpeedKmh = Self.weeklyAvg(weeks: sortedWeeks, buckets: buckets) {
                $0.avgSpeedMps.map { $0 * 3.6 }
            }
        case .swimming:
            swimmingPacePer100m = Self.weeklyAvg(weeks: sortedWeeks, buckets: buckets) {
                guard let speed = $0.avgSpeedMps, speed > 0 else { return nil }
                return 100.0 / speed
            }
            swimmingStrokesPerWorkout = Self.weeklyAvg(weeks: sortedWeeks, buckets: buckets) {
                $0.strokeCount.map { Double($0) }
            }
        }
    }

    private static func weeklyAvg(
        weeks: [Date],
        buckets: [Date: [Workout]],
        extract: (Workout) -> Double?
    ) -> [MetricPoint] {
        weeks.compactMap { week in
            let values = (buckets[week] ?? []).compactMap(extract)
            guard !values.isEmpty else { return nil }
            let avg = values.reduce(0, +) / Double(values.count)
            return MetricPoint(weekStart: week, value: avg)
        }
    }
}
