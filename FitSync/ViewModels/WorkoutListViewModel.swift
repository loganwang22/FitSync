import Foundation
import SwiftData

@Observable
final class WorkoutListViewModel {
    let repository: WorkoutRepository
    private let syncCoordinator: SyncCoordinator

    var workouts: [Workout] = []
    var selectedType: WorkoutType? = nil
    var isLoading = false

    init(repository: WorkoutRepository, syncCoordinator: SyncCoordinator) {
        self.repository = repository
        self.syncCoordinator = syncCoordinator
    }

    @MainActor
    func load() async {
        isLoading = true
        defer { isLoading = false }
        await syncCoordinator.performSync()
        workouts = repository.fetchWorkouts(type: selectedType)
    }

    func filterBy(_ type: WorkoutType?) {
        selectedType = type
        workouts = repository.fetchWorkouts(type: selectedType)
    }
}
