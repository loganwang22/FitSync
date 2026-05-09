import Foundation

/// Snapshot of estimated threshold/fitness metrics. Values are derived from
/// past workouts and are only as good as the hardest efforts in the window —
/// see `Confidence` for guidance on how much to trust each number.
struct FitnessMetrics: Codable {
    var cyclingFTP: Estimate?
    var cyclingLTHR: Estimate?
    var cyclingWattsPerKg: Estimate?

    var runningLTHR: Estimate?
    var runningThresholdPaceSecPerKm: Estimate?

    var bodyMassKg: Double?
    var generatedDate: Date

    struct Estimate: Codable {
        let value: Double
        let confidence: Confidence
        /// Human-readable explanation of how this number was derived
        /// (e.g. "Best 20-min power × 0.95 on 2026-03-15").
        let method: String
        /// Date of the baseline workout used.
        let sourceWorkoutDate: Date?
    }

    /// `low` = the effort used was short or easy; treat as a floor, not a ceiling.
    /// `medium` = a reasonable sustained effort but not a dedicated test.
    /// `high` = a proper threshold-length hard effort.
    enum Confidence: String, Codable {
        case low, medium, high

        var label: String {
            switch self {
            case .low: "Low"
            case .medium: "Medium"
            case .high: "High"
            }
        }
    }
}
