import Foundation

// MARK: - Provider Protocol

protocol AICoachProvider {
    var name: String { get }
    func complete(systemPrompt: String, userPrompt: String) async throws -> String
}

// MARK: - AI Coach Service

final class AICoachService {
    static let shared = AICoachService()

    private static let claudeKeyID = "com.fitsync.claude-api-key"
    private static let kimiKeyID = "com.fitsync.kimi-api-key"
    private static let providerKey = "aiCoachProvider"
    private static let enabledKey = "aiCoachEnabled"

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
        baseAnalysis: CoachAnalysis,
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
            baseAnalysis: baseAnalysis,
            recentWorkouts: recentWorkouts,
            goal: goal
        )

        let response = try await provider.complete(systemPrompt: systemPrompt, userPrompt: userPrompt)
        return try parseResponse(response, source: AICoachService.selectedProvider == .claude ? .claude : .kimi)
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
        baseAnalysis: CoachAnalysis,
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

        // On-device observations summary
        let obsText = baseAnalysis.observations.map { "- \($0.title): \($0.detail)" }.joined(separator: "\n")
        if !obsText.isEmpty {
            parts.append("On-device observations:\n\(obsText)")
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
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 1024,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": userPrompt]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        // Surface API errors (auth failure, rate limit, etc.)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
            let msg = (json?["error"] as? [String: Any])?["message"] as? String
                ?? "HTTP \(httpResponse.statusCode)"
            throw AICoachService.CoachError.apiError("Claude API: \(msg)")
        }

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
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "model": "moonshot-v1-8k",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "temperature": 0.3
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        // Surface API errors (auth failure, rate limit, etc.)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
            let msg = (json?["error"] as? [String: Any])?["message"] as? String
                ?? "HTTP \(httpResponse.statusCode)"
            throw AICoachService.CoachError.apiError("Kimi API: \(msg)")
        }

        guard let choices = json?["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let text = message["content"] as? String else {
            throw AICoachService.CoachError.invalidResponse
        }
        return text
    }
}
