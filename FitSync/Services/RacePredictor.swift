import Foundation

/// Pure-logic predictor using the Riegel formula:
/// `T₂ = T₁ × (D₂/D₁)^1.06`
///
/// Baseline is the fastest sustained running effort (≥ 5 km) within a time
/// window. Results are only trustworthy when the baseline is a real hard
/// effort; easy-only training weeks produce soft predictions.
struct RacePredictor {

    static let riegelExponent = 1.06
    static let minBaselineKm: Double = 5.0

    struct Prediction {
        let targetDistanceKm: Double
        let predictedSeconds: Double
        let baseline: Baseline
    }

    struct Baseline {
        let workout: Workout
        let distanceKm: Double
        let durationSeconds: Double
        var pacePerKm: Double { durationSeconds / distanceKm }
    }

    struct WeeklyPrediction: Identifiable {
        let id = UUID()
        let weekEnd: Date
        let predictedSeconds: Double
    }

    /// Finds the fastest running effort ≥ 5km inside a lookback window.
    static func baseline(
        from workouts: [Workout],
        within window: DateInterval
    ) -> Baseline? {
        let candidates = workouts.compactMap { w -> Baseline? in
            guard w.type == .running,
                  window.contains(w.startDate),
                  let meters = w.distanceMeters,
                  meters >= minBaselineKm * 1000,
                  w.durationSeconds > 0 else {
                return nil
            }
            let km = meters / 1000.0
            return Baseline(workout: w, distanceKm: km, durationSeconds: w.durationSeconds)
        }
        return candidates.min { $0.pacePerKm < $1.pacePerKm }
    }

    static func predict(baseline: Baseline, targetKm: Double) -> Double {
        baseline.durationSeconds * pow(targetKm / baseline.distanceKm, riegelExponent)
    }

    /// Builds a smoothed prediction-per-week history: for each week ending
    /// this Sunday and going back `weeks` weeks, take the best ≥5km effort
    /// from the trailing `smoothingWeeks` weeks and project to `targetKm`.
    static func weeklyHistory(
        workouts: [Workout],
        targetKm: Double,
        weeks: Int = 10,
        smoothingWeeks: Int = 3,
        from anchor: Date = .now
    ) -> [WeeklyPrediction] {
        let calendar = Calendar.current
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: anchor) else {
            return []
        }

        var out: [WeeklyPrediction] = []
        for i in 0..<weeks {
            guard let weekEnd = calendar.date(byAdding: .weekOfYear, value: -i, to: thisWeek.end),
                  let windowStart = calendar.date(byAdding: .weekOfYear, value: -smoothingWeeks, to: weekEnd)
            else { continue }
            let window = DateInterval(start: windowStart, end: weekEnd)
            if let base = baseline(from: workouts, within: window) {
                let secs = predict(baseline: base, targetKm: targetKm)
                out.append(.init(weekEnd: weekEnd, predictedSeconds: secs))
            }
        }
        return out.sorted { $0.weekEnd < $1.weekEnd }
    }
}

extension TrainingGoal {
    /// Target race distance in km. Only pure running goals have a meaningful
    /// Riegel projection from past run efforts — triathlons and swims return
    /// `nil` because the formula doesn't apply (different sports / different
    /// physiology off the bike).
    var predictedRunDistanceKm: Double? {
        switch self {
        case .fiveK: 5.0
        case .tenK: 10.0
        case .halfMarathon: 21.0975
        case .marathon: 42.195
        case .generalFitness,
             .olympicTriathlon, .triathlon,
             .openWaterSwim1500m, .openWaterSwim5K, .openWaterSwim10K:
            nil
        }
    }
}
