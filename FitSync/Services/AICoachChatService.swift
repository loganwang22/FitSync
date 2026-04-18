import Foundation

/// Chat with tool-use for the AI coach. Runs an iterative loop where the model
/// can call local tools (via `CoachToolExecutor`) to retrieve training data,
/// then produces a final plain-text answer.
extension AICoachService {

    static let coachChatSystemPrompt = """
    You are an expert endurance training coach integrated into FitSync, a fitness tracking app. \
    You help the athlete understand their workouts, review training trends, and plan future sessions.

    You have tools to fetch the athlete's actual training data from their device. \
    When the athlete asks about their workouts, trends, or performance, ALWAYS use the tools \
    to get real data before answering — never guess or fabricate metrics.

    Before answering questions that reference relative dates like "last week" or "recently", \
    call get_current_date first to anchor your time reasoning.

    Respond in a conversational, encouraging tone. Use plain text — no markdown, no bullet lists, \
    no headings. Be specific and cite actual numbers from the data. Keep answers tight (2-5 sentences) \
    unless the question explicitly asks for detail.
    """

    @MainActor
    func chat(
        history: [CoachChatMessage],
        toolExecutor: CoachToolExecutor,
        maxRounds: Int = 5
    ) async throws -> [CoachChatMessage] {
        switch AICoachService.selectedProvider {
        case .claude:
            return try await claudeChat(history: history, toolExecutor: toolExecutor, maxRounds: maxRounds)
        case .kimi:
            return try await kimiChat(history: history, toolExecutor: toolExecutor, maxRounds: maxRounds)
        }
    }

    // MARK: - Claude

    @MainActor
    private func claudeChat(
        history: [CoachChatMessage],
        toolExecutor: CoachToolExecutor,
        maxRounds: Int
    ) async throws -> [CoachChatMessage] {
        guard let apiKey = AICoachService.loadAPIKey(for: .claude).nilIfEmpty else {
            throw CoachError.noAPIKey
        }

        var apiMessages: [[String: Any]] = history.compactMap { (msg: CoachChatMessage) -> [String: Any]? in
            switch msg.role {
            case .user:
                return ["role": "user", "content": msg.text]
            case .assistant:
                var blocks: [[String: Any]] = []
                if !msg.text.isEmpty {
                    blocks.append(["type": "text", "text": msg.text])
                }
                for tc in msg.toolCalls {
                    let input = (try? JSONSerialization.jsonObject(with: Data(tc.arguments.utf8))) ?? [:]
                    blocks.append([
                        "type": "tool_use",
                        "id": tc.id,
                        "name": tc.name,
                        "input": input
                    ])
                }
                return blocks.isEmpty ? nil : ["role": "assistant", "content": blocks]
            case .tool:
                let blocks: [[String: Any]] = msg.toolResults.map {
                    ["type": "tool_result", "tool_use_id": $0.id, "content": $0.content]
                }
                return blocks.isEmpty ? nil : ["role": "user", "content": blocks]
            case .system:
                return nil
            }
        }

        let tools: [[String: Any]] = CoachToolExecutor.tools.map { tool in
            [
                "name": tool.name,
                "description": tool.description,
                "input_schema": tool.inputSchema
            ]
        }

        var newMessages: [CoachChatMessage] = []

        for _ in 0..<maxRounds {
            let body: [String: Any] = [
                "model": "claude-sonnet-4-6",
                "max_tokens": 2048,
                "system": AICoachService.coachChatSystemPrompt,
                "tools": tools,
                "messages": apiMessages
            ]

            var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            request.httpMethod = "POST"
            request.timeoutInterval = aiCoachRequestTimeout
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let start = Date()
            aiCoachLogger.info("Claude chat round start")
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await URLSession.shared.data(for: request)
            } catch {
                aiCoachLogger.error("Claude chat transport error after \(Date().timeIntervalSince(start), format: .fixed(precision: 1))s: \(error.localizedDescription)")
                throw error
            }
            let elapsed = Date().timeIntervalSince(start)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                let msg = (json?["error"] as? [String: Any])?["message"] as? String
                    ?? "HTTP \(httpResponse.statusCode)"
                aiCoachLogger.error("Claude chat HTTP \(httpResponse.statusCode) after \(elapsed, format: .fixed(precision: 1))s: \(msg)")
                throw CoachError.apiError("Claude API: \(msg)")
            }

            let stopReason = json?["stop_reason"] as? String
            aiCoachLogger.info("Claude chat round ok in \(elapsed, format: .fixed(precision: 1))s stop=\(stopReason ?? "nil")")
            let content = json?["content"] as? [[String: Any]] ?? []

            var text = ""
            var toolCalls: [CoachChatMessage.ToolCall] = []

            for block in content {
                guard let type = block["type"] as? String else { continue }
                if type == "text", let t = block["text"] as? String {
                    text += t
                } else if type == "tool_use",
                          let id = block["id"] as? String,
                          let name = block["name"] as? String {
                    let input = block["input"] ?? [:]
                    let argStr: String
                    if let argData = try? JSONSerialization.data(withJSONObject: input),
                       let str = String(data: argData, encoding: .utf8) {
                        argStr = str
                    } else {
                        argStr = "{}"
                    }
                    toolCalls.append(.init(id: id, name: name, arguments: argStr))
                }
            }

            newMessages.append(CoachChatMessage(role: .assistant, text: text, toolCalls: toolCalls))
            apiMessages.append(["role": "assistant", "content": content])

            if stopReason == "tool_use" && !toolCalls.isEmpty {
                var results: [CoachChatMessage.ToolResult] = []
                var resultBlocks: [[String: Any]] = []
                for tc in toolCalls {
                    let output = await toolExecutor.execute(name: tc.name, argumentsJSON: tc.arguments)
                    results.append(.init(id: tc.id, name: tc.name, content: output))
                    resultBlocks.append([
                        "type": "tool_result",
                        "tool_use_id": tc.id,
                        "content": output
                    ])
                }
                newMessages.append(CoachChatMessage(role: .tool, toolResults: results))
                apiMessages.append(["role": "user", "content": resultBlocks])
                continue
            }

            break
        }

        return newMessages
    }

    // MARK: - Kimi (OpenAI-compatible)

    @MainActor
    private func kimiChat(
        history: [CoachChatMessage],
        toolExecutor: CoachToolExecutor,
        maxRounds: Int
    ) async throws -> [CoachChatMessage] {
        guard let apiKey = AICoachService.loadAPIKey(for: .kimi).nilIfEmpty else {
            throw CoachError.noAPIKey
        }

        var apiMessages: [[String: Any]] = [
            ["role": "system", "content": AICoachService.coachChatSystemPrompt]
        ]

        for msg in history {
            switch msg.role {
            case .system:
                continue
            case .user:
                apiMessages.append(["role": "user", "content": msg.text])
            case .assistant:
                var dict: [String: Any] = ["role": "assistant"]
                dict["content"] = msg.text.isEmpty ? NSNull() : msg.text
                if let reasoning = msg.reasoningContent, !reasoning.isEmpty {
                    dict["reasoning_content"] = reasoning
                }
                if !msg.toolCalls.isEmpty {
                    dict["tool_calls"] = msg.toolCalls.map { tc in
                        [
                            "id": tc.id,
                            "type": "function",
                            "function": [
                                "name": tc.name,
                                "arguments": tc.arguments
                            ]
                        ]
                    }
                }
                apiMessages.append(dict)
            case .tool:
                for result in msg.toolResults {
                    apiMessages.append([
                        "role": "tool",
                        "tool_call_id": result.id,
                        "content": result.content
                    ])
                }
            }
        }

        let tools: [[String: Any]] = CoachToolExecutor.tools.map { tool in
            [
                "type": "function",
                "function": [
                    "name": tool.name,
                    "description": tool.description,
                    "parameters": tool.inputSchema
                ]
            ]
        }

        var newMessages: [CoachChatMessage] = []

        for _ in 0..<maxRounds {
            let cfg = AICoachService.kimiConfig
            let body: [String: Any] = [
                "model": cfg.model,
                "temperature": cfg.temperature,
                "tools": tools,
                "messages": apiMessages
            ]

            var request = URLRequest(url: URL(string: "https://api.moonshot.ai/v1/chat/completions")!)
            request.httpMethod = "POST"
            request.timeoutInterval = aiCoachRequestTimeout
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let start = Date()
            aiCoachLogger.info("Kimi chat round start model=\(cfg.model)")
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await URLSession.shared.data(for: request)
            } catch {
                aiCoachLogger.error("Kimi chat transport error after \(Date().timeIntervalSince(start), format: .fixed(precision: 1))s: \(error.localizedDescription)")
                throw error
            }
            let elapsed = Date().timeIntervalSince(start)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                let msg = (json?["error"] as? [String: Any])?["message"] as? String
                    ?? "HTTP \(httpResponse.statusCode)"
                aiCoachLogger.error("Kimi chat HTTP \(httpResponse.statusCode) after \(elapsed, format: .fixed(precision: 1))s: \(msg)")
                throw CoachError.apiError("Kimi API: \(msg)")
            }

            aiCoachLogger.info("Kimi chat round ok in \(elapsed, format: .fixed(precision: 1))s")

            let choices = json?["choices"] as? [[String: Any]] ?? []
            guard let choice = choices.first,
                  let message = choice["message"] as? [String: Any] else {
                throw CoachError.invalidResponse
            }

            let text = message["content"] as? String ?? ""
            let reasoning = message["reasoning_content"] as? String
            var toolCalls: [CoachChatMessage.ToolCall] = []
            if let rawCalls = message["tool_calls"] as? [[String: Any]] {
                for call in rawCalls {
                    guard let id = call["id"] as? String,
                          let fn = call["function"] as? [String: Any],
                          let name = fn["name"] as? String else { continue }
                    let args = fn["arguments"] as? String ?? "{}"
                    toolCalls.append(.init(id: id, name: name, arguments: args))
                }
            }

            newMessages.append(CoachChatMessage(
                role: .assistant,
                text: text,
                toolCalls: toolCalls,
                reasoningContent: reasoning
            ))

            // Echo assistant message back to history for next round
            var assistantDict: [String: Any] = ["role": "assistant"]
            assistantDict["content"] = text.isEmpty ? NSNull() : text
            if let reasoning, !reasoning.isEmpty {
                assistantDict["reasoning_content"] = reasoning
            }
            if !toolCalls.isEmpty {
                assistantDict["tool_calls"] = toolCalls.map { tc in
                    [
                        "id": tc.id,
                        "type": "function",
                        "function": ["name": tc.name, "arguments": tc.arguments]
                    ]
                }
            }
            apiMessages.append(assistantDict)

            if !toolCalls.isEmpty {
                var results: [CoachChatMessage.ToolResult] = []
                for tc in toolCalls {
                    let output = await toolExecutor.execute(name: tc.name, argumentsJSON: tc.arguments)
                    results.append(.init(id: tc.id, name: tc.name, content: output))
                    apiMessages.append([
                        "role": "tool",
                        "tool_call_id": tc.id,
                        "content": output
                    ])
                }
                newMessages.append(CoachChatMessage(role: .tool, toolResults: results))
                continue
            }

            break
        }

        return newMessages
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
