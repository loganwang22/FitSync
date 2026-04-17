import SwiftUI
import MapKit

/// A stylish share card with the route map as background and workout stats overlaid.
struct WorkoutShareCard: View {
    let mapImage: UIImage
    let workout: Workout
    let avgHeartRate: Double?
    let elevationGain: Double?

    private var dateString: String {
        workout.startDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year())
    }

    var body: some View {
        ZStack {
            // Map background
            Image(uiImage: mapImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 390, height: 520)
                .clipped()

            // Dark gradient overlay for readability
            LinearGradient(
                colors: [
                    .black.opacity(0.7),
                    .clear,
                    .clear,
                    .black.opacity(0.85),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Content
            VStack {
                // Top: workout type + date
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(workout.type.label.uppercased())
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .tracking(2)
                            .foregroundStyle(.white.opacity(0.8))
                        Text(dateString)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                    Image(systemName: workoutIcon)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)

                Spacer()

                // Bottom: key stats
                VStack(spacing: 16) {
                    // Primary metric (distance)
                    if let dist = workout.distanceMeters {
                        VStack(spacing: 2) {
                            Text(primaryDistance(dist))
                                .font(.system(size: 56, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Text(primaryUnit)
                                .font(.system(size: 16, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.6))
                                .tracking(1)
                        }
                    }

                    // Secondary stats row
                    HStack(spacing: 0) {
                        statItem(
                            value: workout.durationSeconds.formattedDuration,
                            label: "Duration"
                        )

                        if let pace = paceOrSpeed {
                            divider
                            statItem(value: pace.value, label: pace.label)
                        }

                        if let hr = avgHeartRate {
                            divider
                            statItem(
                                value: String(format: "%.0f", hr),
                                label: "Avg HR"
                            )
                        }

                        if let gain = elevationGain, gain > 0 {
                            divider
                            statItem(
                                value: String(format: "%.0f m", gain),
                                label: "Elevation"
                            )
                        }
                    }
                    .padding(.horizontal, 8)

                    // App branding
                    HStack(spacing: 4) {
                        Text("FitSync")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    .padding(.bottom, 4)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
        }
        .frame(width: 390, height: 520)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Helpers

    private var workoutIcon: String {
        switch workout.type {
        case .running: "figure.run"
        case .cycling: "figure.outdoor.cycle"
        case .swimming: "figure.pool.swim"
        }
    }

    private func primaryDistance(_ meters: Double) -> String {
        if workout.type == .swimming {
            return String(format: "%.0f", meters)
        }
        return String(format: "%.2f", meters / 1000.0)
    }

    private var primaryUnit: String {
        workout.type == .swimming ? "METERS" : "KILOMETERS"
    }

    private var paceOrSpeed: (value: String, label: String)? {
        if workout.type == .cycling, let speed = workout.avgSpeedMps {
            return (speed.formattedSpeed, "Avg Speed")
        }
        if workout.type == .swimming, let speed = workout.avgSpeedMps, speed > 0 {
            let pace = 100.0 / speed
            return (pace.formattedSwimmingPace, "Pace")
        }
        if let pace = workout.avgPaceSecondsPerKm {
            return (pace.formattedPace, "Pace")
        }
        return nil
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.2))
            .frame(width: 1, height: 28)
    }
}

// MARK: - Map Snapshotter

enum MapSnapshotter {
    @MainActor
    static func snapshot(
        routePoints: [RoutePoint],
        size: CGSize = CGSize(width: 390, height: 520),
        scale: CGFloat = UIScreen.main.scale
    ) async -> UIImage? {
        let coordinates = routePoints.map(\.coordinate)
        guard !coordinates.isEmpty else { return nil }

        // Compute region with padding
        var minLat = coordinates[0].latitude
        var maxLat = coordinates[0].latitude
        var minLon = coordinates[0].longitude
        var maxLon = coordinates[0].longitude
        for coord in coordinates {
            minLat = min(minLat, coord.latitude)
            maxLat = max(maxLat, coord.latitude)
            minLon = min(minLon, coord.longitude)
            maxLon = max(maxLon, coord.longitude)
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: (maxLat - minLat) * 1.4,
            longitudeDelta: (maxLon - minLon) * 1.4
        )
        let region = MKCoordinateRegion(center: center, span: span)

        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = size
        options.scale = scale
        options.mapType = .standard

        let snapshotter = MKMapSnapshotter(options: options)
        guard let snapshot = try? await snapshotter.start() else { return nil }

        // Draw the route polyline on the snapshot
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            snapshot.image.draw(at: .zero)

            let path = UIBezierPath()
            for (i, coord) in coordinates.enumerated() {
                let point = snapshot.point(for: coord)
                if i == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }

            ctx.cgContext.setStrokeColor(UIColor.systemBlue.cgColor)
            ctx.cgContext.setLineWidth(3.5)
            ctx.cgContext.setLineCap(.round)
            ctx.cgContext.setLineJoin(.round)
            ctx.cgContext.addPath(path.cgPath)
            ctx.cgContext.strokePath()
        }
    }
}
