import SwiftUI
import MapKit
import Charts

struct WorkoutDetailView: View {
    @State private var viewModel: WorkoutDetailViewModel

    init(workout: Workout) {
        _viewModel = State(initialValue: WorkoutDetailViewModel(workout: workout))
    }

    private var workout: Workout { viewModel.workout }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    WorkoutIcon(type: workout.type, size: 48)
                    VStack(alignment: .leading) {
                        Text(workout.type.label)
                            .font(.title2.bold())
                        Text(workout.startDate.shortFormatted)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)

                // Stats Grid
                WorkoutStatsGrid(workout: workout, viewModel: viewModel)
                    .padding(.horizontal)

                // HR + Elevation combined chart
                if viewModel.hasHeartRateSeries || viewModel.hasElevationSeries {
                    HeartRateElevationChart(
                        hrPoints: viewModel.heartRatePoints,
                        elevPoints: viewModel.elevationPoints,
                        totalDuration: workout.durationSeconds
                    )
                    .padding(.horizontal)
                }

                // Route Map
                if !workout.routePoints.isEmpty {
                    VStack(alignment: .leading) {
                        Text("Route")
                            .font(.headline)
                            .padding(.horizontal)
                        RouteMapView(routePoints: workout.sortedRoutePoints)
                            .frame(height: 250)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical)
        }
        .task { await viewModel.load() }
        .navigationTitle("Workout")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct WorkoutStatsGrid: View {
    let workout: Workout
    let viewModel: WorkoutDetailViewModel

    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
        ], spacing: 16) {
            if let dist = workout.distanceMeters {
                StatCard(title: "Distance", value: workout.type == .swimming ? dist.formattedDistanceM : dist.formattedDistanceKm, icon: "arrow.left.and.right")
            }

            StatCard(title: "Duration", value: workout.durationSeconds.formattedDuration, icon: "clock")

            if let cal = workout.activeEnergyKcal {
                StatCard(title: "Calories", value: cal.formattedCalories, icon: "flame")
            }

            if let pace = workout.avgPaceSecondsPerKm {
                StatCard(title: "Pace", value: pace.formattedPace, icon: "speedometer")
            }

            if let speed = workout.avgSpeedMps {
                StatCard(title: "Speed", value: speed.formattedSpeed, icon: "gauge.with.dots.needle.67percent")
            }

            if let gain = workout.elevationGainMeters,
               workout.type == .running || workout.type == .cycling {
                StatCard(title: "Ascent", value: gain.formattedElevation, icon: "arrow.up.right")
            }

            if workout.type == .running {
                if let hr = viewModel.avgHeartRate {
                    StatCard(title: "Avg HR", value: hr.formattedHeartRate, icon: "heart.fill")
                }
                if let maxHR = viewModel.maxHeartRate {
                    StatCard(title: "Max HR", value: maxHR.formattedHeartRate, icon: "heart.fill")
                }
                if let cadence = viewModel.avgCadenceSpm {
                    StatCard(title: "Cadence", value: String(format: "%.0f spm", cadence), icon: "metronome")
                }
                if let gct = viewModel.avgGroundContactTimeMs {
                    StatCard(title: "Ground Contact", value: String(format: "%.0f ms", gct), icon: "shoeprints.fill")
                }
                if let stride = viewModel.avgStrideLengthMeters {
                    StatCard(title: "Stride", value: String(format: "%.2f m", stride), icon: "ruler")
                }
                if let vertical = viewModel.avgVerticalOscillationCm {
                    StatCard(title: "Vert. Oscillation", value: String(format: "%.1f cm", vertical), icon: "arrow.up.and.down")
                }
                if let power = viewModel.avgRunningPowerWatts {
                    StatCard(title: "Power", value: String(format: "%.0f W", power), icon: "bolt.fill")
                }
            }

            if let strokes = workout.strokeCount {
                StatCard(title: "Strokes", value: "\(strokes)", icon: "drop")
            }

            if let laps = workout.laps {
                StatCard(title: "Laps", value: "\(laps)", icon: "arrow.triangle.2.circlepath")
            }
        }
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// Two stacked charts sharing the same time domain. The top chart plots heart
/// rate over time; the bottom chart plots elevation. Stacking rather than
/// overlaying lets each metric keep its own y-scale while still allowing the
/// reader to visually correlate HR bumps with climbs.
struct HeartRateElevationChart: View {
    let hrPoints: [WorkoutDetailViewModel.HeartRatePoint]
    let elevPoints: [WorkoutDetailViewModel.ElevationPoint]
    let totalDuration: Double

    private var domain: ClosedRange<Double> {
        0 ... max(totalDuration, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Heart Rate & Elevation")
                .font(.headline)

            if !hrPoints.isEmpty {
                Label("Heart rate (bpm)", systemImage: "heart.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Chart {
                    ForEach(hrPoints) { point in
                        LineMark(
                            x: .value("Time", point.secondsFromStart),
                            y: .value("BPM", point.bpm)
                        )
                        .foregroundStyle(.red)
                        .interpolationMethod(.monotone)
                    }
                }
                .frame(height: 140)
                .chartXScale(domain: domain)
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
            }

            if !elevPoints.isEmpty {
                Label("Elevation (m)", systemImage: "mountain.2.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Chart {
                    ForEach(elevPoints) { point in
                        AreaMark(
                            x: .value("Time", point.secondsFromStart),
                            y: .value("Meters", point.meters)
                        )
                        .foregroundStyle(Color.blue.opacity(0.25))
                        .interpolationMethod(.monotone)

                        LineMark(
                            x: .value("Time", point.secondsFromStart),
                            y: .value("Meters", point.meters)
                        )
                        .foregroundStyle(.blue)
                        .interpolationMethod(.monotone)
                    }
                }
                .frame(height: 90)
                .chartXScale(domain: domain)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let seconds = value.as(Double.self) {
                                Text(Self.formatTime(seconds))
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private static func formatTime(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

struct RouteMapView: View {
    let routePoints: [RoutePoint]

    private var coordinates: [CLLocationCoordinate2D] {
        routePoints.map(\.coordinate)
    }

    var body: some View {
        Map {
            MapPolyline(coordinates: coordinates)
                .stroke(.blue, lineWidth: 4)
        }
        .mapStyle(.standard(elevation: .realistic))
    }
}
