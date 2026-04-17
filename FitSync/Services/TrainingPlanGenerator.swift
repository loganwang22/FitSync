import Foundation

/// Generates a personalized training plan from workout history + training goal.
struct TrainingPlanGenerator {

    // MARK: - Configuration

    private static let historyWeeks = 6
    private static let planWeeks = 4
    private static let weeklyIncreaseRate = 0.08  // ~8% per week
    private static let deloadRatio = 0.70
    private static let deloadEveryNWeeks = 4

    // MARK: - Baseline

    struct Baseline {
        let avgWeeklyRunKm: Double
        let avgWeeklyCycleKm: Double
        let avgWeeklySwimM: Double
        let avgWeeklySessions: Double
        let avgRunPaceSecPerKm: Double?
        let avgCyclingSpeedKmh: Double?
        let maxLongRunKm: Double
        let trainingDays: Set<Int>  // days of week (1-7) user typically trains
    }

    func computeBaseline(from workouts: [Workout]) -> Baseline {
        let calendar = Calendar.current
        let now = Date.now
        let cutoff = calendar.date(byAdding: .weekOfYear, value: -Self.historyWeeks, to: now) ?? now
        let recent = workouts.filter { $0.startDate >= cutoff }

        let weeks = max(Double(Self.historyWeeks), 1)

        let runs = recent.filter { $0.type == .running }
        let cycles = recent.filter { $0.type == .cycling }
        let swims = recent.filter { $0.type == .swimming }

        let runKm = runs.compactMap(\.distanceMeters).reduce(0, +) / 1000
        let cycleKm = cycles.compactMap(\.distanceMeters).reduce(0, +) / 1000
        let swimM = swims.compactMap(\.distanceMeters).reduce(0, +)

        let avgPace: Double? = {
            let paces = runs.compactMap(\.avgPaceSecondsPerKm)
            return paces.isEmpty ? nil : paces.reduce(0, +) / Double(paces.count)
        }()

        let avgSpeed: Double? = {
            let speeds = cycles.compactMap(\.avgSpeedMps).filter { $0 > 0 }
            return speeds.isEmpty ? nil : (speeds.reduce(0, +) / Double(speeds.count)) * 3.6
        }()

        let maxLongRun = (runs.compactMap(\.distanceMeters).max() ?? 0) / 1000

        let trainingDays = Set(recent.map { calendar.component(.weekday, from: $0.startDate) })

        return Baseline(
            avgWeeklyRunKm: runKm / weeks,
            avgWeeklyCycleKm: cycleKm / weeks,
            avgWeeklySwimM: swimM / weeks,
            avgWeeklySessions: Double(recent.count) / weeks,
            avgRunPaceSecPerKm: avgPace,
            avgCyclingSpeedKmh: avgSpeed,
            maxLongRunKm: maxLongRun,
            trainingDays: trainingDays
        )
    }

    // MARK: - Generate Plan

    func generate(from workouts: [Workout], goal: TrainingGoal) -> TrainingPlan {
        let baseline = computeBaseline(from: workouts)
        let calendar = Calendar.current
        let now = Date.now
        let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now

        let weeklyBlocks = generateWeeklyBlocks(
            baseline: baseline,
            goal: goal,
            startDate: thisWeekStart,
            calendar: calendar
        )

        let milestones = generateMilestones(
            baseline: baseline,
            goal: goal,
            startDate: thisWeekStart,
            calendar: calendar
        )

        return TrainingPlan(
            generatedDate: now,
            goalRawValue: goal.rawValue,
            baselineWeeklyKm: baseline.avgWeeklyRunKm + baseline.avgWeeklyCycleKm + baseline.avgWeeklySwimM / 1000,
            weeklyBlocks: weeklyBlocks,
            monthlyMilestones: milestones
        )
    }

    // MARK: - Weekly Blocks

    private func generateWeeklyBlocks(
        baseline: Baseline,
        goal: TrainingGoal,
        startDate: Date,
        calendar: Calendar
    ) -> [TrainingPlan.WeeklyBlock] {
        let targets = goal.weeklyTargets
        var blocks: [TrainingPlan.WeeklyBlock] = []

        for week in 0..<Self.planWeeks {
            let weekStart = calendar.date(byAdding: .weekOfYear, value: week, to: startDate) ?? startDate
            let isDeload = (week + 1) % Self.deloadEveryNWeeks == 0
            let progressFactor = 1.0 + Self.weeklyIncreaseRate * Double(week)
            let loadFactor = isDeload ? Self.deloadRatio : 1.0

            // Blend between baseline and goal targets, scaling progressively
            let targetRunKm = blendTarget(
                baseline: baseline.avgWeeklyRunKm,
                goalTarget: targets.runKm,
                progress: progressFactor
            ) * loadFactor

            let targetCycleKm = blendTarget(
                baseline: baseline.avgWeeklyCycleKm,
                goalTarget: targets.cycleKm,
                progress: progressFactor
            ) * loadFactor

            let targetSwimM = blendTarget(
                baseline: baseline.avgWeeklySwimM,
                goalTarget: targets.swimM,
                progress: progressFactor
            ) * loadFactor

            let targetSessions = isDeload
                ? max(targets.sessionsPerWeek - 1, 2)
                : max(Int(blendTarget(
                    baseline: baseline.avgWeeklySessions,
                    goalTarget: Double(targets.sessionsPerWeek),
                    progress: progressFactor
                )), 2)

            let workoutTargets = generateWorkoutTargets(
                weekNumber: week + 1,
                goal: goal,
                baseline: baseline,
                targetRunKm: targetRunKm,
                targetCycleKm: targetCycleKm,
                targetSwimM: targetSwimM,
                targetSessions: targetSessions,
                isDeload: isDeload,
                weekStart: weekStart,
                calendar: calendar
            )

            blocks.append(.init(
                weekNumber: week + 1,
                weekStart: weekStart,
                isDeloadWeek: isDeload,
                targetSessions: targetSessions,
                targetRunKm: targetRunKm.rounded(.down, precision: 1),
                targetCycleKm: targetCycleKm.rounded(.down, precision: 1),
                targetSwimM: (targetSwimM / 100).rounded() * 100,  // round to nearest 100m
                workoutTargets: workoutTargets
            ))
        }

        return blocks
    }

    /// Blend between current baseline and goal target with progressive scaling.
    /// Avoids jumping straight to goal targets — builds up gradually.
    private func blendTarget(baseline: Double, goalTarget: Double, progress: Double) -> Double {
        if goalTarget <= 0 { return baseline * progress }
        if baseline <= 0 { return goalTarget * 0.5 * progress }  // start at 50% of goal if no history
        // Move from baseline toward goal target
        let gap = goalTarget - baseline
        let step = gap * 0.25 * progress  // close 25% of gap per step
        return max(baseline + step, baseline * progress)
    }

    // MARK: - Per-Day Workout Targets

    private func generateWorkoutTargets(
        weekNumber: Int,
        goal: TrainingGoal,
        baseline: Baseline,
        targetRunKm: Double,
        targetCycleKm: Double,
        targetSwimM: Double,
        targetSessions: Int,
        isDeload: Bool,
        weekStart: Date,
        calendar: Calendar
    ) -> [TrainingPlan.WorkoutTarget] {
        var targets: [TrainingPlan.WorkoutTarget] = []

        // Determine training days (use user's typical days, or default pattern)
        let preferredDays = baseline.trainingDays.isEmpty
            ? defaultTrainingDays(sessions: targetSessions)
            : pickDays(from: baseline.trainingDays, count: targetSessions)

        let sortedDays = preferredDays.sorted()
        let sports = goal.involvedSports

        // Distribute workouts across days
        for (i, dayOfWeek) in sortedDays.enumerated() {
            let sport = sports[i % sports.count]

            let target: TrainingPlan.WorkoutTarget
            switch sport {
            case .running:
                target = makeRunTarget(
                    dayOfWeek: dayOfWeek,
                    index: i,
                    totalRuns: sortedDays.filter { _ in sport == .running }.count,
                    weeklyKm: targetRunKm,
                    baseline: baseline,
                    isDeload: isDeload,
                    goal: goal
                )
            case .cycling:
                target = makeCycleTarget(
                    dayOfWeek: dayOfWeek,
                    weeklyKm: targetCycleKm,
                    sessions: max(sortedDays.count / sports.count, 1),
                    isDeload: isDeload
                )
            case .swimming:
                target = makeSwimTarget(
                    dayOfWeek: dayOfWeek,
                    weeklyM: targetSwimM,
                    sessions: max(sortedDays.count / sports.count, 1),
                    isDeload: isDeload
                )
            }
            targets.append(target)
        }

        return targets
    }

    // MARK: - Run Targets

    private func makeRunTarget(
        dayOfWeek: Int,
        index: Int,
        totalRuns: Int,
        weeklyKm: Double,
        baseline: Baseline,
        isDeload: Bool,
        goal: TrainingGoal
    ) -> TrainingPlan.WorkoutTarget {
        // Distribute: one long run, one tempo/interval, rest easy
        let isLongRun = index == 0 && !isDeload && [.halfMarathon, .marathon, .tenK].contains(goal)
        let isQuality = index == 1 && !isDeload && totalRuns >= 3

        if isLongRun {
            let longKm = min(weeklyKm * 0.35, baseline.maxLongRunKm * 1.1)  // progressive long run
            let easyPace = (baseline.avgRunPaceSecPerKm ?? 360) * 1.1  // 10% slower than avg
            return .init(
                id: UUID(),
                dayOfWeek: dayOfWeek,
                typeRawValue: WorkoutType.running.rawValue,
                name: "Long Run",
                description: String(format: "Easy pace, build endurance. Target %.1f km.", longKm),
                targetDistanceMeters: longKm * 1000,
                targetDurationMinutes: Int(longKm * easyPace / 60),
                targetPaceSecondsPerKm: easyPace,
                targetHRZone: "aerobic",
                intensity: .moderate
            )
        } else if isQuality {
            let tempoPace = (baseline.avgRunPaceSecPerKm ?? 330) * 0.95
            let tempoKm = weeklyKm * 0.2
            return .init(
                id: UUID(),
                dayOfWeek: dayOfWeek,
                typeRawValue: WorkoutType.running.rawValue,
                name: "Tempo Run",
                description: "Sustained effort at threshold pace. Include warm-up and cool-down.",
                targetDistanceMeters: tempoKm * 1000,
                targetDurationMinutes: Int(tempoKm * tempoPace / 60),
                targetPaceSecondsPerKm: tempoPace,
                targetHRZone: "threshold",
                intensity: .hard
            )
        } else {
            let easyKm = weeklyKm / Double(max(totalRuns, 1))
            let easyPace = (baseline.avgRunPaceSecPerKm ?? 360) * 1.1
            return .init(
                id: UUID(),
                dayOfWeek: dayOfWeek,
                typeRawValue: WorkoutType.running.rawValue,
                name: isDeload ? "Recovery Run" : "Easy Run",
                description: isDeload
                    ? "Very easy effort. Focus on recovery."
                    : String(format: "Comfortable pace, %.1f km.", easyKm),
                targetDistanceMeters: easyKm * 1000,
                targetDurationMinutes: Int(easyKm * easyPace / 60),
                targetPaceSecondsPerKm: easyPace,
                targetHRZone: "easy",
                intensity: .easy
            )
        }
    }

    // MARK: - Cycle Targets

    private func makeCycleTarget(
        dayOfWeek: Int,
        weeklyKm: Double,
        sessions: Int,
        isDeload: Bool
    ) -> TrainingPlan.WorkoutTarget {
        let perSession = weeklyKm / Double(max(sessions, 1))
        return .init(
            id: UUID(),
            dayOfWeek: dayOfWeek,
            typeRawValue: WorkoutType.cycling.rawValue,
            name: isDeload ? "Recovery Ride" : "Steady Ride",
            description: isDeload
                ? "Easy spin for active recovery."
                : String(format: "Maintain steady effort, %.0f km.", perSession),
            targetDistanceMeters: perSession * 1000,
            targetDurationMinutes: Int(perSession / 25 * 60),  // ~25 km/h estimate
            targetPaceSecondsPerKm: nil,
            targetHRZone: isDeload ? "easy" : "aerobic",
            intensity: isDeload ? .easy : .moderate
        )
    }

    // MARK: - Swim Targets

    private func makeSwimTarget(
        dayOfWeek: Int,
        weeklyM: Double,
        sessions: Int,
        isDeload: Bool
    ) -> TrainingPlan.WorkoutTarget {
        let perSession = weeklyM / Double(max(sessions, 1))
        return .init(
            id: UUID(),
            dayOfWeek: dayOfWeek,
            typeRawValue: WorkoutType.swimming.rawValue,
            name: isDeload ? "Easy Swim" : "Technique Swim",
            description: isDeload
                ? "Easy laps focusing on relaxation."
                : String(format: "Mix drills and freestyle, %.0f m.", perSession),
            targetDistanceMeters: perSession,
            targetDurationMinutes: Int(perSession / 50),  // ~50m/min estimate
            targetPaceSecondsPerKm: nil,
            targetHRZone: isDeload ? "easy" : "aerobic",
            intensity: isDeload ? .easy : .moderate
        )
    }

    // MARK: - Monthly Milestones

    private func generateMilestones(
        baseline: Baseline,
        goal: TrainingGoal,
        startDate: Date,
        calendar: Calendar
    ) -> [TrainingPlan.MonthlyMilestone] {
        var milestones: [TrainingPlan.MonthlyMilestone] = []
        let targets = goal.weeklyTargets

        for monthOffset in 0..<3 {
            guard let monthDate = calendar.date(byAdding: .month, value: monthOffset, to: startDate),
                  let monthStart = calendar.dateInterval(of: .month, for: monthDate)?.start else { continue }

            let progressFactor = 1.0 + Self.weeklyIncreaseRate * Double((monthOffset + 1) * 4)

            let title: String
            let detail: String
            var targetWeeklyKm: Double? = nil
            var targetLongRunKm: Double? = nil

            switch monthOffset {
            case 0:
                let weeklyKm = blendTarget(baseline: baseline.avgWeeklyRunKm, goalTarget: targets.runKm, progress: progressFactor)
                targetWeeklyKm = weeklyKm
                title = "Build Base"
                detail = String(format: "Reach %.0f km/week running volume. Focus on consistency.", weeklyKm)

            case 1:
                let longRun = min(baseline.maxLongRunKm * 1.3, targets.runKm * 0.4)
                targetLongRunKm = longRun
                let weeklyKm = blendTarget(baseline: baseline.avgWeeklyRunKm, goalTarget: targets.runKm, progress: progressFactor)
                targetWeeklyKm = weeklyKm
                title = "Increase Volume"
                detail = String(format: "Weekly volume to %.0f km. Long run to %.1f km.", weeklyKm, longRun)

            default:
                let weeklyKm = blendTarget(baseline: baseline.avgWeeklyRunKm, goalTarget: targets.runKm, progress: progressFactor)
                targetWeeklyKm = weeklyKm
                title = "Sharpen Fitness"
                detail = String(format: "Maintain %.0f km/week. Add tempo and speed work.", weeklyKm)
            }

            milestones.append(.init(
                id: UUID(),
                month: monthStart,
                title: title,
                detail: detail,
                targetWeeklyKm: targetWeeklyKm,
                targetLongRunKm: targetLongRunKm
            ))
        }

        return milestones
    }

    // MARK: - Helpers

    private func defaultTrainingDays(sessions: Int) -> [Int] {
        // Mon(2), Wed(4), Fri(6), Sat(7), Tue(3), Thu(5), Sun(1)
        let preferred = [2, 4, 6, 7, 3, 5, 1]
        return Array(preferred.prefix(sessions))
    }

    private func pickDays(from available: Set<Int>, count: Int) -> [Int] {
        let sorted = available.sorted()
        if sorted.count <= count { return sorted }
        // Spread evenly
        let step = Double(sorted.count) / Double(count)
        return (0..<count).map { sorted[Int(Double($0) * step)] }
    }
}

// MARK: - Double rounding helper

private extension Double {
    func rounded(_ rule: FloatingPointRoundingRule, precision: Int) -> Double {
        let factor = pow(10.0, Double(precision))
        return (self * factor).rounded(rule) / factor
    }
}
