import Foundation
import os

let aiCoachLogger = Logger(subsystem: "com.loganwang.FitSync", category: "AICoach")
let aiCoachRequestTimeout: TimeInterval = 180

// MARK: - Provider Protocol

protocol AICoachProvider {
    var name: String { get }
    func complete(systemPrompt: String, userPrompt: String) async throws -> String
}

// MARK: - AI Coach Service

final class AICoachService {
    static let shared = AICoachService()

    fileprivate static let claudeKeyID = "com.fitsync.claude-api-key"
    fileprivate static let kimiKeyID = "com.fitsync.kimi-api-key"
    private static let providerKey = "aiCoachProvider"
    private static let enabledKey = "aiCoachEnabled"
    private static let kimiThinkingKey = "aiCoachKimiThinking"

    static var kimiThinkingEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: kimiThinkingKey) }
        set { UserDefaults.standard.set(newValue, forKey: kimiThinkingKey) }
    }

    /// (model, temperature) for the current Kimi mode.
    static var kimiConfig: (model: String, temperature: Double) {
        kimiThinkingEnabled
            ? (model: "kimi-k2.6", temperature: 1.0)
            : (model: "kimi-k2-turbo-preview", temperature: 0.6)
    }

    enum Provider: String, CaseIterable, Identifiable {
        case claude = "Claude"
        case kimi = "Kimi"
        var id: String { rawValue }
    }

    static var selectedProvider: Provider {
        get {
            guard let raw = UserDefaults.standard.string(forKey: providerKey) else { return .claude }
            return Provider(rawValue: raw) ?? .claude
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: providerKey) }
    }

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var hasAPIKey: Bool {
        switch selectedProvider {
        case .claude: KeychainHelper.loadString(key: claudeKeyID) != nil
        case .kimi: KeychainHelper.loadString(key: kimiKeyID) != nil
        }
    }

    static func saveAPIKey(_ key: String, for provider: Provider) {
        let keyID = provider == .claude ? claudeKeyID : kimiKeyID
        if key.isEmpty {
            KeychainHelper.delete(key: keyID)
        } else {
            KeychainHelper.saveString(key, key: keyID)
        }
    }

    static func loadAPIKey(for provider: Provider) -> String {
        let keyID = provider == .claude ? claudeKeyID : kimiKeyID
        return KeychainHelper.loadString(key: keyID) ?? ""
    }

    // MARK: - Enhancement

    func enhance(
        workout: Workout,
        recentWorkouts: [Workout],
        goal: TrainingGoal?
    ) async throws -> CoachAnalysis {
        let provider = makeProvider()
        guard let provider else { throw CoachError.noAPIKey }

        let systemPrompt = """
        You are an experienced endurance coach. Analyze the workout data provided and return \
        a JSON object with the exact structure shown. Be data-driven, specific, and encouraging. \
        Focus on actionable insights the athlete can use immediately.

        Return ONLY valid JSON with this structure:
        {
          "observations": [{"category": "pace|heartRate|power|form|endurance|recovery|training", "title": "...", "detail": "...", "sentiment": "positive|neutral|caution"}],
          "recommendations": [{"title": "...", "detail": "...", "type": "nextWorkout|technique|recovery|goalProgress"}],
          "suggestedWorkouts": [{"name": "...", "description": "...", "workoutTypeRaw": null|0|1|2, "durationMinutes": 30, "intensity": "easy|moderate|hard"}]
        }
        workoutTypeRaw: 0=running, 1=cycling, 2=swimming, null=other
        """

        let userPrompt = buildUserPrompt(
            workout: workout,
            recentWorkouts: recentWorkouts,
            goal: goal
        )

        let response = try await provider.complete(systemPrompt: systemPrompt, userPrompt: userPrompt)
        return try parseResponse(response, source: AICoachService.selectedProvider == .claude ? .claude : .kimi)
    }

    // MARK: - Follow-up Q&A

    func askFollowUp(
        workout: Workout,
        priorAnalysis: CoachAnalysis,
        priorQAs: [(question: String, answer: String)],
        newQuestion: String,
        recentWorkouts: [Workout],
        goal: TrainingGoal?
    ) async throws -> String {
        let provider = makeProvider()
        guard let provider else { throw CoachError.noAPIKey }

        let systemPrompt = """
        You are an experienced endurance coach helping an athlete understand their workout. \
        Answer questions conversationally in plain text — no markdown, no JSON, no headings, no bullet lists. \
        Be concise (2-4 sentences) and data-driven. Reference the workout metrics when relevant.
        """

        var userPrompt = buildUserPrompt(
            workout: workout,
            recentWorkouts: recentWorkouts,
            goal: goal
        )
        let priorObs = priorAnalysis.observations.map { "- \($0.title): \($0.detail)" }.joined(separator: "\n")
        if !priorObs.isEmpty {
            userPrompt += "\n\nPrior coach observations:\n\(priorObs)"
        }
        userPrompt += "\n\n--- Conversation ---"
        for qa in priorQAs {
            userPrompt += "\nAthlete: \(qa.question)\nCoach: \(qa.answer)"
        }
        userPrompt += "\nAthlete: \(newQuestion)\nCoach:"

        return try await provider.complete(systemPrompt: systemPrompt, userPrompt: userPrompt)
    }

    // MARK: - Private

    private func makeProvider() -> AICoachProvider? {
        switch AICoachService.selectedProvider {
        case .claude:
            guard let key = KeychainHelper.loadString(key: AICoachService.claudeKeyID) else { return nil }
            return ClaudeProvider(apiKey: key)
        case .kimi:
            guard let key = KeychainHelper.loadString(key: AICoachService.kimiKeyID) else { return nil }
            return KimiProvider(apiKey: key)
        }
    }

    private func buildUserPrompt(
        workout: Workout,
        recentWorkouts: [Workout],
        goal: TrainingGoal?
    ) -> String {
        var parts: [String] = []

        // Workout summary
        let type = workout.type.label
        let duration = Int(workout.durationSeconds / 60)
        let dist = workout.distanceMeters.map { String(format: "%.2f km", $0 / 1000) } ?? "N/A"
        parts.append("Workout: \(type), \(duration) min, \(dist)")

        if let pace = workout.avgPaceSecondsPerKm {
            let m = Int(pace) / 60; let s = Int(pace) % 60
            parts.append("Pace: \(m)'\(String(format: "%02d", s))\"/km")
        }
        if let hr = workout.cachedAvgHeartRate {
            parts.append(String(format: "Avg HR: %.0f bpm", hr))
        }
        if let maxHR = workout.cachedMaxHeartRate {
            parts.append(String(format: "Max HR: %.0f bpm", maxHR))
        }
        if let power = workout.cachedAvgPowerWatts {
            parts.append(String(format: "Avg Power: %.0fW", power))
        }
        if let cadence = workout.cachedAvgCadenceSpm {
            parts.append(String(format: "Cadence: %.0f spm", cadence))
        }
        if let gct = workout.cachedAvgGroundContactTimeMs {
            parts.append(String(format: "Ground Contact: %.0f ms", gct))
        }

        if let goal {
            parts.append("Training Goal: \(goal.label)")
        }

        // Recent context
        let recentSummary = recentWorkouts.prefix(5).map { w in
            "\(w.type.label) \(w.startDate.formatted(.dateTime.month(.abbreviated).day())) \(Int(w.durationSeconds/60))min"
        }.joined(separator: ", ")
        if !recentSummary.isEmpty {
            parts.append("Recent workouts: \(recentSummary)")
        }

        return parts.joined(separator: "\n")
    }

    private func parseResponse(_ text: String, source: CoachAnalysis.AnalysisSource) throws -> CoachAnalysis {
        // Extract JSON from response (may have markdown fences)
        let cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8) else { throw CoachError.invalidResponse }

        struct AIResponse: Decodable {
            let observations: [CoachAnalysis.Observation]?
            let recommendations: [CoachAnalysis.Recommendation]?
            let suggestedWorkouts: [CoachAnalysis.SuggestedWorkout]?
        }

        let decoded = try JSONDecoder().decode(AIResponse.self, from: data)
        return CoachAnalysis(
            observations: decoded.observations ?? [],
            recommendations: decoded.recommendations ?? [],
            suggestedWorkouts: decoded.suggestedWorkouts ?? [],
            source: source,
            generatedDate: .now
        )
    }

    enum CoachError: LocalizedError {
        case noAPIKey
        case invalidResponse
        case apiError(String)

        var errorDescription: String? {
            switch self {
            case .noAPIKey: "No API key configured"
            case .invalidResponse: "Could not parse AI response"
            case .apiError(let msg): msg
            }
        }
    }
}

// MARK: - Claude Provider (Anthropic Messages API)

private struct ClaudeProvider: AICoachProvider {
    let apiKey: String
    var name: String { "Claude" }

    func complete(systemPrompt: String, userPrompt: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = aiCoachRequestTimeout
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "model": "claude-sonnet-4-6",
            "max_tokens": 1024,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": userPrompt]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let start = Date()
        aiCoachLogger.info("Claude enhance request start")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            aiCoachLogger.error("Claude enhance transport error after \(Date().timeIntervalSince(start), format: .fixed(precision: 1))s: \(error.localizedDescription)")
            throw error
        }
        let elapsed = Date().timeIntervalSince(start)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
            let msg = (json?["error"] as? [String: Any])?["message"] as? String
                ?? "HTTP \(httpResponse.statusCode)"
            aiCoachLogger.error("Claude enhance HTTP \(httpResponse.statusCode) after \(elapsed, format: .fixed(precision: 1))s: \(msg)")
            throw AICoachService.CoachError.apiError("Claude API: \(msg)")
        }

        aiCoachLogger.info("Claude enhance ok in \(elapsed, format: .fixed(precision: 1))s")
        guard let content = json?["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String else {
            throw AICoachService.CoachError.invalidResponse
        }
        return text
    }
}

// MARK: - Kimi Provider (Moonshot OpenAI-compatible API)

private struct KimiProvider: AICoachProvider {
    let apiKey: String
    var name: String { "Kimi" }

    func complete(systemPrompt: String, userPrompt: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.moonshot.ai/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = aiCoachRequestTimeout
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let cfg = AICoachService.kimiConfig
        let body: [String: Any] = [
            "model": cfg.model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "temperature": cfg.temperature
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let start = Date()
        aiCoachLogger.info("Kimi enhance request start model=\(cfg.model)")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            aiCoachLogger.error("Kimi enhance transport error after \(Date().timeIntervalSince(start), format: .fixed(precision: 1))s: \(error.localizedDescription)")
            throw error
        }
        let elapsed = Date().timeIntervalSince(start)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
            let msg = (json?["error"] as? [String: Any])?["message"] as? String
                ?? "HTTP \(httpResponse.statusCode)"
            aiCoachLogger.error("Kimi enhance HTTP \(httpResponse.statusCode) after \(elapsed, format: .fixed(precision: 1))s: \(msg)")
            throw AICoachService.CoachError.apiError("Kimi API: \(msg)")
        }

        aiCoachLogger.info("Kimi enhance ok in \(elapsed, format: .fixed(precision: 1))s")
        guard let choices = json?["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let text = message["content"] as? String else {
            throw AICoachService.CoachError.invalidResponse
        }
        return text
    }
}
