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

    var formattedElevation: String {
        String(format: "%.0f m", self)
    }

    var formattedCadence: String {
        String(format: "%.0f spm", self)
    }

    var formattedGroundContact: String {
        String(format: "%.0f ms", self)
    }

    var formattedStride: String {
        String(format: "%.2f m", self)
    }

    var formattedVerticalOscillation: String {
        String(format: "%.1f cm", self)
    }

    var formattedPower: String {
        String(format: "%.0f W", self)
    }
}

extension Date {
    var shortFormatted: String {
        formatted(date: .abbreviated, time: .shortened)
    }
}
