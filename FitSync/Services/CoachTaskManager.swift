import Foundation
import Observation

/// Tracks in-flight AI coach enhancement requests so they survive view
/// navigation. The view observes `inProgress` / `errors` for live updates and
/// re-reads `workout.cachedCoachAnalysis` once the task completes.
@MainActor
@Observable
final class CoachTaskManager {
    private(set) var inProgress: Set<String> = []
    private(set) var errors: [String: String] = [:]

    private var activeTasks: [String: Task<Void, Never>] = [:]

    func isEnhancing(_ uuid: String) -> Bool {
        inProgress.contains(uuid)
    }

    func lastError(for uuid: String) -> String? {
        errors[uuid]
    }

    func clearError(for uuid: String) {
        errors[uuid] = nil
    }

    func enhance(
        workout: Workout,
        recentWorkouts: [Workout],
        goal: TrainingGoal?
    ) {
        let uuid = workout.healthKitUUID
        guard !inProgress.contains(uuid) else { return }

        inProgress.insert(uuid)
        errors[uuid] = nil

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let result = try await AICoachService.shared.enhance(
                    workout: workout,
                    recentWorkouts: recentWorkouts,
                    goal: goal
                )
                workout.cachedCoachAnalysis = result
                workout.cachedCoachAnalysisDate = .now
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.errors[uuid] = message
            }
            self.inProgress.remove(uuid)
            self.activeTasks[uuid] = nil
        }
        activeTasks[uuid] = task
    }
}
