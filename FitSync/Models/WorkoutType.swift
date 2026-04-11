import SwiftUI

enum WorkoutType: Int, Codable, CaseIterable, Identifiable {
    case running = 1
    case cycling = 2
    case swimming = 3

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .running: "Running"
        case .cycling: "Cycling"
        case .swimming: "Swimming"
        }
    }

    var systemImage: String {
        switch self {
        case .running: "figure.run"
        case .cycling: "figure.outdoor.cycle"
        case .swimming: "figure.pool.swim"
        }
    }

    var color: Color {
        switch self {
        case .running: .runningColor
        case .cycling: .cyclingColor
        case .swimming: .swimmingColor
        }
    }
}
