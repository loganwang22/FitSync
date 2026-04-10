import SwiftUI

struct ContentView: View {
    let healthKit: HealthKitService
    let syncCoordinator: SyncCoordinator
    let repository: WorkoutRepository

    var body: some View {
        TabView {
            WorkoutListView(viewModel: WorkoutListViewModel(
                repository: repository,
                syncCoordinator: syncCoordinator
            ))
            .tabItem {
                Label("Activity", systemImage: "figure.run")
            }

            SummaryDashboardView(viewModel: SummaryViewModel(
                repository: repository
            ))
            .tabItem {
                Label("Summary", systemImage: "chart.bar.fill")
            }

            TrendsView(viewModel: TrendsViewModel(
                repository: repository
            ))
            .tabItem {
                Label("Trends", systemImage: "chart.line.uptrend.xyaxis")
            }
        }
    }
}
