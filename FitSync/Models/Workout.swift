import Foundation
import SwiftData

@Model
final class Workout {
    @Attribute(.unique) var healthKitUUID: String

    var typeRawValue: Int
    var startDate: Date
    var endDate: Date
    var durationSeconds: Double
    var distanceMeters: Double?
    var activeEnergyKcal: Double?
    var avgPaceSecondsPerKm: Double?
    var avgSpeedMps: Double?
    var elevationGainMeters: Double?
    var strokeCount: Int?
    var laps: Int?
    var sourceName: String?

    @Relationship(deleteRule: .cascade, inverse: \RoutePoint.workout)
    var routePoints: [RoutePoint] = []

    var type: WorkoutType {
        get { WorkoutType(rawValue: typeRawValue) ?? .running }
        set { typeRawValue = newValue.rawValue }
    }

    /// Route points in chronological order. SwiftData relationships have no
    /// guaranteed ordering, so anything that draws a path (map polyline,
    /// elevation chart) MUST go through this accessor — otherwise MapPolyline
    /// will connect points in arbitrary order and produce a tangled shape.
    var sortedRoutePoints: [RoutePoint] {
        routePoints.sorted { $0.timestamp < $1.timestamp }
    }

    init(
        healthKitUUID: String,
        type: WorkoutType,
        startDate: Date,
        endDate: Date,
        durationSeconds: Double,
        distanceMeters: Double? = nil,
        activeEnergyKcal: Double? = nil,
        avgPaceSecondsPerKm: Double? = nil,
        avgSpeedMps: Double? = nil,
        elevationGainMeters: Double? = nil,
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
        self.avgPaceSecondsPerKm = avgPaceSecondsPerKm
        self.avgSpeedMps = avgSpeedMps
        self.elevationGainMeters = elevationGainMeters
        self.strokeCount = strokeCount
        self.laps = laps
        self.sourceName = sourceName
    }
}
