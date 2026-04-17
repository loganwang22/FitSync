import Foundation

enum TrainingGoal: Int, Codable, CaseIterable, Identifiable {
    case generalFitness = 0
    case fiveK = 1
    case tenK = 2
    case halfMarathon = 3
    case marathon = 4
    case olympicTriathlon = 5
    case triathlon = 6  // Ironman / long-distance

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .generalFitness: "General Fitness"
        case .fiveK: "5K"
        case .tenK: "10K"
        case .halfMarathon: "Half Marathon"
        case .marathon: "Marathon"
        case .olympicTriathlon: "Olympic Triathlon"
        case .triathlon: "Ironman Triathlon"
        }
    }

    var systemImage: String {
        switch self {
        case .generalFitness: "heart.fill"
        case .fiveK, .tenK: "figure.run"
        case .halfMarathon, .marathon: "figure.run.circle.fill"
        case .olympicTriathlon, .triathlon: "medal.fill"
        }
    }

    var description: String {
        switch self {
        case .generalFitness: "Stay active and healthy with balanced training"
        case .fiveK: "Build speed and endurance for a 5K race"
        case .tenK: "Train for a strong 10K performance"
        case .halfMarathon: "Prepare for 21.1 km with structured long runs"
        case .marathon: "Full 42.2 km marathon preparation"
        case .olympicTriathlon: "Swim 1.5K, Bike 40K, Run 10K"
        case .triathlon: "Swim 3.8K, Bike 180K, Run 42.2K"
        }
    }

    var weeklyTargets: WeeklyTargets {
        switch self {
        case .generalFitness:
            WeeklyTargets(sessionsPerWeek: 3, runKm: 15, cycleKm: 0, swimM: 0, crossTrainDays: 1)
        case .fiveK:
            WeeklyTargets(sessionsPerWeek: 4, runKm: 25, cycleKm: 0, swimM: 0, crossTrainDays: 1)
        case .tenK:
            WeeklyTargets(sessionsPerWeek: 4, runKm: 35, cycleKm: 0, swimM: 0, crossTrainDays: 1)
        case .halfMarathon:
            WeeklyTargets(sessionsPerWeek: 5, runKm: 45, cycleKm: 0, swimM: 0, crossTrainDays: 1)
        case .marathon:
            WeeklyTargets(sessionsPerWeek: 5, runKm: 60, cycleKm: 0, swimM: 0, crossTrainDays: 1)
        case .olympicTriathlon:
            WeeklyTargets(sessionsPerWeek: 6, runKm: 25, cycleKm: 80, swimM: 3000, crossTrainDays: 0)
        case .triathlon:
            WeeklyTargets(sessionsPerWeek: 7, runKm: 40, cycleKm: 150, swimM: 5000, crossTrainDays: 0)
        }
    }

    var involvedSports: [WorkoutType] {
        switch self {
        case .generalFitness: [.running, .cycling, .swimming]
        case .fiveK, .tenK, .halfMarathon, .marathon: [.running]
        case .olympicTriathlon, .triathlon: [.running, .cycling, .swimming]
        }
    }

    struct WeeklyTargets {
        let sessionsPerWeek: Int
        let runKm: Double
        let cycleKm: Double
        let swimM: Double       // meters
        let crossTrainDays: Int
    }
}
