import Foundation
import SwiftUI
import SwiftData

@MainActor
@Observable
final class CoachViewModel {
    let repository: WorkoutRepository
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

    // Goal prediction
    var prediction: RacePredictor.Prediction?
    var predictionHistory: [RacePredictor.WeeklyPrediction] = []
    var predictionBaselineAgeDays: Int?

    var isLoading = false
    var showGoalSheet = false
    var showSettingsSheet = false
    var showChat = false

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

        let allRecent = repository.fetchWorkouts()
            .filter { $0.startDate >= sixWeeksAgo }
        let thisWeek = allRecent.filter { $0.startDate >= weekStart }

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

        if let goal {
            let allWorkouts = repository.fetchWorkouts()
            trainingPlan = planGenerator.generate(from: allWorkouts, goal: goal)

            if var plan = trainingPlan, !plan.weeklyBlocks.isEmpty {
                plan.weeklyBlocks[0].completedSessions = sessionsThisWeek
                let target = plan.weeklyBlocks[0].targetSessions
                plan.weeklyBlocks[0].completionRatio = target > 0
                    ? min(Double(sessionsThisWeek) / Double(target), 1.0) : 0
                trainingPlan = plan
            }

            computePrediction(goal: goal, allWorkouts: allWorkouts)
        } else {
            trainingPlan = nil
            prediction = nil
            predictionHistory = []
            predictionBaselineAgeDays = nil
        }
    }

    private func computePrediction(goal: TrainingGoal, allWorkouts: [Workout]) {
        guard let targetKm = goal.predictedRunDistanceKm else {
            prediction = nil
            predictionHistory = []
            predictionBaselineAgeDays = nil
            return
        }

        let now = Date.now
        let sixWeeksAgo = Calendar.current.date(byAdding: .weekOfYear, value: -6, to: now) ?? now
        let baselineWindow = DateInterval(start: sixWeeksAgo, end: now)

        if let baseline = RacePredictor.baseline(from: allWorkouts, within: baselineWindow) {
            let secs = RacePredictor.predict(baseline: baseline, targetKm: targetKm)
            prediction = .init(targetDistanceKm: targetKm, predictedSeconds: secs, baseline: baseline)
            predictionBaselineAgeDays = Calendar.current.dateComponents(
                [.day], from: baseline.workout.startDate, to: now
            ).day
        } else {
            prediction = nil
            predictionBaselineAgeDays = nil
        }

        predictionHistory = RacePredictor.weeklyHistory(
            workouts: allWorkouts,
            targetKm: targetKm,
            weeks: 10,
            smoothingWeeks: 3,
            from: now
        )
    }
}
