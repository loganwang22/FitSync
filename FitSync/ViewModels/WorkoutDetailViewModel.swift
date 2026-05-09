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
        var strokeCount: Int?

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

    // Pause windows parsed from HKWorkoutEvents. Used to exclude paused time
    // from per-split duration so pace matches what Strava / Apple Fitness show.
    private var pauseIntervals: [DateInterval] = []

    // Device-calibrated cumulative distance samples
    // (distanceWalkingRunning / distanceCycling). Preferred over raw haversine
    // for computing split boundaries because Apple's stride-model + GPS fusion
    // produces a smoother, better-calibrated distance curve than summing noisy
    // raw GPS points.
    private struct DistanceSample {
        let start: Date
        let end: Date
        let meters: Double
    }
    private var distanceSamples: [DistanceSample] = []

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
            await loadSwimmingStrokes()
        }

        // Pause windows + device-calibrated distance samples are not cached;
        // load them fresh so splits always use current HK data.
        await loadHKWorkout()
        loadPauseWindows()
        if workout.type != .swimming {
            await loadDistanceSamples()
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
        loadPauseWindows()
        if workout.type != .swimming {
            await loadDistanceSamples()
        }
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

        // Find similar workouts (matched runs). Fired in its own Task so the
        // rest of the detail view (segments, elevation) renders immediately;
        // the similarity scan can take noticeable time on first load because
        // it has to backfill denormalized start/end coords for historical
        // runs by faulting in their route points.
        if workout.type == .running, let repo = repository {
            Task { [weak self] in
                guard let self else { return }
                let matches = await repo.findSimilarWorkouts(to: self.workout)
                self.similarWorkouts = matches
            }
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
            await loadSwimmingStrokes()
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
    private var swimmingStrokeSamples: [HKQuantitySample] = []

    private func loadSwimmingLaps() {
        guard workout.type == .swimming, let hkw = hkWorkout else { return }
        swimmingLapEvents = (hkw.workoutEvents ?? [])
            .filter { $0.type == .lap }
            .sorted { $0.dateInterval.start < $1.dateInterval.start }
    }

    private func loadSwimmingStrokes() async {
        guard workout.type == .swimming else { return }
        let type = HKQuantityType(.swimmingStrokeCount)
        // Prefer samples from the HK workout to avoid picking up other swim
        // sessions that happen to overlap the time window.
        if let hkw = hkWorkout {
            let predicate = HKQuery.predicateForObjects(from: hkw)
            let descriptor = HKSampleQueryDescriptor(
                predicates: [.quantitySample(type: type, predicate: predicate)],
                sortDescriptors: [SortDescriptor(\.startDate)]
            )
            if let samples = try? await descriptor.result(for: store), !samples.isEmpty {
                swimmingStrokeSamples = samples
                return
            }
        }
        // Fallback: time-window query.
        if let samples = try? await fetchSamples(type: type) {
            swimmingStrokeSamples = samples.sorted { $0.startDate < $1.startDate }
        }
    }

    // MARK: - Per-distance segments (splits)

    private func computeSegments() {
        let segmentDistance: Double = workout.type == .swimming ? 100.0 : 1000.0

        if workout.type == .swimming && !swimmingLapEvents.isEmpty {
            computeSwimmingLapSegments()
        } else if computeDistanceSampleSegments(segmentDistance: segmentDistance) {
            // Device-calibrated distance samples produced the splits.
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
            let strokes = strokeCount(from: boundary, to: end)
            result.append(WorkoutSegment(
                id: i,
                startTime: boundary,
                endTime: end,
                distanceMeters: perLapDist,
                durationSeconds: max(duration, 0),
                strokeCount: strokes
            ))
            boundary = end
        }

        segments = result
    }

    /// Sum swim strokes that fall within [start, end). A sample straddling a
    /// lap boundary is pro-rated by the fraction of its duration that falls
    /// inside the lap — this avoids double-counting while handling the common
    /// case where Apple Watch emits one sample per length.
    ///
    /// Values are reported exactly as Apple Watch records them — note that
    /// Apple uses a watch-arm-cycle convention for freestyle/backstroke, so
    /// those lap totals will appear ~half of what a swimmer counts by hand.
    /// This is intentional; we show raw HealthKit data.
    private func strokeCount(from start: Date, to end: Date) -> Int? {
        guard !swimmingStrokeSamples.isEmpty, end > start else { return nil }
        let lapSeconds = end.timeIntervalSince(start)
        guard lapSeconds > 0 else { return nil }

        var total = 0.0
        var touched = false
        for sample in swimmingStrokeSamples {
            let s = max(sample.startDate, start)
            let e = min(sample.endDate, end)
            guard e > s else { continue }
            touched = true
            let sampleSeconds = sample.endDate.timeIntervalSince(sample.startDate)
            let count = sample.quantity.doubleValue(for: .count())
            if sampleSeconds <= 0 {
                total += count
            } else {
                let overlap = e.timeIntervalSince(s)
                total += count * (overlap / sampleSeconds)
            }
        }
        guard touched else { return nil }
        return Int(total.rounded())
    }

    /// Lightweight smoothed copy of a GPS path (used as the input to
    /// `computeGPSSegments`). Created locally because we don't want to mutate
    /// the persisted `RoutePoint` SwiftData rows.
    private struct PathPoint {
        let latitude: Double
        let longitude: Double
        let altitude: Double
        let timestamp: Date
    }

    /// 3-point moving-average smoothing on lat/lon/altitude. Reduces GPS jitter
    /// that otherwise inflates haversine cumulative distance and shifts split
    /// boundaries. Cheap (O(n)) and good enough as a fallback when device-
    /// calibrated `distanceWalkingRunning` samples aren't available.
    private func smoothedPath() -> [PathPoint] {
        let pts = cachedRoutePoints
        guard pts.count >= 3 else {
            return pts.map {
                PathPoint(latitude: $0.latitude, longitude: $0.longitude,
                          altitude: $0.altitude, timestamp: $0.timestamp)
            }
        }
        var out: [PathPoint] = []
        out.reserveCapacity(pts.count)
        for i in 0..<pts.count {
            let lo = max(0, i - 1)
            let hi = min(pts.count - 1, i + 1)
            var lat = 0.0, lon = 0.0, alt = 0.0
            var n = 0
            for j in lo...hi {
                lat += pts[j].latitude
                lon += pts[j].longitude
                alt += pts[j].altitude
                n += 1
            }
            out.append(PathPoint(
                latitude: lat / Double(n),
                longitude: lon / Double(n),
                altitude: alt / Double(n),
                timestamp: pts[i].timestamp
            ))
        }
        return out
    }

    private func computeGPSSegments(segmentDistance: Double) {
        let points = smoothedPath()
        guard points.count > 1 else { return }

        var result: [WorkoutSegment] = []
        var segStart = points[0].timestamp
        var cumDist = 0.0
        var segIdx = 0

        for i in 1..<points.count {
            let prev = CLLocation(latitude: points[i - 1].latitude, longitude: points[i - 1].longitude)
            let curr = CLLocation(latitude: points[i].latitude, longitude: points[i].longitude)
            let d = curr.distance(from: prev)
            // Reject GPS jumps that imply >50 m/s — clear noise spikes.
            let dt = points[i].timestamp.timeIntervalSince(points[i - 1].timestamp)
            if dt > 0 && d / dt < 50 {
                cumDist += d
            }

            if cumDist >= segmentDistance {
                let endT = points[i].timestamp
                result.append(WorkoutSegment(
                    id: segIdx,
                    startTime: segStart,
                    endTime: endT,
                    distanceMeters: cumDist,
                    durationSeconds: activeDuration(from: segStart, to: endT),
                    elevationChange: elevationChange(from: segStart, to: endT)
                ))
                segIdx += 1
                segStart = endT
                cumDist = 0
            }
        }

        // Include last partial segment if > 10% of target distance
        if cumDist > segmentDistance * 0.1, let last = points.last {
            result.append(WorkoutSegment(
                id: segIdx,
                startTime: segStart,
                endTime: last.timestamp,
                distanceMeters: cumDist,
                durationSeconds: activeDuration(from: segStart, to: last.timestamp),
                elevationChange: elevationChange(from: segStart, to: last.timestamp)
            ))
        }

        segments = result
    }

    // MARK: - Pause windows

    /// Parses `HKWorkoutEvent`s into pairs of `[pause, resume]` time intervals.
    /// Both explicit (`.pause`/`.resume`) and motion-based (`.motionPaused`/
    /// `.motionResumed`) events are honored. An unterminated pause at the end
    /// runs through `workout.endDate`.
    private func loadPauseWindows() {
        guard let events = hkWorkout?.workoutEvents, !events.isEmpty else {
            pauseIntervals = []
            return
        }
        let sorted = events.sorted { $0.dateInterval.start < $1.dateInterval.start }
        var result: [DateInterval] = []
        var pauseStart: Date? = nil
        for e in sorted {
            switch e.type {
            case .pause, .motionPaused:
                if pauseStart == nil { pauseStart = e.dateInterval.start }
            case .resume, .motionResumed:
                if let s = pauseStart {
                    let end = e.dateInterval.start
                    if end > s { result.append(DateInterval(start: s, end: end)) }
                    pauseStart = nil
                }
            default:
                break
            }
        }
        if let s = pauseStart, workout.endDate > s {
            result.append(DateInterval(start: s, end: workout.endDate))
        }
        pauseIntervals = result
    }

    /// Wall-clock seconds between `start` and `end` minus any time that fell
    /// inside a pause window. Used so split pace excludes pauses (matching
    /// Strava / Apple Fitness conventions).
    private func activeDuration(from start: Date, to end: Date) -> TimeInterval {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        guard !pauseIntervals.isEmpty else { return total }
        var paused: TimeInterval = 0
        for p in pauseIntervals {
            let s = max(p.start, start)
            let e = min(p.end, end)
            if e > s { paused += e.timeIntervalSince(s) }
        }
        return max(total - paused, 0)
    }

    // MARK: - Device-calibrated distance samples

    private func loadDistanceSamples() async {
        let typeID: HKQuantityTypeIdentifier
        switch workout.type {
        case .running:  typeID = .distanceWalkingRunning
        case .cycling:  typeID = .distanceCycling
        case .swimming:
            distanceSamples = []
            return
        }
        let type = HKQuantityType(typeID)
        guard let samples = try? await fetchSamples(type: type, sourceFilterToWorkout: true) else {
            distanceSamples = []
            return
        }
        distanceSamples = samples
            .map {
                DistanceSample(
                    start: $0.startDate,
                    end: $0.endDate,
                    meters: $0.quantity.doubleValue(for: .meter())
                )
            }
            .sorted { $0.start < $1.start }
    }

    /// Builds splits from cumulative `distanceWalkingRunning` /
    /// `distanceCycling` samples. Each sample carries a meter count over a
    /// short [start, end] window; we walk those to find the exact moment the
    /// cumulative distance crosses each km boundary, interpolating within the
    /// sample. Returns `false` if no calibrated distance is available so the
    /// caller can fall back to GPS-based splits.
    private func computeDistanceSampleSegments(segmentDistance: Double) -> Bool {
        guard !distanceSamples.isEmpty else { return false }

        var result: [WorkoutSegment] = []
        var segStartTime = workout.startDate
        var segStartCum = 0.0
        var cum = 0.0
        var nextBoundary = segmentDistance
        var segIdx = 0

        for sample in distanceSamples {
            let sampleStartCum = cum
            let sampleEndCum = cum + sample.meters
            let sampleDur = max(sample.end.timeIntervalSince(sample.start), 0)

            while sampleEndCum >= nextBoundary {
                let into = nextBoundary - sampleStartCum
                let frac = sample.meters > 0 ? min(max(into / sample.meters, 0), 1) : 0
                let crossTime = sample.start.addingTimeInterval(sampleDur * frac)

                result.append(WorkoutSegment(
                    id: segIdx,
                    startTime: segStartTime,
                    endTime: crossTime,
                    distanceMeters: nextBoundary - segStartCum,
                    durationSeconds: activeDuration(from: segStartTime, to: crossTime),
                    elevationChange: elevationChange(from: segStartTime, to: crossTime)
                ))
                segIdx += 1
                segStartTime = crossTime
                segStartCum = nextBoundary
                nextBoundary += segmentDistance
            }

            cum = sampleEndCum
        }

        // Trailing partial split if it covers > 10% of a full split.
        let trailing = cum - segStartCum
        if trailing > segmentDistance * 0.1 {
            let endTime = distanceSamples.last?.end ?? workout.endDate
            result.append(WorkoutSegment(
                id: segIdx,
                startTime: segStartTime,
                endTime: endTime,
                distanceMeters: trailing,
                durationSeconds: activeDuration(from: segStartTime, to: endTime),
                elevationChange: elevationChange(from: segStartTime, to: endTime)
            ))
        }

        guard !result.isEmpty else { return false }
        segments = result
        return true
    }

    /// Sum of altitude deltas across the route slice for `[start, end]`, using
    /// 3-point moving-average smoothing on altitude and a 0.5 m deadband on
    /// per-step deltas (so sub-meter barometer noise doesn't accumulate).
    /// Returns `nil` when no GPS slice covers the range yet.
    private func elevationChange(from start: Date, to end: Date) -> Double? {
        let slice = cachedRoutePoints.filter { $0.timestamp >= start && $0.timestamp <= end }
        guard slice.count >= 2 else { return nil }

        let alts = slice.map(\.altitude)
        var smoothed: [Double] = []
        smoothed.reserveCapacity(alts.count)
        for i in 0..<alts.count {
            let lo = max(0, i - 1)
            let hi = min(alts.count - 1, i + 1)
            var sum = 0.0
            for j in lo...hi { sum += alts[j] }
            smoothed.append(sum / Double(hi - lo + 1))
        }

        var delta = 0.0
        var last = smoothed[0]
        for a in smoothed.dropFirst() {
            let d = a - last
            if abs(d) > 0.5 {
                delta += d
                last = a
            }
        }
        return delta
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
