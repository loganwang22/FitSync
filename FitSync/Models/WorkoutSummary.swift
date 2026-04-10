import Foundation

struct WorkoutSummary: Identifiable {
    let id = UUID()
    let period: DateRange
    let workoutType: WorkoutType?
    let totalDistanceMeters: Double
    let totalDurationSeconds: Double
    let totalCalories: Double
    let workoutCount: Int
    let avgPaceSecondsPerKm: Double?
    let avgHeartRate: Double?

    var totalDistanceKm: Double {
        totalDistanceMeters / 1000.0
    }

    var formattedDistance: String {
        String(format: "%.1f km", totalDistanceKm)
    }

    var formattedDuration: String {
        let hours = Int(totalDurationSeconds) / 3600
        let minutes = (Int(totalDurationSeconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    var formattedCalories: String {
        String(format: "%.0f kcal", totalCalories)
    }
}

enum DateRange: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"
    case year = "Year"

    var id: String { rawValue }

    func interval(from date: Date = .now) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let component: Calendar.Component
        switch self {
        case .week: component = .weekOfYear
        case .month: component = .month
        case .year: component = .year
        }
        guard let di = calendar.dateInterval(of: component, for: date) else {
            return (date, date)
        }
        let end = min(di.end, Date.now)
        return (di.start, end)
    }
}
