import Foundation
import HealthKit

/// `@MainActor`-isolated so that every access to the SwiftData `@Model` workout
/// and every mutation of `@Observable` state happens on the main actor.
/// Reading `@Model` properties off-main is undefined in SwiftData and, in
/// practice, produces garbage values — e.g., `workout.startDate` returning the
/// wrong date means the HR chart's x coordinates land outside the chart domain
/// and the line silently disappears.
@MainActor
@Observable
final class WorkoutDetailViewModel {
    let workout: Workout
    private let store = HKHealthStore()

    /// The underlying HealthKit workout, fetched by UUID on demand. Needed for
    /// source filtering: queries like step count otherwise pick up samples
    /// from both the iPhone pedometer and the Apple Watch for the same time
    /// window and double-count them.
    private var hkWorkout: HKWorkout?

    struct HeartRatePoint: Identifiable {
        let id = UUID()
        let secondsFromStart: Double
        let bpm: Double
    }

    struct ElevationPoint: Identifiable {
        let id = UUID()
        let secondsFromStart: Double
        let meters: Double
    }

    // Time-series for the combined chart
    var heartRatePoints: [HeartRatePoint] = []
    var elevationPoints: [ElevationPoint] = []

    // Running-only aggregates loaded from HealthKit
    var avgHeartRate: Double?
    var maxHeartRate: Double?
    var avgGroundContactTimeMs: Double?
    var avgCadenceSpm: Double?
    var avgStrideLengthMeters: Double?
    var avgVerticalOscillationCm: Double?
    var avgRunningPowerWatts: Double?

    var isLoading = false

    init(workout: Workout) {
        self.workout = workout
    }

    var hasHeartRateSeries: Bool { !heartRatePoints.isEmpty }
    var hasElevationSeries: Bool { !elevationPoints.isEmpty }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        loadElevation()
        await loadHKWorkout()
        await loadHeartRate()

        if workout.type == .running {
            await loadRunningMetrics()
        }
    }

    // MARK: - Elevation (from persisted route points)

    private func loadElevation() {
        let start = workout.startDate
        elevationPoints = workout.sortedRoutePoints.map {
            ElevationPoint(
                secondsFromStart: $0.timestamp.timeIntervalSince(start),
                meters: $0.altitude
            )
        }
    }

    // MARK: - HK workout lookup

    private func loadHKWorkout() async {
        guard hkWorkout == nil,
              let uuid = UUID(uuidString: workout.healthKitUUID) else { return }
        let uuidPredicate = HKQuery.predicateForObjects(with: Set([uuid]))
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(uuidPredicate)],
            sortDescriptors: []
        )
        hkWorkout = try? await descriptor.result(for: store).first
    }

    // MARK: - Heart rate

    private func loadHeartRate() async {
        let type = HKQuantityType(.heartRate)
        let unit = HKUnit.count().unitDivided(by: .minute())
        guard let samples = try? await fetchSamples(type: type) else { return }

        let start = workout.startDate
        heartRatePoints = samples.map { sample in
            HeartRatePoint(
                secondsFromStart: sample.startDate.timeIntervalSince(start),
                bpm: sample.quantity.doubleValue(for: unit)
            )
        }
        let values = heartRatePoints.map(\.bpm)
        avgHeartRate = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        maxHeartRate = values.max()
    }

    // MARK: - Running-only metrics

    private func loadRunningMetrics() async {
        async let gct: Double? = averageSampleValue(
            type: HKQuantityType(.runningGroundContactTime),
            unit: .secondUnit(with: .milli)
        )
        async let stride: Double? = averageSampleValue(
            type: HKQuantityType(.runningStrideLength),
            unit: .meter()
        )
        async let vertical: Double? = averageSampleValue(
            type: HKQuantityType(.runningVerticalOscillation),
            unit: .meterUnit(with: .centi)
        )
        async let power: Double? = averageSampleValue(
            type: HKQuantityType(.runningPower),
            unit: HKUnit(from: "W")
        )
        async let cadence: Double? = computeCadence()

        avgGroundContactTimeMs = await gct
        avgStrideLengthMeters = await stride
        avgVerticalOscillationCm = await vertical
        avgRunningPowerWatts = await power
        avgCadenceSpm = await cadence
    }

    private func computeCadence() async -> Double? {
        guard workout.durationSeconds > 0 else { return nil }
        // Source-filter to the workout's own source (typically Apple Watch) so
        // we don't double-count iPhone pedometer samples for the same window.
        guard let samples = try? await fetchSamples(
            type: HKQuantityType(.stepCount),
            sourceFilterToWorkout: true
        ) else {
            return nil
        }
        let totalSteps = samples.reduce(0.0) { $0 + $1.quantity.doubleValue(for: .count()) }
        guard totalSteps > 0 else { return nil }
        return totalSteps / (workout.durationSeconds / 60.0)
    }

    // MARK: - HealthKit helpers

    private func fetchSamples(
        type: HKQuantityType,
        sourceFilterToWorkout: Bool = false
    ) async throws -> [HKQuantitySample] {
        var predicates: [NSPredicate] = [
            HKQuery.predicateForSamples(
                withStart: workout.startDate,
                end: workout.endDate
            )
        ]
        if sourceFilterToWorkout, let source = hkWorkout?.sourceRevision.source {
            predicates.append(HKQuery.predicateForObjects(from: [source]))
        }
        let compound = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: compound)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        return try await descriptor.result(for: store)
    }

    private func averageSampleValue(type: HKQuantityType, unit: HKUnit) async -> Double? {
        guard let samples = try? await fetchSamples(type: type), !samples.isEmpty else {
            return nil
        }
        let values = samples.map { $0.quantity.doubleValue(for: unit) }
        return values.reduce(0, +) / Double(values.count)
    }
}
