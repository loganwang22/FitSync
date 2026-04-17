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

    /// Finds running workouts with a similar GPS route to the given workout.
    /// Matches based on start/end location proximity (~200m) and distance similarity (±15%).
    func findSimilarWorkouts(to workout: Workout) -> [Workout] {
        guard workout.type == .running,
              let startLat = workout.startLatitude,
              let startLng = workout.startLongitude,
              let endLat = workout.endLatitude,
              let endLng = workout.endLongitude,
              let dist = workout.distanceMeters, dist > 0 else {
            return []
        }

        // ~200m threshold in degrees (rough: 1° lat ≈ 111km, 1° lng ≈ 85km at mid-latitudes)
        let latThreshold = 0.002   // ~220m
        let lngThreshold = 0.0025  // ~210m at 40° latitude
        let distFraction = 0.15    // 15%

        let allRuns = fetchWorkouts(type: .running)
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
