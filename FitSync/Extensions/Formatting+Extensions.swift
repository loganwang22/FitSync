import Foundation

extension TimeInterval {
    var formattedDuration: String {
        let hours = Int(self) / 3600
        let minutes = (Int(self) % 3600) / 60
        let seconds = Int(self) % 60

        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        }
        return String(format: "%dm %02ds", minutes, seconds)
    }
}

extension Double {
    var formattedDistanceKm: String {
        let km = self / 1000.0
        return String(format: "%.2f km", km)
    }

    var formattedDistanceM: String {
        String(format: "%.0f m", self)
    }

    var formattedCalories: String {
        String(format: "%.0f kcal", self)
    }

    var formattedHeartRate: String {
        String(format: "%.0f bpm", self)
    }

    var formattedPace: String {
        let minutes = Int(self) / 60
        let seconds = Int(self) % 60
        return String(format: "%d'%02d\" /km", minutes, seconds)
    }

    var formattedSpeed: String {
        let kmh = self * 3.6
        return String(format: "%.1f km/h", kmh)
    }
}

extension Date {
    var shortFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }

    var dayFormatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: self)
    }

    var timeFormatted: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }
}
