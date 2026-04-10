import Foundation
import HealthKit

@Observable
final class WorkoutDetailViewModel {
    private let healthKit: HealthKitService
    let workout: Workout

    var heartRateSamples: [(date: Date, bpm: Double)] = []
    var isLoadingHR = false

    init(workout: Workout, healthKit: HealthKitService) {
        self.workout = workout
        self.healthKit = healthKit
    }

    @MainActor
    func loadHeartRate() async {
        guard heartRateSamples.isEmpty else { return }
        isLoadingHR = true
        defer { isLoadingHR = false }

        // Heart rate samples are fetched by date range from HealthKit
        // This works without the original HKWorkout reference
        do {
            let hrType = HKQuantityType(.heartRate)
            let predicate = HKQuery.predicateForSamples(
                withStart: workout.startDate,
                end: workout.endDate
            )
            let descriptor = HKSampleQueryDescriptor(
                predicates: [.quantitySample(type: hrType, predicate: predicate)],
                sortDescriptors: [SortDescriptor(\.startDate)]
            )
            let store = HKHealthStore()
            let samples = try await descriptor.result(for: store)
            heartRateSamples = samples.map { sample in
                let bpm = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                return (date: sample.startDate, bpm: bpm)
            }
        } catch {
            // Silently fail — HR data is optional
        }
    }
}
