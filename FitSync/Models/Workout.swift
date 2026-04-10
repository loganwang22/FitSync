import Foundation
import SwiftData
import HealthKit

@Model
final class Workout {
    @Attribute(.unique) var healthKitUUID: String

    var typeRawValue: Int
    var startDate: Date
    var endDate: Date
    var durationSeconds: Double
    var distanceMeters: Double?
    var activeEnergyKcal: Double?
    var avgHeartRate: Double?
    var maxHeartRate: Double?
    var avgPaceSecondsPerKm: Double?
    var avgSpeedMps: Double?
    var strokeCount: Int?
    var laps: Int?
    var sourceName: String?

    @Relationship(deleteRule: .cascade, inverse: \RoutePoint.workout)
    var routePoints: [RoutePoint] = []

    var type: WorkoutType {
        get { WorkoutType(rawValue: typeRawValue) ?? .running }
        set { typeRawValue = newValue.rawValue }
    }

    var distance: Measurement<UnitLength>? {
        guard let distanceMeters else { return nil }
        return Measurement(value: distanceMeters, unit: .meters)
    }

    var duration: TimeInterval {
        durationSeconds
    }

    var formattedPace: String? {
        guard let avgPaceSecondsPerKm, avgPaceSecondsPerKm > 0 else { return nil }
        let minutes = Int(avgPaceSecondsPerKm) / 60
        let seconds = Int(avgPaceSecondsPerKm) % 60
        return String(format: "%d'%02d\"", minutes, seconds)
    }

    init(
        healthKitUUID: String,
        type: WorkoutType,
        startDate: Date,
        endDate: Date,
        durationSeconds: Double,
        distanceMeters: Double? = nil,
        activeEnergyKcal: Double? = nil,
        avgHeartRate: Double? = nil,
        maxHeartRate: Double? = nil,
        avgPaceSecondsPerKm: Double? = nil,
        avgSpeedMps: Double? = nil,
        strokeCount: Int? = nil,
        laps: Int? = nil,
        sourceName: String? = nil
    ) {
        self.healthKitUUID = healthKitUUID
        self.typeRawValue = type.rawValue
        self.startDate = startDate
        self.endDate = endDate
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.activeEnergyKcal = activeEnergyKcal
        self.avgHeartRate = avgHeartRate
        self.maxHeartRate = maxHeartRate
        self.avgPaceSecondsPerKm = avgPaceSecondsPerKm
        self.avgSpeedMps = avgSpeedMps
        self.strokeCount = strokeCount
        self.laps = laps
        self.sourceName = sourceName
    }
}
