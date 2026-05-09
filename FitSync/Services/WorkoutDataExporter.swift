import Foundation
import CoreLocation

/// Produces a plain-text / Markdown dump of a workout suitable for pasting into
/// an AI chat. Preserves training data; strips identifying info like source
/// device/app name and rounds GPS coordinates to ~1 km precision.
@MainActor
enum WorkoutDataExporter {

    /// Round lat/long to 2 decimal places (~1.1 km at the equator).
    private static let coordinateDecimals = 2

    static func export(workout: Workout, viewModel: WorkoutDetailViewModel) -> String {
        var lines: [String] = []
        lines.append("# Workout Export")
        lines.append("")
        lines.append("_Privacy: GPS coordinates rounded to ~1 km; device/app source name omitted._")
        lines.append("")

        lines.append(contentsOf: overviewSection(workout: workout))
        lines.append(contentsOf: metricsSection(workout: workout, viewModel: viewModel))

        if !viewModel.segments.isEmpty {
            lines.append(contentsOf: splitsSection(segments: viewModel.segments, type: workout.type))
        }

        if !viewModel.cachedRoutePoints.isEmpty {
            lines.append(contentsOf: routeSection(points: viewModel.cachedRoutePoints))
        }

        if !viewModel.heartRatePoints.isEmpty {
            lines.append(contentsOf: heartRateSeriesSection(points: viewModel.heartRatePoints))
        }

        if !viewModel.powerPoints.isEmpty {
            lines.append(contentsOf: powerSeriesSection(points: viewModel.powerPoints))
        }

        if !viewModel.elevationPoints.isEmpty {
            lines.append(contentsOf: elevationSeriesSection(points: viewModel.elevationPoints))
        }

        lines.append("")
        lines.append("_Weather data not available in this export._")

        return lines.joined(separator: "\n")
    }

    // MARK: - Sections

    private static func overviewSection(workout: Workout) -> [String] {
        var out: [String] = []
        out.append("## Overview")
        out.append("")
        out.append("- Type: \(workout.type.label)")
        out.append("- Start: \(isoFormatter.string(from: workout.startDate))")
        out.append("- End: \(isoFormatter.string(from: workout.endDate))")
        out.append("- Duration: \(formatDuration(workout.durationSeconds)) (\(Int(workout.durationSeconds)) s)")
        if let distance = workout.distanceMeters {
            out.append("- Distance: \(String(format: "%.3f", distance / 1000)) km (\(Int(distance)) m)")
        }
        if let kcal = workout.activeEnergyKcal {
            out.append("- Active energy: \(Int(kcal)) kcal")
        }
        if let pace = workout.avgPaceSecondsPerKm {
            out.append("- Avg pace: \(formatPace(pace)) /km")
        }
        if let speed = workout.avgSpeedMps {
            out.append("- Avg speed: \(String(format: "%.2f", speed * 3.6)) km/h (\(String(format: "%.2f", speed)) m/s)")
        }
        if let gain = workout.elevationGainMeters {
            out.append("- Elevation gain: \(Int(gain)) m")
        }
        if let laps = workout.laps {
            out.append("- Laps: \(laps)")
        }
        if let strokes = workout.strokeCount {
            out.append("- Strokes: \(strokes)")
        }
        out.append("")
        return out
    }

    private static func metricsSection(workout: Workout, viewModel: WorkoutDetailViewModel) -> [String] {
        var rows: [String] = []
        if let v = viewModel.avgHeartRate ?? workout.cachedAvgHeartRate {
            rows.append("- Avg HR: \(Int(v)) bpm")
        }
        if let v = viewModel.maxHeartRate ?? workout.cachedMaxHeartRate {
            rows.append("- Max HR: \(Int(v)) bpm")
        }
        if let v = viewModel.avgPowerWatts ?? workout.cachedAvgPowerWatts {
            rows.append("- Avg power: \(Int(v)) W")
        }
        if let v = viewModel.maxPowerWatts ?? workout.cachedMaxPowerWatts {
            rows.append("- Max power: \(Int(v)) W")
        }
        if let v = viewModel.avgCadenceSpm ?? workout.cachedAvgCadenceSpm {
            rows.append("- Avg cadence: \(Int(v)) spm")
        }
        if let v = viewModel.avgGroundContactTimeMs ?? workout.cachedAvgGroundContactTimeMs {
            rows.append("- Avg ground contact time: \(Int(v)) ms")
        }
        if let v = viewModel.avgStrideLengthMeters ?? workout.cachedAvgStrideLengthMeters {
            rows.append("- Avg stride length: \(String(format: "%.2f", v)) m")
        }
        if let v = viewModel.avgVerticalOscillationCm ?? workout.cachedAvgVerticalOscillationCm {
            rows.append("- Avg vertical oscillation: \(String(format: "%.1f", v)) cm")
        }
        if let v = viewModel.avgRunningPowerWatts ?? workout.cachedAvgRunningPowerWatts {
            rows.append("- Avg running power: \(Int(v)) W")
        }
        guard !rows.isEmpty else { return [] }
        var out = ["## Metrics", ""]
        out.append(contentsOf: rows)
        out.append("")
        return out
    }

    private static func splitsSection(
        segments: [WorkoutDetailViewModel.WorkoutSegment],
        type: WorkoutType
    ) -> [String] {
        var out = ["## Splits", ""]
        out.append("| # | Distance (km) | Duration | Pace /km | Avg HR | Avg Power | Elev Δ (m) |")
        out.append("|---|---|---|---|---|---|---|")
        for seg in segments {
            let distKm = seg.distanceMeters / 1000
            let pace = seg.distanceMeters > 0
                ? seg.durationSeconds / (seg.distanceMeters / 1000)
                : 0
            let paceStr = pace > 0 ? formatPace(pace) : "—"
            let hrStr = seg.avgHeartRate.map { "\(Int($0))" } ?? "—"
            let powerStr = seg.avgPower.map { "\(Int($0)) W" } ?? "—"
            let elevStr = seg.elevationChange.map { String(format: "%+.0f", $0) } ?? "—"
            out.append("| \(seg.label) | \(String(format: "%.2f", distKm)) | \(formatDuration(seg.durationSeconds)) | \(paceStr) | \(hrStr) | \(powerStr) | \(elevStr) |")
        }
        out.append("")
        return out
    }

    private static func routeSection(points: [RoutePoint]) -> [String] {
        let sorted = points.sorted { $0.timestamp < $1.timestamp }
        guard let first = sorted.first, let last = sorted.last else { return [] }

        let lats = sorted.map(\.latitude)
        let lons = sorted.map(\.longitude)
        let alts = sorted.map(\.altitude)

        var out = ["## Route", ""]
        out.append("- Points recorded: \(sorted.count)")
        out.append("- Start (rounded): \(formatCoord(lat: first.latitude, lon: first.longitude))")
        out.append("- End (rounded): \(formatCoord(lat: last.latitude, lon: last.longitude))")
        if let minLat = lats.min(), let maxLat = lats.max(),
           let minLon = lons.min(), let maxLon = lons.max() {
            out.append("- Bounds (rounded): lat \(roundCoord(minLat))…\(roundCoord(maxLat)), lon \(roundCoord(minLon))…\(roundCoord(maxLon))")
        }
        if let minAlt = alts.min(), let maxAlt = alts.max() {
            out.append("- Altitude range: \(Int(minAlt)) m – \(Int(maxAlt)) m")
        }

        // Downsampled path (rounded) so the AI can see shape without exact trace
        let sample = downsample(sorted, maxCount: 40)
        if sample.count > 1 {
            out.append("")
            out.append("Sampled path (time offset s, lat, lon, altitude m):")
            out.append("```")
            let base = first.timestamp
            for p in sample {
                let t = Int(p.timestamp.timeIntervalSince(base))
                out.append("\(t), \(roundCoord(p.latitude)), \(roundCoord(p.longitude)), \(Int(p.altitude))")
            }
            out.append("```")
        }
        out.append("")
        return out
    }

    private static func heartRateSeriesSection(points: [WorkoutDetailViewModel.HeartRatePoint]) -> [String] {
        let sample = downsample(points, maxCount: 60) { $0.secondsFromStart }
        guard !sample.isEmpty else { return [] }
        var out = ["## Heart Rate Series", "", "Format: time offset (s), bpm", "```"]
        for p in sample {
            out.append("\(Int(p.secondsFromStart)), \(Int(p.bpm))")
        }
        out.append("```")
        out.append("")
        return out
    }

    private static func powerSeriesSection(points: [WorkoutDetailViewModel.PowerPoint]) -> [String] {
        let sample = downsample(points, maxCount: 60) { $0.secondsFromStart }
        guard !sample.isEmpty else { return [] }
        var out = ["## Power Series", "", "Format: time offset (s), W", "```"]
        for p in sample {
            out.append("\(Int(p.secondsFromStart)), \(Int(p.watts))")
        }
        out.append("```")
        out.append("")
        return out
    }

    private static func elevationSeriesSection(points: [WorkoutDetailViewModel.ElevationPoint]) -> [String] {
        let sample = downsample(points, maxCount: 60) { $0.secondsFromStart }
        guard !sample.isEmpty else { return [] }
        var out = ["## Elevation Series", "", "Format: time offset (s), meters", "```"]
        for p in sample {
            out.append("\(Int(p.secondsFromStart)), \(Int(p.meters))")
        }
        out.append("```")
        out.append("")
        return out
    }

    // MARK: - Helpers

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func formatDuration(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%d:%02d", m, sec)
    }

    private static func formatPace(_ secondsPerKm: Double) -> String {
        let s = Int(secondsPerKm.rounded())
        let m = s / 60
        let sec = s % 60
        return String(format: "%d:%02d", m, sec)
    }

    private static func roundCoord(_ value: Double) -> Double {
        let factor = pow(10.0, Double(coordinateDecimals))
        return (value * factor).rounded() / factor
    }

    private static func formatCoord(lat: Double, lon: Double) -> String {
        "\(roundCoord(lat)), \(roundCoord(lon))"
    }

    private static func downsample<T>(_ items: [T], maxCount: Int) -> [T] {
        guard items.count > maxCount, maxCount > 1 else { return items }
        let stride = Double(items.count - 1) / Double(maxCount - 1)
        var result: [T] = []
        result.reserveCapacity(maxCount)
        for i in 0..<maxCount {
            let idx = Int((Double(i) * stride).rounded())
            result.append(items[min(idx, items.count - 1)])
        }
        return result
    }

    private static func downsample<T>(_ items: [T], maxCount: Int, by keyPath: (T) -> Double) -> [T] {
        _ = keyPath // kept for future-proofing (uniform time resampling would use it)
        return downsample(items, maxCount: maxCount)
    }
}
