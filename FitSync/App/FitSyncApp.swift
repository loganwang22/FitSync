import SwiftUI
import SwiftData

@main
struct FitSyncApp: App {
    @State private var healthKit = HealthKitService()
    @State private var syncCoordinator: SyncCoordinator?
    @State private var repository: WorkoutRepository?
    @State private var coachTaskManager = CoachTaskManager()

    let container: ModelContainer

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("historicalDataMonths") private var historicalDataMonths = 0

    @State private var healthKitAuthorized = false

    init() {
        do {
            container = try ModelContainer(for: Workout.self, RoutePoint.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding, let repository, let syncCoordinator {
                    ContentView(
                        healthKit: healthKit,
                        syncCoordinator: syncCoordinator,
                        repository: repository
                    )
                    .environment(coachTaskManager)
                } else if hasCompletedOnboarding {
                    // Services still initializing — avoid flashing onboarding
                    Color(.systemBackground)
                } else if healthKitAuthorized {
                    DataRangeSelectionView { months in
                        historicalDataMonths = months
                        hasCompletedOnboarding = true
                    }
                } else {
                    HealthKitPermissionView(healthKit: healthKit) {
                        healthKitAuthorized = true
                    }
                }
            }
            .onAppear {
                if repository == nil {
                    let repo = WorkoutRepository(context: container.mainContext)
                    repository = repo
                    if hasCompletedOnboarding {
                        syncCoordinator = SyncCoordinator(
                            healthKit: healthKit,
                            repository: repo,
                            historicalMonths: historicalDataMonths > 0 ? historicalDataMonths : 12
                        )
                    }
                }
            }
            .task {
                // Re-request HealthKit authorization on every launch so that any
                // newly added read types (e.g. running stride length, step count)
                // get prompted for on existing installs. This is a no-op for types
                // the user has already decided on.
                if hasCompletedOnboarding {
                    try? await healthKit.requestAuthorization()
                }
            }
            .onChange(of: hasCompletedOnboarding) {
                if hasCompletedOnboarding, syncCoordinator == nil, let repository {
                    syncCoordinator = SyncCoordinator(
                        healthKit: healthKit,
                        repository: repository,
                        historicalMonths: historicalDataMonths
                    )
                }
            }
        }
        .modelContainer(container)
    }
}
