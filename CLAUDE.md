# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

FitSync is a native iOS app (iOS 17+, SwiftUI, SwiftData) that reads workout data from Apple HealthKit, persists it locally, and visualizes activity, summaries, and trends. Read-only HealthKit access — the app never writes to Health.

- Bundle ID: `com.loganwang.FitSync`
- Target: iPhone only (`TARGETED_DEVICE_FAMILY = 1`), iOS 17.0+
- Swift 5, no external package dependencies

## Build / Run / Test

This is an Xcode project with no SwiftPM manifest and no test target. Use `xcodebuild` from the repo root (project file is `FitSync.xcodeproj`, scheme is `FitSync`).

```sh
# Build for the simulator
xcodebuild -project FitSync.xcodeproj -scheme FitSync \
  -destination 'platform=iOS Simulator,name=iPhone 15' build

# Clean
xcodebuild -project FitSync.xcodeproj -scheme FitSync clean
```

HealthKit requires a real device or a simulator with synthesized Health data — in the simulator, use Features → Health → populate sample data before running sync. Onboarding will otherwise show empty state.

The Xcode project uses a `PBXFileSystemSynchronizedRootGroup` pointing at `FitSync/`, so **new Swift files added anywhere under `FitSync/` are picked up automatically** — there's no need to edit `project.pbxproj` when adding files.

## Architecture

MVVM + a small service layer. The object graph is wired up once in `FitSyncApp` and passed down by dependency injection (no singletons, no environment objects for services).

### Startup and onboarding flow (`App/FitSyncApp.swift`)

Three-state root driven by two `@AppStorage` flags (`hasCompletedOnboarding`, `historicalDataMonths`):

1. `HealthKitPermissionView` — requests HealthKit authorization on first launch.
2. `DataRangeSelectionView` — user picks how many months of history to import.
3. `ContentView` — the main `TabView` (Activity / Summary / Trends).

`WorkoutRepository` and `SyncCoordinator` are created lazily in `.onAppear` after the `ModelContainer` exists and onboarding is complete. When you add new top-level services, follow this same pattern — construct them in `FitSyncApp` and inject, don't reach for singletons.

### The data pipeline

```
HealthKit (HKWorkout, HKWorkoutRoute, HKQuantitySample)
        │
        ▼
HealthKitService        ──  pure HK access, async/await
        │
        ▼
SyncCoordinator         ──  @Observable, @MainActor sync,
        │                   maps HKWorkout → Workout, dedupes by UUID
        ▼
WorkoutRepository       ──  SwiftData ModelContext wrapper:
        │                   CRUD + range/type queries + aggregation
        ▼
ViewModels (@Observable) ── WorkoutListVM, WorkoutDetailVM,
        │                   SummaryVM, TrendsVM
        ▼
SwiftUI Views           ──  WorkoutList, WorkoutDetail, Summary, Trends
```

Key invariants:

- **`Workout.healthKitUUID` is the unique key.** `SyncCoordinator.performSync` fetches existing UUIDs via `WorkoutRepository.allHealthKitUUIDs()` and only inserts new ones — incremental sync is based on `lastSyncDate`, with an initial pull going back `historicalMonths` (default 12).
- **SwiftData predicates cannot use enum values directly.** `Workout.type` is a computed `WorkoutType`, but the stored property is `typeRawValue: Int`. Any `#Predicate<Workout>` filtering by type must read `typeRawValue` and compare to a local `let rawValue = type.rawValue` captured outside the predicate — see `WorkoutRepository.fetchWorkouts(in:...)` for the pattern.
- **Route points cascade delete** via `@Relationship(deleteRule: .cascade, inverse: \RoutePoint.workout)` on `Workout.routePoints`. Don't manually delete `RoutePoint`s.
- `HealthKitService` maps between `WorkoutType` (running/cycling/swimming only) and `HKWorkoutActivityType`. If you add a new workout type, update `WorkoutType`, `HealthKitService.hkActivityType(for:)`, and the `switch` in `SyncCoordinator.mapWorkout`.
- Derived metrics (`avgPaceSecondsPerKm`, `avgSpeedMps`) are computed at **map time** in `SyncCoordinator.mapWorkout`, not at read time. If you change the formulas, existing persisted workouts won't be recomputed — a resync (or a migration) is needed.

### Directory layout under `FitSync/`

- `App/` — `@main` entry point + DI wiring
- `Models/` — SwiftData `@Model`s (`Workout`, `RoutePoint`), value types (`WorkoutType`, `WorkoutSummary`, `DateRange`)
- `Services/` — `HealthKitService`, `WorkoutRepository`, `SyncCoordinator`
- `ViewModels/` — one `@Observable` view model per top-level screen
- `Views/` — grouped by feature (`Root`, `Onboarding`, `WorkoutList`, `WorkoutDetail`, `Summary`, `Trends`)
- `Components/` — shared SwiftUI components (`WorkoutIcon`, `StatLabel`, ...)
- `Extensions/` — `Color+Theme`, `Formatting+Extensions`
- `Resources/` — asset catalog + `FitSync.entitlements` (HealthKit capability)

### Conventions

- View models are `@Observable` (Swift Observation framework), not `ObservableObject`. Mutations that touch SwiftData or UI must be `@MainActor`.
- Views receive their VM as a `let`, constructed by the parent — see `ContentView` for the wiring.
- Formatting helpers (pace, duration, distance) live on the model/summary types themselves (`Workout.formattedPace`, `WorkoutSummary.formattedDuration`). Prefer extending these over scattering `String(format:)` calls in views.
