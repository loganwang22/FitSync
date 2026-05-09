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
            HKQuantityType(.cyclingPower),
            HKQuantityType(.vo2Max),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.bodyMass),
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

    // MARK: - Cardio Fitness (VO2 Max)

    struct VO2MaxSample: Identifiable {
        let id = UUID()
        let date: Date
        /// ml/(kg·min)
        let value: Double
    }

    /// Fetches VO2 max samples (Apple's "Cardio Fitness" metric) from HealthKit.
    /// Apple Watch generates these periodically after qualifying outdoor walks/runs.
    func fetchVO2MaxSamples(from startDate: Date, to endDate: Date = .now) async throws -> [VO2MaxSample] {
        let type = HKQuantityType(.vo2Max)
        let unit = HKUnit(from: "ml/kg*min")
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let samples = try await descriptor.result(for: store)
        return samples.map {
            VO2MaxSample(date: $0.startDate, value: $0.quantity.doubleValue(for: unit))
        }
    }

    // MARK: - Resting Heart Rate

    struct RestingHRSample: Identifiable {
        let id = UUID()
        let date: Date
        let bpm: Double
    }

    func fetchRestingHeartRate(from startDate: Date, to endDate: Date = .now) async throws -> [RestingHRSample] {
        let type = HKQuantityType(.restingHeartRate)
        let unit = HKUnit.count().unitDivided(by: .minute())
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let samples = try await descriptor.result(for: store)
        return samples.map {
            RestingHRSample(date: $0.startDate, bpm: $0.quantity.doubleValue(for: unit))
        }
    }

    // MARK: - Heart Rate Variability (SDNN)

    struct HRVSample: Identifiable {
        let id = UUID()
        let date: Date
        /// SDNN in milliseconds
        let ms: Double
    }

    func fetchHRV(from startDate: Date, to endDate: Date = .now) async throws -> [HRVSample] {
        let type = HKQuantityType(.heartRateVariabilitySDNN)
        let unit = HKUnit.secondUnit(with: .milli)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let samples = try await descriptor.result(for: store)
        return samples.map {
            HRVSample(date: $0.startDate, ms: $0.quantity.doubleValue(for: unit))
        }
    }

    // MARK: - Body Mass

    /// Returns the most recent body-mass sample in kilograms, or nil if none.
    /// Needed for power-to-weight ratio.
    func fetchLatestBodyMassKg(asOf date: Date = .now) async throws -> Double? {
        let type = HKQuantityType(.bodyMass)
        let predicate = HKQuery.predicateForSamples(withStart: nil, end: date)
        var descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)]
        )
        descriptor.limit = 1
        let samples = try await descriptor.result(for: store)
        return samples.first?.quantity.doubleValue(for: .gramUnit(with: .kilo))
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
