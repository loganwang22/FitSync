import Foundation

@Observable
final class SummaryViewModel {
    private let repository: WorkoutRepository
    private let calendar = Calendar.current

    var selectedRange: DateRange = .week
    var selectedDate: Date = .now
    var overallSummary: WorkoutSummary?
    var sportSummaries: [WorkoutSummary] = []

    init(repository: WorkoutRepository) {
        self.repository = repository
    }

    var canGoForward: Bool {
        let component = selectedRange.calendarComponent
        guard let current = calendar.dateInterval(of: component, for: .now),
              let selected = calendar.dateInterval(of: component, for: selectedDate) else {
            return false
        }
        return selected.start < current.start
    }

    var periodLabel: String {
        let start = selectedRange.interval(from: selectedDate).start
        switch selectedRange {
        case .week:
            let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
            let startStr = start.formatted(.dateTime.month(.abbreviated).day())
            let endStr = end.formatted(.dateTime.day().year())
            return "\(startStr)–\(endStr)"
        case .month:
            return start.formatted(.dateTime.month(.wide).year())
        case .year:
            return start.formatted(.dateTime.year())
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
        shiftSelectedDate(by: -1)
    }

    func goForward() {
        guard canGoForward else { return }
        shiftSelectedDate(by: 1)
    }

    private func shiftSelectedDate(by value: Int) {
        selectedDate = calendar.date(
            byAdding: selectedRange.calendarComponent,
            value: value,
            to: selectedDate
        ) ?? selectedDate
        load()
    }
}
