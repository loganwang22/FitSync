import SwiftUI
import HealthKit

struct HealthKitPermissionView: View {
    let healthKit: HealthKitService
    let onComplete: () -> Void

    @State private var isRequesting = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "heart.fill")
                .font(.system(size: 64))
                .foregroundStyle(.red)

            Text("FitSync")
                .font(.largeTitle.bold())

            Text("Connect to Apple Health to see your workouts, routes, and fitness trends.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            VStack(alignment: .leading, spacing: 12) {
                PermissionRow(icon: "figure.run", text: "Running workouts")
                PermissionRow(icon: "figure.outdoor.cycle", text: "Cycling workouts")
                PermissionRow(icon: "figure.pool.swim", text: "Swimming workouts")
                PermissionRow(icon: "heart.fill", text: "Heart rate data")
                PermissionRow(icon: "map", text: "Workout routes")
            }
            .padding(.horizontal, 48)

            Spacer()

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                Task {
                    isRequesting = true
                    do {
                        try await healthKit.requestAuthorization()
                        onComplete()
                    } catch {
                        self.error = error.localizedDescription
                    }
                    isRequesting = false
                }
            } label: {
                if isRequesting {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    Text("Connect Health Data")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .padding(.horizontal, 32)
            .disabled(isRequesting)

            #if targetEnvironment(simulator)
            Button("Skip (Simulator)") {
                onComplete()
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            #endif

            Spacer().frame(height: 32)
        }
    }
}

private struct PermissionRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(.red)
            Text(text)
                .font(.subheadline)
        }
    }
}
