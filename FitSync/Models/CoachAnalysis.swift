import Foundation

struct CoachAnalysis: Codable {
    var observations: [Observation]
    var recommendations: [Recommendation]
    var suggestedWorkouts: [SuggestedWorkout]
    var source: AnalysisSource
    var generatedDate: Date

    // MARK: - Observation

    struct Observation: Codable, Identifiable {
        var id: String { "\(category.rawValue)-\(title)" }
        let category: Category
        let title: String
        let detail: String
        let sentiment: Sentiment

        enum Category: String, Codable {
            case pace, heartRate, power, form, endurance, recovery, training
        }

        enum Sentiment: String, Codable {
            case positive, neutral, caution
        }
    }

    // MARK: - Recommendation

    struct Recommendation: Codable, Identifiable {
        var id: String { title }
        let title: String
        let detail: String
        let type: RecommendationType

        enum RecommendationType: String, Codable {
            case nextWorkout, technique, recovery, goalProgress
        }
    }

    // MARK: - Suggested Workout

    struct SuggestedWorkout: Codable, Identifiable {
        var id: String { name }
        let name: String
        let description: String
        let workoutTypeRaw: Int?

        var workoutType: WorkoutType? {
            workoutTypeRaw.flatMap { WorkoutType(rawValue: $0) }
        }

        enum CodingKeys: String, CodingKey {
            case name, description, workoutTypeRaw, durationMinutes, intensity
        }
        let durationMinutes: Int?
        let intensity: Intensity

        enum Intensity: String, Codable {
            case easy, moderate, hard
        }
    }

    enum AnalysisSource: String, Codable {
        case onDevice
        case claude
        case kimi
    }
}
