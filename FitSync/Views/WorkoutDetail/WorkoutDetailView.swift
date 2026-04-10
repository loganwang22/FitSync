import SwiftUI
import MapKit
import Charts

struct WorkoutDetailView: View {
    let workout: Workout

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
                WorkoutStatsGrid(workout: workout)
                    .padding(.horizontal)

                // Route Map
                if !workout.routePoints.isEmpty {
                    VStack(alignment: .leading) {
                        Text("Route")
                            .font(.headline)
                            .padding(.horizontal)
                        RouteMapView(routePoints: workout.routePoints)
                            .frame(height: 250)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal)
                    }
                }

                // Heart Rate (placeholder for now)
                if workout.avgHeartRate != nil {
                    VStack(alignment: .leading) {
                        Text("Heart Rate")
                            .font(.headline)
                            .padding(.horizontal)
                        HStack {
                            StatLabel("Average", value: workout.avgHeartRate?.formattedHeartRate ?? "-", icon: "heart.fill")
                            if let max = workout.maxHeartRate {
                                StatLabel("Max", value: max.formattedHeartRate, icon: "heart.fill")
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Workout")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct WorkoutStatsGrid: View {
    let workout: Workout

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
