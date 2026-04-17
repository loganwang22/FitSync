import Foundation

struct TrainingPlan: Codable {
    let generatedDate: Date
    let goalRawValue: Int
    let baselineWeeklyKm: Double

    var weeklyBlocks: [WeeklyBlock]
    var monthlyMilestones: [MonthlyMilestone]

    var goal: TrainingGoal? { TrainingGoal(rawValue: goalRawValue) }

    // MARK: - Weekly Block

    struct WeeklyBlock: Codable, Identifiable {
        var id: Int { weekNumber }
        let weekNumber: Int
        let weekStart: Date
        let isDeloadWeek: Bool
        let targetSessions: Int
        let targetRunKm: Double
        let targetCycleKm: Double
        let targetSwimM: Double
        var workoutTargets: [WorkoutTarget]

        /// How far through the week we are (0-1).
        var completionRatio: Double? = nil
        var completedSessions: Int? = nil
    }

    struct WorkoutTarget: Codable, Identifiable {
        let id: UUID
        let dayOfWeek: Int  // 1=Sun … 7=Sat (Calendar)
        let typeRawValue: Int
        let name: String
        let description: String
        let targetDistanceMeters: Double?
        let targetDurationMinutes: Int?
        let targetPaceSecondsPerKm: Double?
        let targetHRZone: String?
        let intensity: Intensity

        var type: WorkoutType? { WorkoutType(rawValue: typeRawValue) }

        enum Intensity: String, Codable {
            case easy, moderate, hard
        }
    }

    // MARK: - Monthly Milestone

    struct MonthlyMilestone: Codable, Identifiable {
        let id: UUID
        let month: Date
        let title: String
        let detail: String
        let targetWeeklyKm: Double?
        let targetLongRunKm: Double?
        var achieved: Bool = false
    }
}
