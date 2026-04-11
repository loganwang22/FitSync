# FitSync

A native iOS app that reads workout data from Apple HealthKit, persists it locally with SwiftData, and visualizes activity, summaries, and trends — running, cycling, and swimming.

FitSync has **read-only** access to Health. It never writes samples back.

## Features

- **Workout list** — unified history of runs, rides, and swims pulled from HealthKit
- **Workout detail**
  - Distance, duration, pace/speed, calories
  - Stacked **heart rate + elevation** chart over the workout timeline
  - Route map drawn from persisted GPS points
  - Running-specific metrics: avg/max HR, cadence, ground contact time, stride length, vertical oscillation, power, ascent
- **Summary dashboard** — week / month / year aggregation of distance, duration, calories, and elevation gain
- **Trends** — longitudinal view across workout types
- **Onboarding** — HealthKit permission flow + "how far back to import" selector (default 12 months)

## Requirements

- iOS 17.0+ (SwiftUI, SwiftData, Swift Charts, and the Observation framework)
- Xcode 15+
- Swift 5
- A device or simulator with synthesized Health data (HealthKit is unavailable on a fresh simulator — use **Features → Health** to populate samples before running sync)

No external package dependencies.

## Build & Run

```sh
# Build for simulator (generic — works regardless of which sim images you have)
xcodebuild -project FitSync.xcodeproj -scheme FitSync \
  -destination 'generic/platform=iOS Simulator' build

# Clean
xcodebuild -project FitSync.xcodeproj -scheme FitSync clean
```

Or just open `FitSync.xcodeproj` in Xcode and hit run.

- Bundle ID: `com.loganwang.FitSync`
- Target: iPhone only, iOS 17.0+

## Architecture

MVVM with a small service layer. The object graph is wired up once in `FitSyncApp` and passed down by dependency injection — no singletons, no environment objects for services.

```
HealthKit (HKWorkout, HKWorkoutRoute, HKQuantitySample)
        │
        ▼
HealthKitService         ── async/await wrappers over HK queries
        │
        ▼
SyncCoordinator          ── @MainActor, maps HKWorkout → Workout,
        │                   dedupes by UUID, backfills elevation
        ▼
WorkoutRepository        ── SwiftData ModelContext wrapper:
        │                   CRUD + range/type queries + aggregation
        ▼
ViewModels (@Observable) ── WorkoutList / WorkoutDetail / Summary / Trends
        │
        ▼
SwiftUI Views
```

### Directory layout

```
FitSync/
├── App/            @main entry + DI wiring
├── Models/         SwiftData @Models (Workout, RoutePoint) + value types
├── Services/       HealthKitService, WorkoutRepository, SyncCoordinator
├── ViewModels/     One @Observable view model per top-level screen
├── Views/          Grouped by feature (Root, Onboarding, WorkoutList, ...)
├── Components/     Shared SwiftUI components
├── Extensions/     Color theme, formatting helpers
└── Resources/      Asset catalog + FitSync.entitlements (HealthKit)
```

### Key invariants

- **`Workout.healthKitUUID` is the unique dedup key.** Incremental sync builds a `[uuid: Workout]` map from the repository on each run and inserts only UUIDs not already persisted.
- **SwiftData predicates cannot use enum values directly.** `Workout.type` is a computed `WorkoutType`; the stored column is `typeRawValue: Int`. Filtering must compare against a local `let rawValue = type.rawValue` captured outside the predicate — see `WorkoutRepository.fetchWorkouts(in:...)`.
- **Route points are unordered** (`@Relationship` collections have no guaranteed iteration order). Anything drawing a path — map polylines, elevation charts — must go through `Workout.sortedRoutePoints`, or `MapPolyline` will connect points in arbitrary order.
- **SwiftData `@Model` reads must stay on the main actor.** Off-actor reads return garbage (e.g. `workout.startDate` reporting the wrong date), which silently breaks chart domains. `WorkoutDetailViewModel` is `@MainActor` for this reason.
- **Cadence is source-filtered** to the workout's own source (typically Apple Watch). Without filtering, the iPhone motion coprocessor contributes a parallel set of step samples for the same window, roughly doubling the result.
- **Elevation** is read from `HKMetadataKeyElevationAscended` when available and falls back to GPS altitude derivation (with a 1 m noise threshold and 20 m vertical-accuracy filter). Only running and cycling get elevation; swimming stays `nil`.
- **Derived metrics** (`avgPaceSecondsPerKm`, `avgSpeedMps`) are computed in `SyncCoordinator.mapWorkout` at import time. Changing the formulas does *not* recompute existing rows — a resync or migration is needed.

### Adding a new workout type

Update three spots:
1. Add a case to `WorkoutType`
2. Map it in `HealthKitService.hkActivityType(for:)`
3. Handle it in `SyncCoordinator.mapWorkout`

### Adding files

The Xcode project uses a `PBXFileSystemSynchronizedRootGroup` pointing at `FitSync/`, so **new Swift files added anywhere under `FitSync/` are picked up automatically** — no `project.pbxproj` edits needed.

## HealthKit permissions

Declared in `Info.plist`:

- `NSHealthShareUsageDescription` — read access explanation
- `NSHealthUpdateUsageDescription` — present but the app never writes

Read types are declared in `HealthKitService.readTypes`. When you add a new read type, existing installs need to re-prompt — `FitSyncApp` calls `requestAuthorization()` on every launch, which is a no-op for types the user has already decided on but will trigger a fresh sheet for anything new.
