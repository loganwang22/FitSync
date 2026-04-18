import Foundation

/// Tools the AI coach can call to retrieve training data. Defines a
/// provider-neutral schema (JSONSchema) plus a local executor that queries
/// SwiftData and HealthKit.
struct CoachTool {
    let name: String
    let description: String
    /// JSONSchema `input_schema` / `parameters` object.
    let inputSchema: [String: Any]
}

@MainActor
final class CoachToolExecutor {
    let repository: WorkoutRepository
    let healthKit: HealthKitService
    var onToolStart: ((String) -> Void)?

    init(repository: WorkoutRepository, healthKit: HealthKitService) {
        self.repository = repository
        self.healthKit = healthKit
    }

    static let iso = ISO8601DateFormatter()

    /// Tool catalog shared by Claude and Kimi. Description-rich so the model
    /// picks the right one.
    static let tools: [CoachTool] = [
        CoachTool(
            name: "get_current_date",
            description: "Returns today's date and day-of-week. Call this first when the user references relative dates like 'last week' or 'yesterday'.",
            inputSchema: [
                "type": "object",
                "properties": [:] as [String: Any],
                "required": [] as [String]
            ]
        ),
        CoachTool(
            name: "list_workouts",
            description: "Lists workouts in a date range. Returns type, date, duration, distance, pace, HR, power, cadence. Use this to answer questions about training history.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "from_date": ["type": "string", "description": "ISO 8601 date (YYYY-MM-DD) — inclusive start"],
                    "to_date": ["type": "string", "description": "ISO 8601 date (YYYY-MM-DD) — inclusive end"],
                    "type": ["type": "string", "enum": ["running", "cycling", "swimming", "all"], "description": "Filter by workout type; omit or use 'all' for all types"]
                ],
                "required": ["from_date", "to_date"]
            ]
        ),
        CoachTool(
            name: "get_workout_detail",
            description: "Returns detailed metrics for a single workout including HR, power, cadence, stride length, ground contact time, and existing AI analysis if cached.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "workout_id": ["type": "string", "description": "The healthKitUUID of the workout"]
                ],
                "required": ["workout_id"]
            ]
        ),
        CoachTool(
            name: "summarize_period",
            description: "Returns aggregated training stats (total distance, duration, session count, avg pace) for a date range, optionally broken down by sport.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "from_date": ["type": "string", "description": "ISO 8601 date (YYYY-MM-DD)"],
                    "to_date": ["type": "string", "description": "ISO 8601 date (YYYY-MM-DD)"]
                ],
                "required": ["from_date", "to_date"]
            ]
        ),
        CoachTool(
            name: "get_health_trend",
            description: "Returns cardio health samples (VO2 max, resting heart rate, or heart rate variability) over a period. Useful for fitness trend questions.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "metric": ["type": "string", "enum": ["vo2_max", "resting_hr", "hrv"], "description": "Which health metric to fetch"],
                    "days_back": ["type": "integer", "description": "How many days back from today (1-365)"]
                ],
                "required": ["metric", "days_back"]
            ]
        ),
        CoachTool(
            name: "get_training_goal",
            description: "Returns the athlete's current training goal (if set) and weekly targets.",
            inputSchema: [
                "type": "object",
                "properties": [:] as [String: Any],
                "required": [] as [String]
            ]
        )
    ]

    // MARK: - Dispatch

    func execute(name: String, argumentsJSON: String) async -> String {
        onToolStart?(name)
        let args = (try? JSONSerialization.jsonObject(with: Data(argumentsJSON.utf8)) as? [String: Any]) ?? [:]
        do {
            switch name {
            case "get_current_date":     return getCurrentDate()
            case "list_workouts":        return try listWorkouts(args)
            case "get_workout_detail":   return try getWorkoutDetail(args)
            case "summarize_period":     return try summarizePeriod(args)
            case "get_health_trend":     return try await getHealthTrend(args)
            case "get_training_goal":    return getTrainingGoal()
            default:                     return encodeError("Unknown tool: \(name)")
            }
        } catch {
            return encodeError(error.localizedDescription)
        }
    }

    // MARK: - Tool implementations

    private func getCurrentDate() -> String {
        let now = Date.now
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let day = Calendar.current.component(.weekday, from: now)
        let weekdayNames = ["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"]
        let payload: [String: Any] = [
            "today": formatter.string(from: now),
            "day_of_week": weekdayNames[day - 1]
        ]
        return jsonString(payload)
    }

    private func listWorkouts(_ args: [String: Any]) throws -> String {
        guard let fromStr = args["from_date"] as? String,
              let toStr = args["to_date"] as? String else {
            throw ToolError.invalidArgs("from_date and to_date required")
        }
        let from = try parseDate(fromStr)
        let to = try parseDate(toStr).addingTimeInterval(86399) // end-of-day

        let typeStr = args["type"] as? String
        let type: WorkoutType? = {
            switch typeStr {
            case "running": return .running
            case "cycling": return .cycling
            case "swimming": return .swimming
            default: return nil
            }
        }()

        let all = repository.fetchWorkouts(type: type)
        let filtered = all.filter { $0.startDate >= from && $0.startDate <= to }

        let items: [[String: Any]] = filtered.map { workoutToDict($0) }
        return jsonString(["count": items.count, "workouts": items])
    }

    private func getWorkoutDetail(_ args: [String: Any]) throws -> String {
        guard let id = args["workout_id"] as? String else {
            throw ToolError.invalidArgs("workout_id required")
        }
        guard let w = repository.fetchWorkouts().first(where: { $0.healthKitUUID == id }) else {
            return encodeError("Workout not found")
        }
        var dict = workoutToDict(w)
        if let gct = w.cachedAvgGroundContactTimeMs { dict["avg_ground_contact_ms"] = Int(gct) }
        if let stride = w.cachedAvgStrideLengthMeters { dict["avg_stride_length_m"] = round(stride * 100) / 100 }
        if let laps = w.laps { dict["laps"] = laps }
        if let strokes = w.strokeCount { dict["strokes"] = strokes }
        if let cached = w.cachedCoachAnalysis {
            dict["prior_ai_observations"] = cached.observations.map { "\($0.title): \($0.detail)" }
        }
        return jsonString(dict)
    }

    private func workoutToDict(_ w: Workout) -> [String: Any] {
        var dict: [String: Any] = [:]
        dict["id"] = w.healthKitUUID
        dict["type"] = w.type.label.lowercased()
        dict["date"] = formatDate(w.startDate)
        dict["duration_minutes"] = Int(w.durationSeconds / 60)
        if let d = w.distanceMeters { dict["distance_km"] = round(d / 10) / 100 }
        if let p = w.avgPaceSecondsPerKm { dict["avg_pace_seconds_per_km"] = Int(p) }
        if let s = w.avgSpeedMps { dict["avg_speed_mps"] = round(s * 100) / 100 }
        if let hr = w.cachedAvgHeartRate { dict["avg_hr"] = Int(hr) }
        if let maxHR = w.cachedMaxHeartRate { dict["max_hr"] = Int(maxHR) }
        if let pw = w.cachedAvgPowerWatts { dict["avg_power_w"] = Int(pw) }
        if let cad = w.cachedAvgCadenceSpm { dict["avg_cadence_spm"] = Int(cad) }
        if let el = w.elevationGainMeters { dict["elevation_gain_m"] = Int(el) }
        if let kcal = w.activeEnergyKcal { dict["calories"] = Int(kcal) }
        return dict
    }

    private func summarizePeriod(_ args: [String: Any]) throws -> String {
        guard let fromStr = args["from_date"] as? String,
              let toStr = args["to_date"] as? String else {
            throw ToolError.invalidArgs("from_date and to_date required")
        }
        let from = try parseDate(fromStr)
        let to = try parseDate(toStr).addingTimeInterval(86399)

        let all = repository.fetchWorkouts()
        let inRange = all.filter { $0.startDate >= from && $0.startDate <= to }

        func bucket(_ type: WorkoutType) -> [String: Any] {
            let filtered = inRange.filter { $0.type == type }
            let totalDist = filtered.compactMap(\.distanceMeters).reduce(0, +)
            let totalDur = filtered.map(\.durationSeconds).reduce(0, +)
            let paces = filtered.compactMap(\.avgPaceSecondsPerKm)
            let avgPace = paces.isEmpty ? nil : paces.reduce(0, +) / Double(paces.count)
            var dict: [String: Any] = [
                "count": filtered.count,
                "total_distance_km": round(totalDist / 10) / 100,
                "total_duration_minutes": Int(totalDur / 60)
            ]
            if let avgPace { dict["avg_pace_seconds_per_km"] = Int(avgPace) }
            return dict
        }

        let payload: [String: Any] = [
            "from": fromStr,
            "to": toStr,
            "overall_count": inRange.count,
            "overall_duration_minutes": Int(inRange.map(\.durationSeconds).reduce(0, +) / 60),
            "running": bucket(.running),
            "cycling": bucket(.cycling),
            "swimming": bucket(.swimming)
        ]
        return jsonString(payload)
    }

    private func getHealthTrend(_ args: [String: Any]) async throws -> String {
        guard let metric = args["metric"] as? String,
              let daysBack = args["days_back"] as? Int else {
            throw ToolError.invalidArgs("metric and days_back required")
        }
        let from = Calendar.current.date(byAdding: .day, value: -max(1, min(daysBack, 365)), to: .now) ?? .now

        switch metric {
        case "vo2_max":
            let samples = try await healthKit.fetchVO2MaxSamples(from: from)
            let values = samples.map { ["date": formatDate($0.date), "value": round($0.value * 10) / 10] as [String: Any] }
            return jsonString(["metric": "vo2_max", "unit": "ml/kg/min", "samples": values])
        case "resting_hr":
            let samples = try await healthKit.fetchRestingHeartRate(from: from)
            let values = samples.map { ["date": formatDate($0.date), "value": Int($0.bpm)] as [String: Any] }
            return jsonString(["metric": "resting_hr", "unit": "bpm", "samples": values])
        case "hrv":
            let samples = try await healthKit.fetchHRV(from: from)
            let values = samples.map { ["date": formatDate($0.date), "value": round($0.ms * 10) / 10] as [String: Any] }
            return jsonString(["metric": "hrv", "unit": "ms", "samples": values])
        default:
            throw ToolError.invalidArgs("Unknown metric: \(metric)")
        }
    }

    private func getTrainingGoal() -> String {
        let raw = UserDefaults.standard.object(forKey: "trainingGoalRawValue") as? Int
        guard let raw, let goal = TrainingGoal(rawValue: raw) else {
            return jsonString(["goal": NSNull()])
        }
        let targets = goal.weeklyTargets
        return jsonString([
            "goal": goal.label,
            "description": goal.description,
            "weekly_targets": [
                "sessions": targets.sessionsPerWeek,
                "running_km": targets.runKm,
                "cycling_km": targets.cycleKm,
                "swimming_m": targets.swimM
            ]
        ])
    }

    // MARK: - Helpers

    private func parseDate(_ str: String) throws -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = Calendar.current.timeZone
        guard let date = formatter.date(from: str) else {
            throw ToolError.invalidArgs("Invalid date: \(str). Expected YYYY-MM-DD.")
        }
        return date
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func jsonString(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }

    private func encodeError(_ message: String) -> String {
        jsonString(["error": message])
    }

    enum ToolError: LocalizedError {
        case invalidArgs(String)
        var errorDescription: String? {
            switch self {
            case .invalidArgs(let m): return m
            }
        }
    }
}
