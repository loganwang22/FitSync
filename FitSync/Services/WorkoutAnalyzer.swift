import Foundation

/// On-device rule-based workout analysis engine. Stateless — all data passed in.
struct WorkoutAnalyzer {

    // MARK: - Thresholds

    private static let optimalCadenceRange = 170.0...185.0
    private static let goodGroundContactMs = 250.0
    private static let goodVerticalOscCm = 8.0
    private static let weeklyVolumeIncreaseWarning = 0.10  // 10%
    private static let maxEstimatedHR = 190.0  // fallback if no max HR data
    private static let hrZoneEasy = 0.65
    private static let hrZoneAerobic = 0.80
    private static let hrZoneThreshold = 0.90

    // MARK: - Public API

    func analyze(
        workout: Workout,
        recentWorkouts: [Workout],
        goal: TrainingGoal?
    ) -> CoachAnalysis {
        var observations: [CoachAnalysis.Observation] = []
        var recommendations: [CoachAnalysis.Recommendation] = []

        observations.append(contentsOf: analyzePace(workout: workout, recent: recentWorkouts))
        observations.append(contentsOf: analyzeHeartRate(workout: workout))
        observations.append(contentsOf: analyzePower(workout: workout))
        observations.append(contentsOf: analyzeRunningForm(workout: workout))
        observations.append(contentsOf: analyzeTrainingLoad(recent: recentWorkouts))

        if let goal {
            observations.append(contentsOf: analyzeGoalProgress(recent: recentWorkouts, goal: goal))
        }

        recommendations.append(contentsOf: generateRecommendations(
            workout: workout,
            observations: observations,
            recent: recentWorkouts,
            goal: goal
        ))

        let suggested = suggestNextWorkouts(
            recent: recentWorkouts,
            goal: goal,
            lastWorkout: workout
        )

        return CoachAnalysis(
            observations: observations,
            recommendations: recommendations,
            suggestedWorkouts: suggested,
            source: .onDevice,
            generatedDate: .now
        )
    }

    // MARK: - Pace Analysis

    private func analyzePace(workout: Workout, recent: [Workout]) -> [CoachAnalysis.Observation] {
        var results: [CoachAnalysis.Observation] = []
        guard let pace = workout.avgPaceSecondsPerKm, workout.type == .running else { return results }

        // Compare to recent average
        let recentPaces = recent
            .filter { $0.type == .running && $0.healthKitUUID != workout.healthKitUUID }
            .compactMap(\.avgPaceSecondsPerKm)

        if !recentPaces.isEmpty {
            let avgRecent = recentPaces.reduce(0, +) / Double(recentPaces.count)
            let diff = pace - avgRecent  // negative = faster

            if diff < -5 {
                results.append(.init(
                    category: .pace,
                    title: "Faster Than Usual",
                    detail: String(format: "Your pace was %.0fs/km faster than your recent average of %@.", -diff, avgRecent.formattedPaceShort),
                    sentiment: .positive
                ))
            } else if diff > 10 {
                results.append(.init(
                    category: .pace,
                    title: "Slower Pace",
                    detail: String(format: "%.0fs/km slower than recent average. This could be an easy/recovery run, which is great for base building.", diff),
                    sentiment: .neutral
                ))
            }
        }

        // Speed analysis for cycling
        if workout.type == .cycling, let speed = workout.avgSpeedMps {
            let kmh = speed * 3.6
            if kmh > 30 {
                results.append(.init(category: .pace, title: "Strong Speed", detail: String(format: "%.1f km/h is a solid cycling pace.", kmh), sentiment: .positive))
            }
        }

        return results
    }

    // MARK: - Heart Rate

    private func analyzeHeartRate(workout: Workout) -> [CoachAnalysis.Observation] {
        var results: [CoachAnalysis.Observation] = []
        guard let avgHR = workout.cachedAvgHeartRate else { return results }

        let maxHR = workout.cachedMaxHeartRate ?? Self.maxEstimatedHR
        let pctAvg = avgHR / maxHR

        let zone: String
        let sentiment: CoachAnalysis.Observation.Sentiment
        if pctAvg < Self.hrZoneEasy {
            zone = "easy/recovery"
            sentiment = .neutral
        } else if pctAvg < Self.hrZoneAerobic {
            zone = "aerobic"
            sentiment = .positive
        } else if pctAvg < Self.hrZoneThreshold {
            zone = "threshold"
            sentiment = .neutral
        } else {
            zone = "anaerobic/max effort"
            sentiment = .caution
        }

        results.append(.init(
            category: .heartRate,
            title: "\(zone.capitalized) Zone",
            detail: String(format: "Average HR %.0f bpm (%.0f%% of max). This was a %@ effort.", avgHR, pctAvg * 100, zone),
            sentiment: sentiment
        ))

        // High max HR warning
        if let maxRecorded = workout.cachedMaxHeartRate, maxRecorded > maxHR * 0.95 {
            results.append(.init(
                category: .heartRate,
                title: "Near Max HR",
                detail: String(format: "Your max HR hit %.0f bpm. Ensure adequate recovery after high-intensity sessions.", maxRecorded),
                sentiment: .caution
            ))
        }

        return results
    }

    // MARK: - Power

    private func analyzePower(workout: Workout) -> [CoachAnalysis.Observation] {
        var results: [CoachAnalysis.Observation] = []

        if workout.type == .cycling, let avg = workout.cachedAvgPowerWatts, let max = workout.cachedMaxPowerWatts, avg > 0 {
            let variability = max / avg
            if variability > 1.5 {
                results.append(.init(
                    category: .power,
                    title: "Variable Power Output",
                    detail: String(format: "Max power (%.0fW) was %.1fx your average (%.0fW). Try to maintain steadier power on flat sections.", max, variability, avg),
                    sentiment: .neutral
                ))
            } else {
                results.append(.init(
                    category: .power,
                    title: "Steady Power",
                    detail: String(format: "Good power consistency — avg %.0fW with controlled peaks.", avg),
                    sentiment: .positive
                ))
            }
        }

        if workout.type == .running, let power = workout.cachedAvgRunningPowerWatts, power > 0 {
            results.append(.init(
                category: .power,
                title: "Running Power",
                detail: String(format: "Average running power of %.0fW. Track this over time to measure efficiency.", power),
                sentiment: .neutral
            ))
        }

        return results
    }

    // MARK: - Running Form

    private func analyzeRunningForm(workout: Workout) -> [CoachAnalysis.Observation] {
        var results: [CoachAnalysis.Observation] = []
        guard workout.type == .running else { return results }

        if let cadence = workout.cachedAvgCadenceSpm {
            if Self.optimalCadenceRange.contains(cadence) {
                results.append(.init(
                    category: .form,
                    title: "Good Cadence",
                    detail: String(format: "%.0f spm is in the optimal range (170-185). This helps reduce impact forces.", cadence),
                    sentiment: .positive
                ))
            } else if cadence < Self.optimalCadenceRange.lowerBound {
                results.append(.init(
                    category: .form,
                    title: "Low Cadence",
                    detail: String(format: "%.0f spm is below optimal. Try shorter, quicker steps to reduce overstriding and injury risk.", cadence),
                    sentiment: .caution
                ))
            } else {
                results.append(.init(
                    category: .form,
                    title: "High Cadence",
                    detail: String(format: "%.0f spm — very quick turnover. Ensure your stride length isn't too short for your pace.", cadence),
                    sentiment: .neutral
                ))
            }
        }

        if let gct = workout.cachedAvgGroundContactTimeMs {
            if gct < Self.goodGroundContactMs {
                results.append(.init(
                    category: .form,
                    title: "Quick Ground Contact",
                    detail: String(format: "%.0f ms ground contact time is efficient. Your feet spend less time on the ground.", gct),
                    sentiment: .positive
                ))
            } else {
                results.append(.init(
                    category: .form,
                    title: "Ground Contact Time",
                    detail: String(format: "%.0f ms — try drills like high knees or strides to improve foot speed.", gct),
                    sentiment: .neutral
                ))
            }
        }

        if let vo = workout.cachedAvgVerticalOscillationCm {
            if vo < Self.goodVerticalOscCm {
                results.append(.init(
                    category: .form,
                    title: "Efficient Vertical Movement",
                    detail: String(format: "%.1f cm oscillation means you're directing energy forward, not up.", vo),
                    sentiment: .positive
                ))
            } else {
                results.append(.init(
                    category: .form,
                    title: "High Bounce",
                    detail: String(format: "%.1f cm vertical oscillation. Focus on running 'low and smooth' to save energy.", vo),
                    sentiment: .caution
                ))
            }
        }

        return results
    }

    // MARK: - Training Load

    private func analyzeTrainingLoad(recent: [Workout]) -> [CoachAnalysis.Observation] {
        var results: [CoachAnalysis.Observation] = []
        let calendar = Calendar.current
        let now = Date.now

        // Weekly volume comparison (this week vs last week)
        guard let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start,
              let lastWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeekStart) else {
            return results
        }

        let thisWeek = recent.filter { $0.startDate >= thisWeekStart }
        let lastWeek = recent.filter { $0.startDate >= lastWeekStart && $0.startDate < thisWeekStart }

        let thisWeekDist = thisWeek.compactMap(\.distanceMeters).reduce(0, +)
        let lastWeekDist = lastWeek.compactMap(\.distanceMeters).reduce(0, +)

        if lastWeekDist > 0 {
            let increase = (thisWeekDist - lastWeekDist) / lastWeekDist
            if increase > Self.weeklyVolumeIncreaseWarning {
                results.append(.init(
                    category: .training,
                    title: "Volume Spike",
                    detail: String(format: "Weekly distance up %.0f%% from last week. The 10%% rule suggests building gradually to avoid injury.", increase * 100),
                    sentiment: .caution
                ))
            }
        }

        // Rest days check
        let last7 = recent.filter { $0.startDate >= (calendar.date(byAdding: .day, value: -7, to: now) ?? now) }
        let uniqueDays = Set(last7.map { calendar.startOfDay(for: $0.startDate) })
        if uniqueDays.count >= 7 {
            results.append(.init(
                category: .recovery,
                title: "No Rest Days",
                detail: "You've trained every day this week. Rest is when your body adapts — consider a recovery day.",
                sentiment: .caution
            ))
        }

        return results
    }

    // MARK: - Goal Progress

    private func analyzeGoalProgress(recent: [Workout], goal: TrainingGoal) -> [CoachAnalysis.Observation] {
        var results: [CoachAnalysis.Observation] = []
        let calendar = Calendar.current
        let now = Date.now
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return results }

        let thisWeek = recent.filter { $0.startDate >= weekStart }
        let targets = goal.weeklyTargets

        // Sessions count
        let sessionsCount = thisWeek.count
        if sessionsCount >= targets.sessionsPerWeek {
            results.append(.init(
                category: .training,
                title: "Session Target Met",
                detail: "\(sessionsCount)/\(targets.sessionsPerWeek) sessions this week. You're on track!",
                sentiment: .positive
            ))
        }

        // Running distance
        if targets.runKm > 0 {
            let runKm = thisWeek.filter { $0.type == .running }.compactMap(\.distanceMeters).reduce(0, +) / 1000
            let pct = runKm / targets.runKm
            if pct >= 0.9 {
                results.append(.init(
                    category: .endurance,
                    title: "Run Volume On Track",
                    detail: String(format: "%.1f / %.0f km running this week (%.0f%%).", runKm, targets.runKm, pct * 100),
                    sentiment: .positive
                ))
            } else if pct < 0.5 {
                results.append(.init(
                    category: .endurance,
                    title: "Run Volume Low",
                    detail: String(format: "%.1f / %.0f km running this week. Consider adding a run to stay on target.", runKm, targets.runKm),
                    sentiment: .caution
                ))
            }
        }

        // Triathlon: check sport balance
        if goal.involvedSports.count > 1 {
            let typesThisWeek = Set(thisWeek.map(\.type))
            let missing = goal.involvedSports.filter { !typesThisWeek.contains($0) }
            if !missing.isEmpty {
                let missingNames = missing.map(\.label).joined(separator: ", ")
                results.append(.init(
                    category: .training,
                    title: "Missing Disciplines",
                    detail: "No \(missingNames) this week. For \(goal.label), try to train all disciplines each week.",
                    sentiment: .caution
                ))
            }
        }

        return results
    }

    // MARK: - Recommendations

    private func generateRecommendations(
        workout: Workout,
        observations: [CoachAnalysis.Observation],
        recent: [Workout],
        goal: TrainingGoal?
    ) -> [CoachAnalysis.Recommendation] {
        var recs: [CoachAnalysis.Recommendation] = []

        let hasCaution = observations.contains { $0.sentiment == .caution }
        let hasNoRestDays = observations.contains { $0.category == .recovery }
        let hasLowCadence = observations.contains { $0.category == .form && $0.title.contains("Low Cadence") }
        let hasVolumeSpike = observations.contains { $0.title.contains("Volume Spike") }

        // Recovery recommendation
        if hasNoRestDays || hasVolumeSpike {
            recs.append(.init(
                title: "Prioritize Recovery",
                detail: "Your training load is high. Schedule a rest day or easy cross-training session to allow adaptation.",
                type: .recovery
            ))
        }

        // Form improvement
        if hasLowCadence {
            recs.append(.init(
                title: "Cadence Drills",
                detail: "Add 4x30s cadence pickups to your next easy run. Focus on quick, light steps without increasing effort.",
                type: .technique
            ))
        }

        // Goal-specific
        if let goal, goal.involvedSports.contains(.running) {
            let recentRuns = recent.filter { $0.type == .running }
            let allSamePace = recentRuns.count >= 3 && recentRuns.allSatisfy { run in
                guard let p1 = run.avgPaceSecondsPerKm, let p2 = recentRuns.first?.avgPaceSecondsPerKm else { return false }
                return abs(p1 - p2) < 15  // within 15s/km
            }
            if allSamePace {
                recs.append(.init(
                    title: "Add Variety",
                    detail: "Your recent runs are all at similar pace. Mix in an interval or tempo session to build speed.",
                    type: .nextWorkout
                ))
            }
        }

        // General encouragement if nothing concerning
        if !hasCaution && recs.isEmpty {
            recs.append(.init(
                title: "Keep It Up",
                detail: "Solid session! Your metrics look good. Stay consistent and the results will follow.",
                type: .goalProgress
            ))
        }

        return recs
    }

    // MARK: - Suggested Workouts

    private func suggestNextWorkouts(
        recent: [Workout],
        goal: TrainingGoal?,
        lastWorkout: Workout
    ) -> [CoachAnalysis.SuggestedWorkout] {
        var suggestions: [CoachAnalysis.SuggestedWorkout] = []
        let calendar = Calendar.current
        let now = Date.now
        let daysSinceLast = calendar.dateComponents([.day], from: lastWorkout.startDate, to: now).day ?? 0

        // If worked out today/yesterday, suggest recovery or complementary
        if daysSinceLast <= 1 {
            if lastWorkout.type == .running {
                suggestions.append(.init(
                    name: "Recovery Ride or Walk",
                    description: "Low-intensity cross-training to promote recovery while staying active.",
                    workoutTypeRaw: WorkoutType.cycling.rawValue,
                    durationMinutes: 30,
                    intensity: .easy
                ))
            } else if lastWorkout.type == .cycling {
                suggestions.append(.init(
                    name: "Easy Recovery Run",
                    description: "Short, easy-pace run to maintain running fitness without additional fatigue.",
                    workoutTypeRaw: WorkoutType.running.rawValue,
                    durationMinutes: 25,
                    intensity: .easy
                ))
            }
        }

        // Goal-specific suggestions
        if let goal {
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            let thisWeek = recent.filter { $0.startDate >= weekStart }
            let typesThisWeek = Set(thisWeek.map(\.type))

            // Suggest missing sports for triathlon goals
            for sport in goal.involvedSports where !typesThisWeek.contains(sport) {
                let name: String
                let desc: String
                let mins: Int
                switch sport {
                case .running:
                    name = "Aerobic Run"
                    desc = "Easy to moderate run to build your aerobic base."
                    mins = 40
                case .cycling:
                    name = "Steady Ride"
                    desc = "Maintain a consistent effort to build cycling endurance."
                    mins = 60
                case .swimming:
                    name = "Technique Swim"
                    desc = "Focus on form with drill sets and easy laps."
                    mins = 30
                }
                suggestions.append(.init(
                    name: name,
                    description: desc,
                    workoutTypeRaw: sport.rawValue,
                    durationMinutes: mins,
                    intensity: .moderate
                ))
            }

            // Long run suggestion for marathon goals
            if [.halfMarathon, .marathon].contains(goal) {
                let longRuns = thisWeek.filter { $0.type == .running && $0.durationSeconds > 3600 }
                if longRuns.isEmpty {
                    suggestions.append(.init(
                        name: "Long Run",
                        description: "Weekly long run at easy pace. Key for building marathon endurance.",
                        workoutTypeRaw: WorkoutType.running.rawValue,
                        durationMinutes: goal == .marathon ? 90 : 70,
                        intensity: .easy
                    ))
                }
            }
        }

        // Strength training suggestion (universal)
        let hasStrengthSuggestion = suggestions.contains { $0.name.contains("Strength") }
        if !hasStrengthSuggestion && suggestions.count < 3 {
            suggestions.append(.init(
                name: "Strength Training",
                description: "Core and leg strength work to improve performance and prevent injuries.",
                workoutTypeRaw: nil,
                durationMinutes: 30,
                intensity: .moderate
            ))
        }

        return Array(suggestions.prefix(3))
    }
}

// MARK: - Helper

private extension Double {
    var formattedPaceShort: String {
        let m = Int(self) / 60
        let s = Int(self) % 60
        return String(format: "%d'%02d\"/km", m, s)
    }
}
