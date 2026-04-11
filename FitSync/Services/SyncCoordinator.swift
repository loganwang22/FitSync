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

            let existingByUUID = Dictionary(
                uniqueKeysWithValues: repository.fetchWorkouts().map { ($0.healthKitUUID, $0) }
            )

            for hk in hkWorkouts {
                if let existing = existingByUUID[hk.uuid.uuidString] {
                    // Backfill elevation on older workouts that were imported before
                    // the elevation field existed.
                    if existing.elevationGainMeters == nil,
                       existing.type == .running || existing.type == .cycling {
                        if let gain = Self.elevationGain(fromMetadataOf: hk) {
                            existing.elevationGainMeters = gain
                        } else if let locations = try? await healthKit.fetchRoute(for: hk),
                                  !locations.isEmpty {
                            existing.elevationGainMeters = Self.elevationGain(from: locations)
                        }
                    }
                } else {
                    let workout = Self.mapWorkout(hk)
                    let locations = try? await healthKit.fetchRoute(for: hk)
                    workout.routePoints = locations?.map { RoutePoint(from: $0) } ?? []
                    if workout.elevationGainMeters == nil,
                       workout.type == .running || workout.type == .cycling,
                       let locations, !locations.isEmpty {
                        workout.elevationGainMeters = Self.elevationGain(from: locations)
                    }
                    repository.insert(workout)
                }
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

        let elevationFromMetadata: Double? = {
            guard type == .running || type == .cycling else { return nil }
            return Self.elevationGain(fromMetadataOf: hk)
        }()

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
            elevationGainMeters: elevationFromMetadata,
            strokeCount: strokeCount,
            laps: laps,
            sourceName: hk.sourceRevision.source.name
        )
    }

    // MARK: - Elevation

    /// Reads ascended elevation from HealthKit workout metadata. Apple Watch and
    /// most third-party sources populate `HKMetadataKeyElevationAscended` — use
    /// this as the authoritative value when present.
    static func elevationGain(fromMetadataOf hk: HKWorkout) -> Double? {
        guard let quantity = hk.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity else {
            return nil
        }
        return quantity.doubleValue(for: .meter())
    }

    /// Fallback: derives ascent from GPS altitudes. GPS altitude is noisy so we
    /// ignore deltas under 1 m and points with bad vertical accuracy.
    static func elevationGain(from locations: [CLLocation]) -> Double {
        guard locations.count > 1 else { return 0 }
        let noiseThreshold = 1.0
        var gain = 0.0
        var lastAltitude: Double?
        for location in locations {
            guard location.verticalAccuracy >= 0, location.verticalAccuracy < 20 else { continue }
            let altitude = location.altitude
            if let previous = lastAltitude {
                let delta = altitude - previous
                if delta > noiseThreshold {
                    gain += delta
                    lastAltitude = altitude
                } else if delta < -noiseThreshold {
                    lastAltitude = altitude
                }
            } else {
                lastAltitude = altitude
            }
        }
        return gain
    }
}
