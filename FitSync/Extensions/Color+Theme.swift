import SwiftUI

extension Color {
    static let runningColor = Color.green
    static let cyclingColor = Color.orange
    static let swimmingColor = Color.blue

    static func forWorkoutType(_ type: WorkoutType) -> Color {
        switch type {
        case .running: .runningColor
        case .cycling: .cyclingColor
        case .swimming: .swimmingColor
        }
    }
}
