import Foundation
import HealthKit
import CoreLocation

final class HealthKitService {
    private let store = HKHealthStore()

    private let readTypes: Set<HKObjectType> = {
        var types: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.distanceCycling),
            HKQuantityType(.distanceSwimming),
            HKQuantityType(.swimmingStrokeCount),
            HKQuantityType(.stepCount),
            HKQuantityType(.runningGroundContactTime),
            HKQuantityType(.runningStrideLength),
            HKQuantityType(.runningVerticalOscillation),
            HKQuantityType(.runningPower),
        ]
        types.insert(HKSeriesType.workoutRoute())
        return types
    }()

    static var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization() async throws {
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    // MARK: - Fetch Workouts

    func fetchWorkouts(
        types: [WorkoutType] = WorkoutType.allCases,
        from startDate: Date,
        to endDate: Date = .now
    ) async throws -> [HKWorkout] {
        let hkTypes = types.map { hkActivityType(for: $0) }
        let datePredicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)

        var allWorkouts: [HKWorkout] = []

        for hkType in hkTypes {
            let activityPredicate = HKQuery.predicateForWorkouts(with: hkType)
            let compound = NSCompoundPredicate(andPredicateWithSubpredicates: [activityPredicate, datePredicate])

            let descriptor = HKSampleQueryDescriptor(
                predicates: [.sample(type: .workoutType(), predicate: compound)],
                sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)]
            )

            let results = try await descriptor.result(for: store)
            allWorkouts.append(contentsOf: results.compactMap { $0 as? HKWorkout })
        }

        return allWorkouts.sorted { $0.startDate > $1.startDate }
    }

    // MARK: - Fetch Route

    func fetchRoute(for workout: HKWorkout) async throws -> [CLLocation] {
        let routeType = HKSeriesType.workoutRoute()
        let predicate = HKQuery.predicateForObjects(from: workout)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.sample(type: routeType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let routes = try await descriptor.result(for: store)
        guard let route = routes.first as? HKWorkoutRoute else { return [] }

        return try await withCheckedThrowingContinuation { continuation in
            var allLocations: [CLLocation] = []
            let query = HKWorkoutRouteQuery(route: route) { _, locations, done, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if let locations {
                    allLocations.append(contentsOf: locations)
                }
                if done {
                    continuation.resume(returning: allLocations)
                }
            }
            store.execute(query)
        }
    }

    // MARK: - Fetch Heart Rate

    func fetchHeartRateSamples(for workout: HKWorkout) async throws -> [(date: Date, bpm: Double)] {
        let hrType = HKQuantityType(.heartRate)
        let predicate = HKQuery.predicateForSamples(
            withStart: workout.startDate,
            end: workout.endDate
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: hrType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let samples = try await descriptor.result(for: store)
        return samples.map { sample in
            let bpm = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            return (date: sample.startDate, bpm: bpm)
        }
    }

    // MARK: - Helpers

    private func hkActivityType(for type: WorkoutType) -> HKWorkoutActivityType {
        switch type {
        case .running: .running
        case .cycling: .cycling
        case .swimming: .swimming
        }
    }
}
