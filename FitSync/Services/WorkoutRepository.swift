import Foundation
import SwiftData

final class WorkoutRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - CRUD

    func insert(_ workout: Workout) {
        context.insert(workout)
    }

    func save() throws {
        try context.save()
    }

    // MARK: - Queries

    func fetchWorkouts(type: WorkoutType? = nil, limit: Int? = nil) -> [Workout] {
        var descriptor = FetchDescriptor<Workout>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        if let type {
            let rawValue = type.rawValue
            descriptor.predicate = #Predicate<Workout> { $0.typeRawValue == rawValue }
        }
        if let limit {
            descriptor.fetchLimit = limit
        }
        return (try? context.fetch(descriptor)) ?? []
    }

    func fetchWorkouts(in range: DateRange, from date: Date = .now, type: WorkoutType? = nil) -> [Workout] {
        let interval = range.interval(from: date)
        let start = interval.start
        let end = interval.end

        var descriptor = FetchDescriptor<Workout>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )

        if let type {
            let rawValue = type.rawValue
            descriptor.predicate = #Predicate<Workout> {
                $0.startDate >= start && $0.startDate <= end && $0.typeRawValue == rawValue
            }
        } else {
            descriptor.predicate = #Predicate<Workout> {
                $0.startDate >= start && $0.startDate <= end
            }
        }

        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Aggregation

    func summary(for range: DateRange, from date: Date = .now, type: WorkoutType? = nil) -> WorkoutSummary {
        let workouts = fetchWorkouts(in: range, from: date, type: type)

        let totalDistance = workouts.compactMap(\.distanceMeters).reduce(0, +)
        let totalDuration = workouts.map(\.durationSeconds).reduce(0, +)
        let totalCalories = workouts.compactMap(\.activeEnergyKcal).reduce(0, +)
        let totalElevationGain = workouts.compactMap(\.elevationGainMeters).reduce(0, +)

        var avgPace: Double? = nil
        if type == .running || type == nil {
            let paces = workouts.compactMap(\.avgPaceSecondsPerKm)
            if !paces.isEmpty {
                avgPace = paces.reduce(0, +) / Double(paces.count)
            }
        }

        return WorkoutSummary(
            period: range,
            workoutType: type,
            totalDistanceMeters: totalDistance,
            totalDurationSeconds: totalDuration,
            totalCalories: totalCalories,
            workoutCount: workouts.count,
            avgPaceSecondsPerKm: avgPace,
            totalElevationGainMeters: totalElevationGain
        )
    }

    // MARK: - Similar Workouts (Matched Runs)

    /// Bump when similarity thresholds or the match formula change so
    /// previously-written caches are discarded on the next scan.
    private static let similarityCriteriaVersion = 2

    /// Finds running workouts with a similar GPS route to the given workout.
    /// Matches based on start/end location proximity (~200m) and distance similarity (±15%).
    ///
    /// Results are cached on the workout and only recomputed when a newer
    /// running workout has been synced since the last computation.
    ///
    /// Async because a cold-cache scan faults in `sortedRoutePoints` for every
    /// historical run missing denormalized start/end coords — that's tens to
    /// hundreds of synchronous SwiftData relationship loads on the main actor
    /// and will freeze the UI. The backfill yields between items so the main
    /// thread can render.
    @MainActor
    func findSimilarWorkouts(to workout: Workout) async -> [Workout] {
        guard workout.type == .running,
              let dist = workout.distanceMeters, dist > 0 else {
            return []
        }

        let allRuns = fetchWorkouts(type: .running)
        let latestRunDate = allRuns.map(\.startDate).max()

        // Fast path: cache hit with the current criteria version and no newer
        // run synced since. Skips the expensive backfill entirely.
        if workout.cachedSimilarCriteriaVersion == Self.similarityCriteriaVersion,
           let cached = workout.cachedSimilarUUIDs,
           let cachedAsOf = workout.cachedSimilarLatestRunDate,
           let latest = latestRunDate,
           cachedAsOf >= latest {
            let uuidSet = Set(cached)
            return allRuns
                .filter { uuidSet.contains($0.healthKitUUID) }
                .sorted { $0.startDate > $1.startDate }
        }

        // Slow path: populate denormalized coords for any historical run that
        // pre-dates these fields, yielding to keep the UI responsive.
        await backfillStartEndCoordinates(for: allRuns)

        // The current workout itself may have been missing coords until we
        // just ran the backfill, so check after.
        guard workout.startLatitude != nil, workout.startLongitude != nil,
              workout.endLatitude != nil, workout.endLongitude != nil else {
            return []
        }

        let matches = computeSimilarWorkouts(to: workout, from: allRuns)
        workout.cachedSimilarUUIDs = matches.map(\.healthKitUUID)
        workout.cachedSimilarLatestRunDate = latestRunDate
        workout.cachedSimilarCriteriaVersion = Self.similarityCriteriaVersion
        return matches.sorted { $0.startDate > $1.startDate }
    }

    @MainActor
    private func backfillStartEndCoordinates(for runs: [Workout]) async {
        var counter = 0
        for w in runs where w.startLatitude == nil || w.endLatitude == nil {
            let pts = w.sortedRoutePoints
            if let first = pts.first, let last = pts.last {
                w.startLatitude = first.latitude
                w.startLongitude = first.longitude
                w.endLatitude = last.latitude
                w.endLongitude = last.longitude
            }
            counter += 1
            if counter % 5 == 0 {
                await Task.yield()
            }
        }
    }

    private func computeSimilarWorkouts(to workout: Workout, from allRuns: [Workout]) -> [Workout] {
        guard let startLat = workout.startLatitude,
              let startLng = workout.startLongitude,
              let endLat = workout.endLatitude,
              let endLng = workout.endLongitude,
              let dist = workout.distanceMeters, dist > 0 else { return [] }

        // ~200m threshold in degrees (rough: 1° lat ≈ 111km, 1° lng ≈ 85km at mid-latitudes)
        let latThreshold = 0.002
        let lngThreshold = 0.0025
        let distFraction = 0.15
        let uuid = workout.healthKitUUID

        return allRuns.filter { w in
            guard w.healthKitUUID != uuid,
                  let sLat = w.startLatitude, let sLng = w.startLongitude,
                  let eLat = w.endLatitude, let eLng = w.endLongitude,
                  let wDist = w.distanceMeters, wDist > 0 else {
                return false
            }

            let startClose = abs(sLat - startLat) < latThreshold && abs(sLng - startLng) < lngThreshold
            let endClose = abs(eLat - endLat) < latThreshold && abs(eLng - endLng) < lngThreshold
            let distClose = abs(wDist - dist) / dist < distFraction

            return startClose && endClose && distClose
        }
    }

    // MARK: - Time Series

    struct WeeklyData: Identifiable {
        let id = UUID()
        let weekStart: Date
        let totalDistanceKm: Double
        let totalDurationMinutes: Double
        let workoutCount: Int
        let workoutType: WorkoutType?
    }

    func weeklyTotals(weeks: Int = 12, type: WorkoutType? = nil) -> [WeeklyData] {
        let calendar = Calendar.current
        let now = Date.now
        var results: [WeeklyData] = []

        for i in 0..<weeks {
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -i, to: now),
                  let interval = calendar.dateInterval(of: .weekOfYear, for: weekStart) else { continue }

            let start = interval.start
            let end = interval.end

            var descriptor = FetchDescriptor<Workout>()
            if let type {
                let rawValue = type.rawValue
                descriptor.predicate = #Predicate<Workout> {
                    $0.startDate >= start && $0.startDate < end && $0.typeRawValue == rawValue
                }
            } else {
                descriptor.predicate = #Predicate<Workout> {
                    $0.startDate >= start && $0.startDate < end
                }
            }

            let workouts = (try? context.fetch(descriptor)) ?? []
            let totalDist = workouts.compactMap(\.distanceMeters).reduce(0, +) / 1000.0
            let totalDur = workouts.map(\.durationSeconds).reduce(0, +) / 60.0

            results.append(WeeklyData(
                weekStart: interval.start,
                totalDistanceKm: totalDist,
                totalDurationMinutes: totalDur,
                workoutCount: workouts.count,
                workoutType: type
            ))
        }

        return results.reversed()
    }
}
