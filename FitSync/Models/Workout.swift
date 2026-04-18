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

    /// Set at sync time so views can check without faulting in the relationship.
    var hasMap: Bool = false

    // Denormalized start/end GPS coordinates for fast route matching.
    var startLatitude: Double?
    var startLongitude: Double?
    var endLatitude: Double?
    var endLongitude: Double?

    @Relationship(deleteRule: .cascade, inverse: \RoutePoint.workout)
    var routePoints: [RoutePoint] = []

    // MARK: - Cached HealthKit detail data (lazy-populated on first detail open)

    /// Non-nil once HealthKit detail data has been fetched and cached.
    var detailCacheDate: Date?

    var cachedAvgHeartRate: Double?
    var cachedMaxHeartRate: Double?
    var cachedAvgPowerWatts: Double?
    var cachedMaxPowerWatts: Double?
    var cachedAvgCadenceSpm: Double?
    var cachedAvgGroundContactTimeMs: Double?
    var cachedAvgStrideLengthMeters: Double?
    var cachedAvgVerticalOscillationCm: Double?
    var cachedAvgRunningPowerWatts: Double?

    /// JSON-encoded time-series arrays for charts.
    var cachedHeartRateSeriesData: Data?
    var cachedPowerSeriesData: Data?

    /// Cached coach analysis (JSON-encoded CoachAnalysis).
    var cachedCoachAnalysisData: Data?
    var cachedCoachAnalysisDate: Date?

    /// Cached list of similar-run UUIDs (JSON-encoded [String]). Populated lazily
    /// the first time `findSimilarWorkouts` is called; stable unless a newer
    /// running workout is synced (which invalidates the cache).
    var cachedSimilarUUIDsData: Data?
    /// The max startDate across all running workouts at the time the cache
    /// was written. Cache is valid while no newer running workout exists.
    var cachedSimilarLatestRunDate: Date?
    /// Bump when similarity criteria change (thresholds, formula) to
    /// invalidate all existing caches on next scan.
    var cachedSimilarCriteriaVersion: Int?

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

    // MARK: - Time-series codable helpers

    struct CachedTimePoint: Codable {
        let t: Double  // secondsFromStart
        let v: Double  // value (bpm or watts)
    }

    var cachedHeartRateSeries: [CachedTimePoint]? {
        get {
            guard let data = cachedHeartRateSeriesData else { return nil }
            return try? JSONDecoder().decode([CachedTimePoint].self, from: data)
        }
        set {
            cachedHeartRateSeriesData = newValue.flatMap { try? JSONEncoder().encode($0) }
        }
    }

    var cachedPowerSeries: [CachedTimePoint]? {
        get {
            guard let data = cachedPowerSeriesData else { return nil }
            return try? JSONDecoder().decode([CachedTimePoint].self, from: data)
        }
        set {
            cachedPowerSeriesData = newValue.flatMap { try? JSONEncoder().encode($0) }
        }
    }

    var cachedSimilarUUIDs: [String]? {
        get {
            guard let data = cachedSimilarUUIDsData else { return nil }
            return try? JSONDecoder().decode([String].self, from: data)
        }
        set {
            cachedSimilarUUIDsData = newValue.flatMap { try? JSONEncoder().encode($0) }
        }
    }

    var cachedCoachAnalysis: CoachAnalysis? {
        get {
            guard let data = cachedCoachAnalysisData else { return nil }
            return try? JSONDecoder().decode(CoachAnalysis.self, from: data)
        }
        set {
            cachedCoachAnalysisData = newValue.flatMap { try? JSONEncoder().encode($0) }
        }
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
