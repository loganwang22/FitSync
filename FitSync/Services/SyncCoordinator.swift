import Foundation
import HealthKit
import CoreLocation

@Observable
final class SyncCoordinator {
    private let healthKit: HealthKitService
    private let repository: WorkoutRepository
    private let historicalMonths: Int

    var isSyncing = false
    var lastSyncDate: Date?
    var syncError: String?

    init(healthKit: HealthKitService, repository: WorkoutRepository, historicalMonths: Int = 12) {
        self.healthKit = healthKit
        self.repository = repository
        self.historicalMonths = historicalMonths
    }

    @MainActor
    func performSync() async {
        guard !isSyncing else { return }
        isSyncing = true
        syncError = nil
        defer { isSyncing = false }

        do {
            let since = lastSyncDate ?? Calendar.current.date(byAdding: .month, value: -historicalMonths, to: .now)!
            let hkWorkouts = try await healthKit.fetchWorkouts(from: since)

            let existingUUIDs = try repository.allHealthKitUUIDs()
            let newWorkouts = hkWorkouts.filter { !existingUUIDs.contains($0.uuid.uuidString) }

            for hk in newWorkouts {
                let workout = Self.mapWorkout(hk)
                let locations = try? await healthKit.fetchRoute(for: hk)
                workout.routePoints = locations?.map { RoutePoint(from: $0) } ?? []
                repository.insert(workout)
            }

            try repository.save()
            lastSyncDate = .now
        } catch {
            syncError = error.localizedDescription
        }
    }

    // MARK: - Mapping

    private static func mapWorkout(_ hk: HKWorkout) -> Workout {
        let type: WorkoutType
        switch hk.workoutActivityType {
        case .running: type = .running
        case .cycling: type = .cycling
        case .swimming: type = .swimming
        default: type = .running
        }

        let distance = hk.totalDistance?.doubleValue(for: .meter())
        let calories = hk.totalEnergyBurned?.doubleValue(for: .kilocalorie())
        let duration = hk.duration

        var avgPace: Double? = nil
        if type == .running, let dist = distance, dist > 0 {
            avgPace = duration / (dist / 1000.0)
        }

        var avgSpeed: Double? = nil
        if type == .cycling, let dist = distance, dist > 0 {
            avgSpeed = dist / duration
        }

        var strokeCount: Int? = nil
        var laps: Int? = nil
        if type == .swimming {
            if let strokes = hk.totalSwimmingStrokeCount {
                strokeCount = Int(strokes.doubleValue(for: .count()))
            }
            laps = hk.workoutEvents?.filter { $0.type == .lap }.count
        }

        return Workout(
            healthKitUUID: hk.uuid.uuidString,
            type: type,
            startDate: hk.startDate,
            endDate: hk.endDate,
            durationSeconds: duration,
            distanceMeters: distance,
            activeEnergyKcal: calories,
            avgPaceSecondsPerKm: avgPace,
            avgSpeedMps: avgSpeed,
            strokeCount: strokeCount,
            laps: laps,
            sourceName: hk.sourceRevision.source.name
        )
    }
}
