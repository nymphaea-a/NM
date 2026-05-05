import Foundation

// MARK: - 数据模型

struct ChatResponse: Codable, Sendable {
    let choices: [Choice]
    let usage: TokenUsage?
}

struct Choice: Codable, Sendable {
    let message: MessageContent
}

struct MessageContent: Codable, Sendable {
    let content: String
}

struct StreamDelta: Codable, Sendable {
    let reasoning_content: String?
    let content: String?
}

struct StreamChoice: Codable, Sendable {
    let delta: StreamDelta?
}

struct TokenUsage: Codable, Sendable {
    let prompt_tokens: Int
    let completion_tokens: Int
    let total_tokens: Int
}

struct StreamResponse: Codable, Sendable {
    let choices: [StreamChoice]
    let usage: TokenUsage?
}

// MARK: - API 服务

struct APIService {

    // 通用非流式调用
    static func callAI(
        config: any AIConfigProtocol,
        messages: [[String: String]],
        enableThinking: Bool = true,
        completion: @escaping @Sendable (Result<(String, TokenUsage?), Error>) -> Void
    ) {

        guard let url = URL(string: "\(config.baseURL)/chat/completions") else {
            completion(.failure(NSError(domain: "APIService", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "无效的 URL"])))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120

        var body: [String: Any] = [
            "model": config.model,
            "messages": messages,
            "stream": false
        ]
        if !enableThinking {
            body["enable_thinking"] = false
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(error))
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                completion(.failure(NSError(domain: "APIService",
                    code: httpResponse.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "HTTP 状态码: \(httpResponse.statusCode)"])))
                return
            }

            guard let data = data else {
                completion(.failure(NSError(domain: "APIService", code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "响应数据为空"])))
                return
            }

            do {
                let (content, usage) = try Self.decodeResponse(from: data)
                completion(.success((content, usage)))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    // 非隔离的解码辅助方法
    nonisolated private static func decodeResponse(from data: Data) throws -> (String, TokenUsage?) {
        let decoder = JSONDecoder()
        let response = try decoder.decode(ChatResponse.self, from: data)
        guard let content = response.choices.first?.message.content else {
            throw NSError(domain: "APIService", code: -3,
                        userInfo: [NSLocalizedDescriptionKey: "响应中无 choices 数据"])
        }
        return (content, response.usage)
    }

    // 通用流式调用（使用闲置超时：持续30秒无新token才判定超时）
    static func callAIStream(
        config: any AIConfigProtocol,
        messages: [[String: String]],
        enableThinking: Bool = true,
        onToken: @escaping @Sendable (String, Bool) -> Void,
        onComplete: @escaping @Sendable (Result<TokenUsage?, Error>) -> Void
    ) {

        guard let url = URL(string: "\(config.baseURL)/chat/completions") else {
            onComplete(.failure(NSError(domain: "APIService", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "无效的 URL"])))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        // 不设置固定超时，由闲置超时逻辑接管
        request.timeoutInterval = 1800

        var body: [String: Any] = [
            "model": config.model,
            "messages": messages,
            "stream": true,
            "stream_options": ["include_usage": true]
        ]
        if !enableThinking {
            body["enable_thinking"] = false
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            onComplete(.failure(error))
            return
        }

        Task {
            let lock = NSLock()
            var isTimedOut = false
            var isCompleted = false
            let idleTimeout: TimeInterval = 30

            func markTimedOut() {
                lock.lock()
                isTimedOut = true
                lock.unlock()
            }

            func checkTimedOut() -> Bool {
                lock.lock()
                defer { lock.unlock() }
                return isTimedOut
            }

            func markCompleted() -> Bool {
                lock.lock()
                defer { lock.unlock() }
                if isCompleted { return false }
                isCompleted = true
                return true
            }

            var timeoutTask: Task<Void, Never>?
            func resetTimeout() {
                timeoutTask?.cancel()
                timeoutTask = Task {
                    try? await Task.sleep(nanoseconds: UInt64(idleTimeout * 1_000_000_000))
                    guard !Task.isCancelled else { return }
                    markTimedOut()
                    if markCompleted() {
                        onComplete(.failure(NSError(domain: "APIService", code: -2,
                            userInfo: [NSLocalizedDescriptionKey: "闲置超时：\(Int(idleTimeout))秒未收到新 token"])))
                    }
                }
            }

            resetTimeout()

            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: request)

                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    timeoutTask?.cancel()
                    let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                    if markCompleted() {
                        onComplete(.failure(NSError(domain: "APIService", code: code,
                            userInfo: [NSLocalizedDescriptionKey: "HTTP 状态码: \(code)"])))
                    }
                    return
                }

                var cachedUsage: TokenUsage?

                for try await line in bytes.lines {
                    if checkTimedOut() { break }
                    resetTimeout()

                    guard line.hasPrefix("data: ") else { continue }
                    let jsonStr = String(line.dropFirst(6))

                    guard let jsonData = jsonStr.data(using: .utf8) else { continue }

                    if jsonStr == "[DONE]" {
                        timeoutTask?.cancel()
                        if markCompleted() {
                            onComplete(.success(cachedUsage))
                        }
                        return
                    }

                    let streamResponse = try JSONDecoder().decode(StreamResponse.self, from: jsonData)

                    if let usage = streamResponse.usage {
                        cachedUsage = usage
                        continue
                    }

                    if let delta = streamResponse.choices.first?.delta {
                        if let reasoning = delta.reasoning_content, !reasoning.isEmpty {
                            await MainActor.run {
                                onToken(reasoning, true)
                            }
                        }
                        if let content = delta.content, !content.isEmpty {
                            await MainActor.run {
                                onToken(content, false)
                            }
                        }
                    }
                }

                timeoutTask?.cancel()
                if !checkTimedOut() {
                    if markCompleted() {
                        onComplete(.success(cachedUsage))
                    }
                }
            } catch {
                timeoutTask?.cancel()
                if markCompleted() {
                    onComplete(.failure(error))
                }
            }
        }
    }
}
