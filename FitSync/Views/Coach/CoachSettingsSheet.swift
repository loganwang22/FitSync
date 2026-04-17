import SwiftUI

struct CoachSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedProvider = AICoachService.selectedProvider
    @State private var apiKey = ""
    @State private var aiEnabled = AICoachService.isEnabled
    @State private var testStatus: String?
    @State private var isTesting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("AI Enhancement") {
                    Toggle("Enable AI Coach", isOn: $aiEnabled)
                        .onChange(of: aiEnabled) { _, val in
                            AICoachService.isEnabled = val
                        }

                    if aiEnabled {
                        Picker("Provider", selection: $selectedProvider) {
                            ForEach(AICoachService.Provider.allCases) { p in
                                Text(p.rawValue).tag(p)
                            }
                        }
                        .onChange(of: selectedProvider) { _, val in
                            AICoachService.selectedProvider = val
                            apiKey = AICoachService.loadAPIKey(for: val)
                        }

                        SecureField("API Key", text: $apiKey)
                            .textContentType(.password)
                            .autocorrectionDisabled()
                            .onSubmit { saveKey() }

                        Button {
                            saveKey()
                            Task { await testConnection() }
                        } label: {
                            HStack {
                                Text("Test Connection")
                                if isTesting {
                                    Spacer()
                                    ProgressView()
                                        .controlSize(.small)
                                }
                            }
                        }
                        .disabled(apiKey.isEmpty || isTesting)

                        if let status = testStatus {
                            Text(status)
                                .font(.caption)
                                .foregroundStyle(status.contains("Success") ? .green : .red)
                        }
                    }
                }

                Section {
                    Text("AI enhancement sends workout metrics to the selected provider's API for deeper analysis. Your API key is stored in the device Keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Coach Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        saveKey()
                        dismiss()
                    }
                }
            }
            .onAppear {
                apiKey = AICoachService.loadAPIKey(for: selectedProvider)
            }
        }
    }

    private func saveKey() {
        AICoachService.saveAPIKey(apiKey, for: selectedProvider)
    }

    private func testConnection() async {
        isTesting = true
        testStatus = nil

        do {
            let enhanced = try await AICoachService.shared.enhance(
                workout: makeTestWorkout(),
                baseAnalysis: CoachAnalysis(
                    observations: [],
                    recommendations: [],
                    suggestedWorkouts: [],
                    source: .onDevice,
                    generatedDate: .now
                ),
                recentWorkouts: [],
                goal: nil
            )
            testStatus = "Success — \(enhanced.observations.count) observations"
        } catch {
            testStatus = "Error: \(error.localizedDescription)"
        }

        isTesting = false
    }

    private func makeTestWorkout() -> Workout {
        Workout(
            healthKitUUID: "test",
            type: .running,
            startDate: .now.addingTimeInterval(-1800),
            endDate: .now,
            durationSeconds: 1800,
            distanceMeters: 5000,
            avgPaceSecondsPerKm: 360
        )
    }
}
