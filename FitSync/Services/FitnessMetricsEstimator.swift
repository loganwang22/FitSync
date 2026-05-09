import Foundation

/// Estimates threshold/fitness metrics from past workouts.
///
/// - Cycling FTP: 95% of the best 20-minute rolling average power from
///   cycling workouts with a power series.
/// - Cycling LTHR: average HR over the last 20 minutes of a 30-minute+
///   hard solo cycling effort (Friel field test heuristic).
/// - Cycling W/kg: cyclingFTP / latest body mass (from HealthKit).
/// - Running LTHR: same Friel heuristic applied to hard ≥30-min runs.
/// - Running threshold pace: average pace over the last 20 minutes of the
///   same qualifying run — the running-world analogue of FTP, more useful
///   than running power because pace is universally tracked.
///
/// Nothing here is a lab test; quality depends on whether the user has
/// actually done hard sustained efforts in the window. Each `Estimate`
/// carries a `Confidence` so the UI can flag soft numbers.
@MainActor
struct FitnessMetricsEstimator {
    /// Lookback window for finding qualifying efforts.
    static let lookbackWeeks = 8

    /// Minimum sustained effort length that counts as a threshold-ish effort.
    /// Shorter efforts still produce a value but with lowered confidence.
    static let minEffortMinutes: Double = 20

    func estimate(
        workouts: [Workout],
        bodyMassKg: Double?,
        from now: Date = .now
    ) -> FitnessMetrics {
        let window = lookbackWindow(from: now)
        let recent = workouts.filter { window.contains($0.startDate) }

        let cyclingWorkouts = recent.filter { $0.type == .cycling }
        let runningWorkouts = recent.filter { $0.type == .running }

        let ftp = estimateCyclingFTP(from: cyclingWorkouts)
        let cyclingLTHR = estimateLTHR(from: cyclingWorkouts, sport: .cycling)
        let cyclingWPerKg = computeWattsPerKg(ftp: ftp, bodyMassKg: bodyMassKg)

        let runningLTHR = estimateLTHR(from: runningWorkouts, sport: .running)
        let thresholdPace = estimateRunningThresholdPace(from: runningWorkouts)

        return FitnessMetrics(
            cyclingFTP: ftp,
            cyclingLTHR: cyclingLTHR,
            cyclingWattsPerKg: cyclingWPerKg,
            runningLTHR: runningLTHR,
            runningThresholdPaceSecPerKm: thresholdPace,
            bodyMassKg: bodyMassKg,
            generatedDate: now
        )
    }

    private func lookbackWindow(from now: Date) -> DateInterval {
        let start = Calendar.current.date(byAdding: .weekOfYear, value: -Self.lookbackWeeks, to: now) ?? now
        return DateInterval(start: start, end: now)
    }

    // MARK: - Cycling FTP

    /// Classic field-test FTP: best 20-min average power × 0.95. We scan
    /// each cycling workout's cached power series for the highest 20-min
    /// rolling mean, then take the max across workouts.
    private func estimateCyclingFTP(from workouts: [Workout]) -> FitnessMetrics.Estimate? {
        var best: (watts: Double, workout: Workout, minutes: Double)?

        for w in workouts {
            guard let series = w.cachedPowerSeries, !series.isEmpty else { continue }
            // Prefer a 20-min window; fall back to the longest possible window
            // ≥ 10 min with reduced confidence.
            if let r20 = bestRollingMean(series: series, windowSeconds: 20 * 60) {
                if best == nil || r20 > best!.watts {
                    best = (r20, w, 20)
                }
            } else if let r10 = bestRollingMean(series: series, windowSeconds: 10 * 60) {
                if best == nil || r10 > best!.watts {
                    best = (r10, w, 10)
                }
            }
        }

        guard let b = best else { return nil }
        let ftp = b.watts * 0.95
        let confidence: FitnessMetrics.Confidence = b.minutes >= 20 ? .high : .medium
        let method = String(
            format: "%.0fW × 0.95 from best %.0f-min effort",
            b.watts, b.minutes
        )
        return .init(
            value: ftp,
            confidence: confidence,
            method: method,
            sourceWorkoutDate: b.workout.startDate
        )
    }

    /// Sliding-window max mean over a time-series of (secondsFromStart, value).
    /// Series points aren't guaranteed to be at 1Hz, so we walk both endpoints
    /// by timestamp rather than by index.
    private func bestRollingMean(
        series: [Workout.CachedTimePoint],
        windowSeconds: Double
    ) -> Double? {
        let sorted = series.sorted { $0.t < $1.t }
        guard let first = sorted.first, let last = sorted.last,
              last.t - first.t >= windowSeconds else {
            return nil
        }

        var best: Double?
        var j = 0
        for i in 0..<sorted.count {
            let windowEnd = sorted[i].t + windowSeconds
            if windowEnd > last.t { break }
            while j < sorted.count && sorted[j].t < windowEnd {
                j += 1
            }
            let slice = sorted[i..<j]
            guard !slice.isEmpty else { continue }
            let mean = slice.map(\.v).reduce(0, +) / Double(slice.count)
            if best == nil || mean > best! {
                best = mean
            }
        }
        return best
    }

    // MARK: - LTHR (Friel field-test heuristic)

    private enum Sport { case running, cycling }

    /// Friel's 30-min solo TT method: average HR over the **final 20 minutes**
    /// of a ~30+ min hard effort approximates LTHR. We relax "all-out" to
    /// "hard" by requiring the effort's avg HR to be ≥ 85% of the user's
    /// observed max HR in the window.
    private func estimateLTHR(from workouts: [Workout], sport: Sport) -> FitnessMetrics.Estimate? {
        let hrWorkouts = workouts.filter {
            ($0.cachedHeartRateSeries?.count ?? 0) > 0 && $0.durationSeconds >= 30 * 60
        }
        guard !hrWorkouts.isEmpty else { return nil }

        let observedMaxHR = workouts.compactMap(\.cachedMaxHeartRate).max() ?? 0
        guard observedMaxHR > 0 else { return nil }
        let hardFloor = observedMaxHR * 0.85

        var best: (lthr: Double, workout: Workout, confidence: FitnessMetrics.Confidence)?

        for w in hrWorkouts {
            guard let avg = w.cachedAvgHeartRate, avg >= hardFloor,
                  let series = w.cachedHeartRateSeries else { continue }
            let sorted = series.sorted { $0.t < $1.t }
            guard let last = sorted.last else { continue }
            let windowStart = last.t - 20 * 60
            guard windowStart >= 10 * 60 else { continue }  // need ≥ 30 min total

            let tail = sorted.filter { $0.t >= windowStart }
            guard !tail.isEmpty else { continue }
            let lthr = tail.map(\.v).reduce(0, +) / Double(tail.count)

            // Higher confidence when the effort was longer and harder.
            let confidence: FitnessMetrics.Confidence =
                w.durationSeconds >= 45 * 60 && avg >= observedMaxHR * 0.9
                    ? .high
                    : .medium

            if best == nil || lthr > best!.lthr {
                best = (lthr, w, confidence)
            }
        }

        guard let b = best else { return nil }
        let sportLabel = sport == .running ? "run" : "ride"
        return .init(
            value: b.lthr,
            confidence: b.confidence,
            method: "Final 20-min HR of hard \(sportLabel)",
            sourceWorkoutDate: b.workout.startDate
        )
    }

    // MARK: - Running threshold pace

    /// Running analogue of FTP: average pace over the last 20 min of a ≥30-min
    /// hard run. Uses the same qualifying effort criteria as running LTHR.
    private func estimateRunningThresholdPace(from workouts: [Workout]) -> FitnessMetrics.Estimate? {
        let candidates = workouts.filter {
            $0.durationSeconds >= 30 * 60 && $0.distanceMeters ?? 0 >= 5000
        }
        guard !candidates.isEmpty else { return nil }

        let observedMaxHR = workouts.compactMap(\.cachedMaxHeartRate).max() ?? 0
        let hardFloor = observedMaxHR * 0.85

        // For pace, we don't have a per-second pace series, only overall. So
        // use the workout's average pace when the average HR qualifies as
        // threshold-ish. Best (fastest) such pace wins.
        var best: (pace: Double, workout: Workout, confidence: FitnessMetrics.Confidence)?

        for w in candidates {
            guard let dist = w.distanceMeters, dist > 0 else { continue }
            let pace = w.avgPaceSecondsPerKm ?? (w.durationSeconds / (dist / 1000))

            let confidence: FitnessMetrics.Confidence
            if let avgHR = w.cachedAvgHeartRate, observedMaxHR > 0, avgHR >= hardFloor {
                confidence = w.durationSeconds >= 45 * 60 ? .high : .medium
            } else {
                confidence = .low
            }

            if best == nil || pace < best!.pace {
                best = (pace, w, confidence)
            }
        }

        guard let b = best else { return nil }
        return .init(
            value: b.pace,
            confidence: b.confidence,
            method: "Avg pace of hardest ≥30-min run",
            sourceWorkoutDate: b.workout.startDate
        )
    }

    // MARK: - W/kg

    private func computeWattsPerKg(
        ftp: FitnessMetrics.Estimate?,
        bodyMassKg: Double?
    ) -> FitnessMetrics.Estimate? {
        guard let ftp, let kg = bodyMassKg, kg > 0 else { return nil }
        let ratio = ftp.value / kg
        return .init(
            value: ratio,
            confidence: ftp.confidence,
            method: String(format: "FTP / %.1f kg", kg),
            sourceWorkoutDate: ftp.sourceWorkoutDate
        )
    }
}
