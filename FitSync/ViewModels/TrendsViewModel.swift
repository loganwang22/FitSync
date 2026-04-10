import Foundation

@Observable
final class TrendsViewModel {
    private let repository: WorkoutRepository

    var selectedType: WorkoutType? = nil
    var weeklyData: [WorkoutRepository.WeeklyData] = []

    // Per-type data for stacked chart
    var stackedData: [(week: Date, distance: Double, type: WorkoutType)] = []

    init(repository: WorkoutRepository) {
        self.repository = repository
    }

    func load() {
        weeklyData = repository.weeklyTotals(weeks: 12, type: selectedType)
        loadStackedData()
    }

    func selectType(_ type: WorkoutType?) {
        selectedType = type
        weeklyData = repository.weeklyTotals(weeks: 12, type: selectedType)
    }

    private func loadStackedData() {
        var result: [(week: Date, distance: Double, type: WorkoutType)] = []
        for type in WorkoutType.allCases {
            let data = repository.weeklyTotals(weeks: 12, type: type)
            for entry in data {
                result.append((week: entry.weekStart, distance: entry.totalDistanceKm, type: type))
            }
        }
        stackedData = result
    }
}
