import Foundation

struct MLXChatService {
    enum ServiceError: LocalizedError {
        case invalidBaseURL
        case loopbackAddressOnDevice
        case requestTimedOut(String)
        case generationTimedOut(String, String, Int)
        case cannotReachServer(String)
        case cancelled
        case invalidResponse
        case httpStatus(Int, String)
        case modelNotFound(String)
        case missingAssistantMessage

        var errorDescription: String? {
            switch self {
            case .invalidBaseURL:
                "The local model server address is not a valid URL."
            case .loopbackAddressOnDevice:
                "`127.0.0.1` and `localhost` only work in the iOS Simulator. On a real iPhone, use your Mac's LAN IP, for example `http://192.168.1.23:8080`."
            case .requestTimedOut(let url):
                "The request timed out while connecting to `\(url)`. Make sure the Mac and iPhone are on the same Wi-Fi, the MLX server is running with `--host 0.0.0.0 --port 8080`, and Settings uses the Mac's LAN IP instead of `127.0.0.1`."
            case .generationTimedOut(let url, let modelName, let timeout):
                "The local model server accepted the request but did not finish a chat response from `\(url)` within \(timeout) seconds. Requested model: `\(modelName)`. Check the MLX terminal logs: the model may still be loading, too large for memory, or stuck generating."
            case .cannotReachServer(let url):
                "Could not reach the local model server at `\(url)`. Check that MLX is running, the server was started with `--host 0.0.0.0`, macOS Firewall is not blocking Python, and the app uses your Mac's LAN IP."
            case .cancelled:
                "The chat request was cancelled."
            case .invalidResponse:
                "The local model server returned an invalid response."
            case .httpStatus(let statusCode, let body):
                "The local model server returned HTTP \(statusCode): \(body)"
            case .modelNotFound(let modelName):
                "The local model server could not find `\(modelName)`. Choose a supported model in Settings and restart the MLX server with that same model id."
            case .missingAssistantMessage:
                "The local model server did not return an assistant message."
            }
        }
    }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func chatCompletionsURLDescription(baseURL: String) -> String {
        (try? makeURL(baseURL: baseURL, endpointPath: "/v1/chat/completions").absoluteString) ?? "Invalid server address"
    }

    func testConnection(baseURL: String, modelName: String) async throws -> String {
        let normalizedModelName = ModelSettings.normalizedModelName(modelName)
        let url = try makeURL(baseURL: baseURL, endpointPath: "/v1/models")
        try validateReachableHost(url.host)

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 8

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw serviceError(for: error, url: url)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw error(for: data, statusCode: httpResponse.statusCode, modelName: normalizedModelName)
        }

        if let models = try? JSONDecoder().decode(ModelsResponse.self, from: data),
           !models.data.isEmpty {
            let modelIDs = models.data.map(\.id)
            if modelIDs.contains(normalizedModelName) {
                return "Connected. Server reports model `\(normalizedModelName)`."
            }

            return "Connected, but the server is not serving the selected model. Selected: `\(normalizedModelName)`. Server models: \(modelIDs.joined(separator: ", "))."
        }

        return "Connected to the local model server."
    }

    func testChatCompletion(baseURL: String, modelName: String) async throws -> String {
        let answer = try await send(
            question: "Reply with only the word OK.",
            systemPrompt: "You are a local server health check. Reply with only OK.",
            baseURL: baseURL,
            modelName: modelName,
            maxTokens: 2,
            timeoutInterval: 120,
            performsPreflight: true
        )

        return "Chat endpoint responded: \(answer)"
    }

    func send(
        question: String,
        systemPrompt: String,
        history: [ChatMessage] = [],
        baseURL: String,
        modelName: String,
        maxTokens: Int = 400,
        timeoutInterval: TimeInterval = 120,
        performsPreflight: Bool = true
    ) async throws -> String {
        let normalizedModelName = ModelSettings.normalizedModelName(modelName)
        if performsPreflight {
            _ = try await testConnection(baseURL: baseURL, modelName: normalizedModelName)
        }

        let url = try makeURL(baseURL: baseURL, endpointPath: "/v1/chat/completions")

        var apiMessages: [ChatCompletionMessage] = [.init(role: .system, content: systemPrompt)]
        apiMessages += history.suffix(6).map { ChatCompletionMessage(role: $0.role, content: $0.content) }
        apiMessages.append(.init(role: .user, content: question))

        let requestBody = ChatCompletionRequest(
            model: normalizedModelName,
            messages: apiMessages,
            temperature: 0.5,
            maxTokens: maxTokens,
            stream: false
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(requestBody)
        request.timeoutInterval = timeoutInterval

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw serviceError(
                for: error,
                url: url,
                modelName: normalizedModelName,
                timeoutInterval: timeoutInterval,
                timedOutAfterResponseStarted: error.code == .timedOut
            )
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw error(for: data, statusCode: httpResponse.statusCode, modelName: normalizedModelName)
        }

        let completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let answer = completion.choices.first?.message.content, !answer.isEmpty else {
            throw ServiceError.missingAssistantMessage
        }

        return answer
    }

    private func makeURL(baseURL: String, endpointPath: String) throws -> URL {
        guard var components = URLComponents(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw ServiceError.invalidBaseURL
        }

        let basePath = components.path.trimmingTrailingSlash()
        let endpoint = endpointPath.hasPrefix("/") ? endpointPath : "/" + endpointPath

        if endpoint.hasPrefix("/v1"), basePath.hasSuffix("/v1") {
            components.path = basePath + endpoint.dropFirst(3)
        } else {
            components.path = basePath + endpoint
        }

        guard let url = components.url else {
            throw ServiceError.invalidBaseURL
        }

        return url
    }

    private func validateReachableHost(_ host: String?) throws {
        guard let host else { return }

        #if targetEnvironment(simulator)
        return
        #else
        if host == "127.0.0.1" || host.localizedCaseInsensitiveCompare("localhost") == .orderedSame {
            throw ServiceError.loopbackAddressOnDevice
        }
        #endif
    }

    private func serviceError(
        for error: URLError,
        url: URL,
        modelName: String? = nil,
        timeoutInterval: TimeInterval? = nil,
        timedOutAfterResponseStarted: Bool = false
    ) -> ServiceError {
        switch error.code {
        case .timedOut:
            if timedOutAfterResponseStarted {
                return .generationTimedOut(
                    url.absoluteString,
                    modelName ?? "Unknown",
                    Int(timeoutInterval ?? 0)
                )
            }

            return .requestTimedOut(url.absoluteString)
        case .cancelled:
            return .cancelled
        case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .notConnectedToInternet:
            return .cannotReachServer(url.absoluteString)
        default:
            return .httpStatus(error.errorCode, error.localizedDescription)
        }
    }

    private func error(for data: Data, statusCode: Int, modelName: String) -> ServiceError {
        let message = Self.serverErrorMessage(from: data)

        if statusCode == 404,
           message.localizedCaseInsensitiveContains("Repository Not Found") ||
            message.localizedCaseInsensitiveContains("repo_id") {
            return .modelNotFound(modelName)
        }

        return .httpStatus(statusCode, message)
    }

    private static func serverErrorMessage(from data: Data) -> String {
        if let errorResponse = try? JSONDecoder().decode(ServerErrorResponse.self, from: data) {
            return errorResponse.message
        }

        return String(data: data, encoding: .utf8) ?? "No response body"
    }
}

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [ChatCompletionMessage]
    let temperature: Double
    let maxTokens: Int
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
        case stream
    }
}

private struct ChatCompletionMessage: Codable {
    let role: ChatMessage.Role
    let content: String
}

private struct ChatCompletionResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: ChatCompletionMessage
    }
}

private struct ModelsResponse: Decodable {
    let data: [Model]

    struct Model: Decodable {
        let id: String
    }
}

private struct ServerErrorResponse: Decodable {
    let message: String

    enum CodingKeys: String, CodingKey {
        case error
        case message
        case detail
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let error = try? container.decode(FlexibleError.self, forKey: .error) {
            message = error.message
        } else if let message = try? container.decode(String.self, forKey: .message) {
            self.message = message
        } else if let detail = try? container.decode(String.self, forKey: .detail) {
            message = detail
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "No known server error field was present."
                )
            )
        }
    }
}

private enum FlexibleError: Decodable {
    case string(String)
    case object(String)

    var message: String {
        switch self {
        case .string(let message):
            message
        case .object(let message):
            message
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let message = try? container.decode(String.self) {
            self = .string(message)
            return
        }

        let object = try container.decode(ErrorObject.self)
        self = .object(object.message ?? object.code ?? "The local model server returned an error.")
    }

    private struct ErrorObject: Decodable {
        let message: String?
        let code: String?
    }
}

private extension String {
    func trimmingTrailingSlash() -> String {
        var value = self
        while value.last == "/" {
            value.removeLast()
        }
        return value
    }
}
