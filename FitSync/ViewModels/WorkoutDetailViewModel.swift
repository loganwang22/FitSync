import Foundation
import HealthKit
import CoreLocation

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

    struct PowerPoint: Identifiable {
        let id = UUID()
        let secondsFromStart: Double
        let watts: Double
    }

    struct WorkoutSegment: Identifiable {
        let id: Int
        let startTime: Date
        let endTime: Date
        let distanceMeters: Double
        let durationSeconds: Double
        var avgHeartRate: Double?
        var elevationChange: Double?
        var avgPower: Double?

        var label: String { "\(id + 1)" }
    }

    // Cached route points (sorted once to avoid repeated O(n log n) sorts)
    var cachedRoutePoints: [RoutePoint] = []

    // Time-series for the combined chart
    var heartRatePoints: [HeartRatePoint] = []
    var elevationPoints: [ElevationPoint] = []
    var powerPoints: [PowerPoint] = []
    var segments: [WorkoutSegment] = []

    // Aggregates
    var avgHeartRate: Double?
    var maxHeartRate: Double?
    var avgPowerWatts: Double?
    var maxPowerWatts: Double?
    var avgGroundContactTimeMs: Double?
    var avgCadenceSpm: Double?
    var avgStrideLengthMeters: Double?
    var avgVerticalOscillationCm: Double?
    var avgRunningPowerWatts: Double?

    var isLoading = false

    // Similar workouts (matched runs)
    var similarWorkouts: [Workout] = []
    private var repository: WorkoutRepository?

    init(workout: Workout) {
        self.workout = workout
    }

    func setRepository(_ repo: WorkoutRepository) {
        self.repository = repo
    }

    var hasHeartRateSeries: Bool { !heartRatePoints.isEmpty }
    var hasElevationSeries: Bool { !elevationPoints.isEmpty }
    var hasPowerSeries: Bool { !powerPoints.isEmpty }
    var hasRoute: Bool { !cachedRoutePoints.isEmpty }
    var isRouteLoaded = false

    // MARK: - Public API

    func load() async {
        guard !isLoading else { return }
        isLoading = true

        // Load stats/charts immediately (from cache or HealthKit)
        if workout.detailCacheDate != nil {
            loadFromCache()
        } else {
            await fetchFromHealthKit()
            saveToCache()
        }

        // For swimming, fetch real lap events from HKWorkout (needs HK lookup)
        if workout.type == .swimming && swimmingLapEvents.isEmpty {
            await loadHKWorkout()
            loadSwimmingLaps()
        }

        // Compute segments without route data first (even segments for swimming,
        // or partial for GPS workouts until route loads)
        computeSegments()
        isLoading = false

        // Fire-and-forget: load route points after UI is already showing
        if workout.type != .swimming {
            Task { await loadRouteData() }
        }
    }

    /// Clears cached data and re-fetches everything from HealthKit.
    func resync() async {
        guard !isLoading else { return }
        isLoading = true

        await fetchFromHealthKit()
        saveToCache()
        computeSegments()
        isLoading = false

        if workout.type != .swimming {
            Task { await loadRouteData() }
        }
    }

    private func loadRouteData() async {
        cachedRoutePoints = workout.sortedRoutePoints

        // If no route points were persisted during initial sync (e.g. HealthKit
        // hadn't finished processing the route yet), try fetching from HK now.
        if cachedRoutePoints.isEmpty {
            await fetchRouteFromHealthKit()
        }

        // Backfill start/end coordinates for route matching
        backfillStartEndCoordinates()

        isRouteLoaded = true

        if workout.type != .swimming {
            loadElevation()
        }

        // Recompute segments with GPS data + HR/power assignment
        computeSegments()

        // Find similar workouts (matched runs)
        if workout.type == .running, let repo = repository {
            similarWorkouts = repo.findSimilarWorkouts(to: workout)
        }
    }

    /// Fetches route data directly from HealthKit and persists it to SwiftData.
    private func fetchRouteFromHealthKit() async {
        await loadHKWorkout()
        guard let hkw = hkWorkout else { return }

        let routeType = HKSeriesType.workoutRoute()
        let predicate = HKQuery.predicateForObjects(from: hkw)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.sample(type: routeType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        guard let route = (try? await descriptor.result(for: store))?.first as? HKWorkoutRoute else {
            return
        }

        let locations: [CLLocation] = await withCheckedContinuation { continuation in
            var all: [CLLocation] = []
            let query = HKWorkoutRouteQuery(route: route) { _, locs, done, error in
                if let locs { all.append(contentsOf: locs) }
                if done || error != nil {
                    continuation.resume(returning: all)
                }
            }
            store.execute(query)
        }

        guard !locations.isEmpty else { return }
        let routePoints = locations.map { RoutePoint(from: $0) }
        workout.routePoints = routePoints
        workout.hasMap = true

        // Backfill elevation gain if missing
        if workout.elevationGainMeters == nil,
           workout.type == .running || workout.type == .cycling {
            let gains = zip(locations.dropFirst(), locations).reduce(0.0) { sum, pair in
                let delta = pair.0.altitude - pair.1.altitude
                return delta > 0 ? sum + delta : sum
            }
            if gains > 0 { workout.elevationGainMeters = gains }
        }

        cachedRoutePoints = routePoints.sorted { $0.timestamp < $1.timestamp }
    }

    private func backfillStartEndCoordinates() {
        guard workout.startLatitude == nil, !cachedRoutePoints.isEmpty else { return }
        let first = cachedRoutePoints.first!
        let last = cachedRoutePoints.last!
        workout.startLatitude = first.latitude
        workout.startLongitude = first.longitude
        workout.endLatitude = last.latitude
        workout.endLongitude = last.longitude
    }

    // MARK: - Cache read/write

    private func loadFromCache() {
        avgHeartRate = workout.cachedAvgHeartRate
        maxHeartRate = workout.cachedMaxHeartRate
        avgPowerWatts = workout.cachedAvgPowerWatts
        maxPowerWatts = workout.cachedMaxPowerWatts
        avgCadenceSpm = workout.cachedAvgCadenceSpm
        avgGroundContactTimeMs = workout.cachedAvgGroundContactTimeMs
        avgStrideLengthMeters = workout.cachedAvgStrideLengthMeters
        avgVerticalOscillationCm = workout.cachedAvgVerticalOscillationCm
        avgRunningPowerWatts = workout.cachedAvgRunningPowerWatts

        if let cached = workout.cachedHeartRateSeries {
            heartRatePoints = cached.map {
                HeartRatePoint(secondsFromStart: $0.t, bpm: $0.v)
            }
        }
        if let cached = workout.cachedPowerSeries {
            powerPoints = cached.map {
                PowerPoint(secondsFromStart: $0.t, watts: $0.v)
            }
        }
    }

    private func saveToCache() {
        workout.cachedAvgHeartRate = avgHeartRate
        workout.cachedMaxHeartRate = maxHeartRate
        workout.cachedAvgPowerWatts = avgPowerWatts
        workout.cachedMaxPowerWatts = maxPowerWatts
        workout.cachedAvgCadenceSpm = avgCadenceSpm
        workout.cachedAvgGroundContactTimeMs = avgGroundContactTimeMs
        workout.cachedAvgStrideLengthMeters = avgStrideLengthMeters
        workout.cachedAvgVerticalOscillationCm = avgVerticalOscillationCm
        workout.cachedAvgRunningPowerWatts = avgRunningPowerWatts

        workout.cachedHeartRateSeries = heartRatePoints.map {
            Workout.CachedTimePoint(t: $0.secondsFromStart, v: $0.bpm)
        }
        workout.cachedPowerSeries = powerPoints.isEmpty ? nil : powerPoints.map {
            Workout.CachedTimePoint(t: $0.secondsFromStart, v: $0.watts)
        }

        workout.detailCacheDate = .now
    }

    // MARK: - HealthKit fetching

    private func fetchFromHealthKit() async {
        await loadHKWorkout()
        await loadHeartRate()

        if workout.type == .running {
            await loadRunningMetrics()
        }
        if workout.type == .cycling {
            await loadCyclingPower()
        }
        if workout.type == .swimming {
            loadSwimmingLaps()
        }
    }

    // MARK: - Elevation (from persisted route points)

    private func loadElevation() {
        let start = workout.startDate
        elevationPoints = cachedRoutePoints.map {
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

    // MARK: - Cycling power

    private func loadCyclingPower() async {
        let type = HKQuantityType(.cyclingPower)
        let unit = HKUnit(from: "W")
        guard let samples = try? await fetchSamples(type: type) else { return }

        let start = workout.startDate
        powerPoints = samples.map { sample in
            PowerPoint(
                secondsFromStart: sample.startDate.timeIntervalSince(start),
                watts: sample.quantity.doubleValue(for: unit)
            )
        }
        let values = powerPoints.map(\.watts)
        avgPowerWatts = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        maxPowerWatts = values.max()
    }

    // MARK: - Swimming lap events

    private var swimmingLapEvents: [HKWorkoutEvent] = []

    private func loadSwimmingLaps() {
        guard workout.type == .swimming, let hkw = hkWorkout else { return }
        swimmingLapEvents = (hkw.workoutEvents ?? [])
            .filter { $0.type == .lap }
            .sorted { $0.dateInterval.start < $1.dateInterval.start }
    }

    // MARK: - Per-distance segments (splits)

    private func computeSegments() {
        let segmentDistance: Double = workout.type == .swimming ? 100.0 : 1000.0

        if workout.type == .swimming && !swimmingLapEvents.isEmpty {
            computeSwimmingLapSegments()
        } else if cachedRoutePoints.isEmpty {
            computeEvenSegments(segmentDistance: segmentDistance)
        } else {
            computeGPSSegments(segmentDistance: segmentDistance)
        }

        assignHeartRateToSegments()
        assignPowerToSegments()
    }

    /// Use real lap events from HealthKit for swimming splits.
    ///
    /// Each lap's duration spans **from the previous lap's end to this lap's
    /// end** (not just the active-swim window reported by
    /// `HKWorkoutEvent.dateInterval`). This attributes turn/wall time to the
    /// lap it belongs to, so pace reflects what the swimmer actually
    /// experiences. The first lap runs from workout start; the sum of all lap
    /// durations equals the wall-clock time from workout start to the last
    /// lap's end.
    private func computeSwimmingLapSegments() {
        guard let totalDist = workout.distanceMeters, totalDist > 0 else { return }

        let lapCount = swimmingLapEvents.count
        guard lapCount > 0 else { return }

        // Pool swimming: each lap is one pool length.
        // Estimate per-lap distance from total distance / lap count.
        let perLapDist = totalDist / Double(lapCount)

        var result: [WorkoutSegment] = []
        var boundary = workout.startDate
        for (i, event) in swimmingLapEvents.enumerated() {
            let end = event.dateInterval.end
            let duration = end.timeIntervalSince(boundary)
            result.append(WorkoutSegment(
                id: i,
                startTime: boundary,
                endTime: end,
                distanceMeters: perLapDist,
                durationSeconds: max(duration, 0)
            ))
            boundary = end
        }

        segments = result
    }

    private func computeGPSSegments(segmentDistance: Double) {
        let points = cachedRoutePoints
        guard points.count > 1 else { return }

        var result: [WorkoutSegment] = []
        var segStart = points[0].timestamp
        var cumDist = 0.0
        var segElevChange = 0.0
        var lastAlt = points[0].altitude
        var segIdx = 0

        for i in 1..<points.count {
            let prev = CLLocation(latitude: points[i - 1].latitude, longitude: points[i - 1].longitude)
            let curr = CLLocation(latitude: points[i].latitude, longitude: points[i].longitude)
            cumDist += curr.distance(from: prev)

            let altDelta = points[i].altitude - lastAlt
            if abs(altDelta) > 1.0 {
                segElevChange += altDelta
                lastAlt = points[i].altitude
            }

            if cumDist >= segmentDistance {
                result.append(WorkoutSegment(
                    id: segIdx,
                    startTime: segStart,
                    endTime: points[i].timestamp,
                    distanceMeters: cumDist,
                    durationSeconds: points[i].timestamp.timeIntervalSince(segStart),
                    elevationChange: segElevChange
                ))
                segIdx += 1
                segStart = points[i].timestamp
                cumDist = 0
                segElevChange = 0
            }
        }

        // Include last partial segment if > 10% of target distance
        if cumDist > segmentDistance * 0.1, let last = points.last {
            result.append(WorkoutSegment(
                id: segIdx,
                startTime: segStart,
                endTime: last.timestamp,
                distanceMeters: cumDist,
                durationSeconds: last.timestamp.timeIntervalSince(segStart),
                elevationChange: segElevChange
            ))
        }

        segments = result
    }

    /// For workouts without route points (e.g. pool swimming), divide evenly.
    private func computeEvenSegments(segmentDistance: Double) {
        guard let totalDist = workout.distanceMeters, totalDist > 0,
              workout.durationSeconds > 0 else { return }

        let avgSpeed = totalDist / workout.durationSeconds  // m/s
        let fullCount = Int(totalDist / segmentDistance)
        let remainder = totalDist - Double(fullCount) * segmentDistance
        let start = workout.startDate
        var result: [WorkoutSegment] = []

        for i in 0..<fullCount {
            let segDur = segmentDistance / avgSpeed
            let segStart = start.addingTimeInterval(Double(i) * segDur)
            result.append(WorkoutSegment(
                id: i,
                startTime: segStart,
                endTime: start.addingTimeInterval(Double(i + 1) * segDur),
                distanceMeters: segmentDistance,
                durationSeconds: segDur
            ))
        }

        // Include partial last segment if > 10% of target distance
        if remainder > segmentDistance * 0.1 {
            let segDur = remainder / avgSpeed
            let segStart = start.addingTimeInterval(Double(fullCount) * (segmentDistance / avgSpeed))
            result.append(WorkoutSegment(
                id: fullCount,
                startTime: segStart,
                endTime: segStart.addingTimeInterval(segDur),
                distanceMeters: remainder,
                durationSeconds: segDur
            ))
        }

        segments = result
    }

    private func assignHeartRateToSegments() {
        guard !heartRatePoints.isEmpty else { return }
        let start = workout.startDate

        for i in 0..<segments.count {
            let segStartSec = segments[i].startTime.timeIntervalSince(start)
            let segEndSec = segments[i].endTime.timeIntervalSince(start)
            let hrs = heartRatePoints.filter {
                $0.secondsFromStart >= segStartSec && $0.secondsFromStart < segEndSec
            }
            if !hrs.isEmpty {
                segments[i].avgHeartRate = hrs.map(\.bpm).reduce(0, +) / Double(hrs.count)
            }
        }
    }

    private func assignPowerToSegments() {
        guard !powerPoints.isEmpty else { return }
        let start = workout.startDate

        for i in 0..<segments.count {
            let segStartSec = segments[i].startTime.timeIntervalSince(start)
            let segEndSec = segments[i].endTime.timeIntervalSince(start)
            let pws = powerPoints.filter {
                $0.secondsFromStart >= segStartSec && $0.secondsFromStart < segEndSec
            }
            if !pws.isEmpty {
                segments[i].avgPower = pws.map(\.watts).reduce(0, +) / Double(pws.count)
            }
        }
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
