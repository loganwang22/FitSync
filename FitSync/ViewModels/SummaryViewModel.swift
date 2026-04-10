import Foundation

@Observable
final class SummaryViewModel {
    private let repository: WorkoutRepository

    var selectedRange: DateRange = .week
    var selectedDate: Date = .now
    var overallSummary: WorkoutSummary?
    var sportSummaries: [WorkoutSummary] = []

    init(repository: WorkoutRepository) {
        self.repository = repository
    }

    var canGoForward: Bool {
        let calendar = Calendar.current
        let component: Calendar.Component
        switch selectedRange {
        case .week: component = .weekOfYear
        case .month: component = .month
        case .year: component = .year
        }
        guard let current = calendar.dateInterval(of: component, for: .now),
              let selected = calendar.dateInterval(of: component, for: selectedDate) else {
            return false
        }
        return selected.start < current.start
    }

    var periodLabel: String {
        let calendar = Calendar.current
        let interval = selectedRange.interval(from: selectedDate)
        let start = interval.start

        switch selectedRange {
        case .week:
            let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
            let fmt = DateFormatter()
            fmt.dateFormat = "MMM d"
            let startStr = fmt.string(from: start)
            fmt.dateFormat = "d, yyyy"
            let endStr = fmt.string(from: end)
            return "\(startStr)–\(endStr)"
        case .month:
            let fmt = DateFormatter()
            fmt.dateFormat = "MMMM yyyy"
            return fmt.string(from: start)
        case .year:
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy"
            return fmt.string(from: start)
        }
    }

    func load() {
        overallSummary = repository.summary(for: selectedRange, from: selectedDate)
        sportSummaries = WorkoutType.allCases.map { type in
            repository.summary(for: selectedRange, from: selectedDate, type: type)
        }.filter { $0.workoutCount > 0 }
    }

    func selectRange(_ range: DateRange) {
        selectedRange = range
        selectedDate = .now
        load()
    }

    func goBack() {
        let calendar = Calendar.current
        switch selectedRange {
        case .week:
            selectedDate = calendar.date(byAdding: .weekOfYear, value: -1, to: selectedDate) ?? selectedDate
        case .month:
            selectedDate = calendar.date(byAdding: .month, value: -1, to: selectedDate) ?? selectedDate
        case .year:
            selectedDate = calendar.date(byAdding: .year, value: -1, to: selectedDate) ?? selectedDate
        }
        load()
    }

    func goForward() {
        guard canGoForward else { return }
        let calendar = Calendar.current
        switch selectedRange {
        case .week:
            selectedDate = calendar.date(byAdding: .weekOfYear, value: 1, to: selectedDate) ?? selectedDate
        case .month:
            selectedDate = calendar.date(byAdding: .month, value: 1, to: selectedDate) ?? selectedDate
        case .year:
            selectedDate = calendar.date(byAdding: .year, value: 1, to: selectedDate) ?? selectedDate
        }
        load()
    }
}
