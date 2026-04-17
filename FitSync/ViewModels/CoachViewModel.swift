import Foundation
import SwiftUI
import SwiftData

@MainActor
@Observable
final class CoachViewModel {
    let repository: WorkoutRepository
    private let analyzer = WorkoutAnalyzer()
    private let planGenerator = TrainingPlanGenerator()

    var goal: TrainingGoal? {
        get {
            guard let raw = UserDefaults.standard.object(forKey: "trainingGoalRawValue") as? Int else { return nil }
            return TrainingGoal(rawValue: raw)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.rawValue, forKey: "trainingGoalRawValue")
            } else {
                UserDefaults.standard.removeObject(forKey: "trainingGoalRawValue")
            }
        }
    }

    // Weekly load
    var sessionsThisWeek: Int = 0
    var runKmThisWeek: Double = 0
    var cycleKmThisWeek: Double = 0
    var swimMThisWeek: Double = 0
    var totalDurationMinThisWeek: Double = 0

    // Training plan
    var trainingPlan: TrainingPlan?

    // Suggestions & insights
    var suggestedWorkouts: [CoachAnalysis.SuggestedWorkout] = []
    var recentInsights: [(workout: Workout, summary: String)] = []

    var isLoading = false
    var showGoalSheet = false
    var showSettingsSheet = false

    init(repository: WorkoutRepository) {
        self.repository = repository
    }

    func load() {
        isLoading = true
        defer { isLoading = false }

        let calendar = Calendar.current
        let now = Date.now
        let sixWeeksAgo = calendar.date(byAdding: .weekOfYear, value: -6, to: now) ?? now
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now

        // Fetch recent workouts
        let allRecent = repository.fetchWorkouts()
            .filter { $0.startDate >= sixWeeksAgo }
        let thisWeek = allRecent.filter { $0.startDate >= weekStart }

        // Weekly load
        sessionsThisWeek = thisWeek.count
        runKmThisWeek = thisWeek
            .filter { $0.type == .running }
            .compactMap(\.distanceMeters)
            .reduce(0, +) / 1000
        cycleKmThisWeek = thisWeek
            .filter { $0.type == .cycling }
            .compactMap(\.distanceMeters)
            .reduce(0, +) / 1000
        swimMThisWeek = thisWeek
            .filter { $0.type == .swimming }
            .compactMap(\.distanceMeters)
            .reduce(0, +)
        totalDurationMinThisWeek = thisWeek
            .map(\.durationSeconds)
            .reduce(0, +) / 60

        // Generate training plan
        if let goal {
            let allWorkouts = repository.fetchWorkouts()
            trainingPlan = planGenerator.generate(from: allWorkouts, goal: goal)

            // Update current week completion
            if var plan = trainingPlan, !plan.weeklyBlocks.isEmpty {
                plan.weeklyBlocks[0].completedSessions = sessionsThisWeek
                let target = plan.weeklyBlocks[0].targetSessions
                plan.weeklyBlocks[0].completionRatio = target > 0
                    ? min(Double(sessionsThisWeek) / Double(target), 1.0) : 0
                trainingPlan = plan
            }
        } else {
            trainingPlan = nil
        }

        // Suggestions from analyzer (based on most recent workout)
        if let latest = allRecent.first {
            let analysis = analyzer.analyze(
                workout: latest,
                recentWorkouts: allRecent,
                goal: goal
            )
            suggestedWorkouts = analysis.suggestedWorkouts
        }

        // Recent insights from cached analyses
        recentInsights = allRecent.prefix(5).compactMap { workout in
            guard let analysis = workout.cachedCoachAnalysis,
                  let firstObs = analysis.observations.first else { return nil }
            return (workout: workout, summary: firstObs.title)
        }
    }
}
