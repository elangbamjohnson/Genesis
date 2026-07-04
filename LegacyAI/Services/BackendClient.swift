import Foundation

struct BackendClient {
    enum ClientError: LocalizedError {
        case invalidBaseURL
        case loopbackAddressOnDevice
        case requestTimedOut(String)
        case cannotReachServer(String)
        case httpStatus(Int, String)
        case invalidResponse
        case serializationError(String)

        var errorDescription: String? {
            switch self {
            case .invalidBaseURL:
                return "The backend server address is not a valid URL."
            case .loopbackAddressOnDevice:
                return "`127.0.0.1` and `localhost` only work in the iOS Simulator. On a real iPhone, use your Mac's LAN IP, for example `http://192.168.1.23:8090`."
            case .requestTimedOut(let url):
                return "The request timed out while connecting to `\(url)`. Make sure the Mac and iPhone are on the same Wi-Fi, the backend is running, and Settings uses the Mac's LAN IP instead of `127.0.0.1`."
            case .cannotReachServer(let url):
                return "Could not reach the backend server at `\(url)`. Check that the backend is running and you use your Mac's LAN IP."
            case .httpStatus(let statusCode, let body):
                return "The backend server returned HTTP \(statusCode): \(body)"
            case .invalidResponse:
                return "The backend server returned an invalid response."
            case .serializationError(let details):
                return "Serialization error: \(details)"
            }
        }
    }

    struct ImportResult: Decodable {
        let imported: Int
        let skipped: Int
        let failed: Int
    }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // Helper decoder with robust date parsing
    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder -> Date in
            let container = try decoder.singleValueContainer()
            let dateStr = try container.decode(String.self)
            
            // Try standard ISO8601
            let isoFormatter = ISO8601DateFormatter()
            if let date = isoFormatter.date(from: dateStr) {
                return date
            }
            
            // Try ISO8601 without Z or offset (standard naive timestamp from FastAPI/Python)
            let naiveFormatter = DateFormatter()
            naiveFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            naiveFormatter.timeZone = TimeZone(secondsFromGMT: 0)
            if let date = naiveFormatter.date(from: dateStr) {
                return date
            }
            
            // Try with fractional seconds
            naiveFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
            if let date = naiveFormatter.date(from: dateStr) {
                return date
            }
            
            // Fallback try with fractional seconds + Z
            naiveFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'"
            if let date = naiveFormatter.date(from: dateStr) {
                return date
            }

            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date format: \(dateStr)")
        }
        return decoder
    }

    // Helper encoder
    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    func checkHealth(baseURL: String) async throws -> Bool {
        let url = try makeURL(baseURL: baseURL, endpointPath: "/health")
        try validateReachableHost(url.host)

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5

        do {
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(httpResponse.statusCode)
        } catch {
            return false
        }
    }

    func fetchMemories(baseURL: String) async throws -> [LifeEntry] {
        let url = try makeURL(baseURL: baseURL, endpointPath: "/v1/memories")
        try validateReachableHost(url.host)

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw clientError(for: error, url: url)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ClientError.httpStatus(httpResponse.statusCode, body)
        }

        do {
            let backendMemories = try makeDecoder().decode([BackendMemory].self, from: data)
            return backendMemories.compactMap { $0.toLifeEntry() }
        } catch {
            throw ClientError.serializationError(error.localizedDescription)
        }
    }

    func createMemory(_ entry: LifeEntry, baseURL: String) async throws -> LifeEntry {
        let url = try makeURL(baseURL: baseURL, endpointPath: "/v1/memories")
        try validateReachableHost(url.host)

        let backendMemory = BackendMemory(entry)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10
        request.httpBody = try makeEncoder().encode(backendMemory)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw clientError(for: error, url: url)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ClientError.httpStatus(httpResponse.statusCode, body)
        }

        do {
            let created = try makeDecoder().decode(BackendMemory.self, from: data)
            guard let entry = created.toLifeEntry() else {
                throw ClientError.invalidResponse
            }
            return entry
        } catch {
            throw ClientError.serializationError(error.localizedDescription)
        }
    }

    func deleteMemory(id: UUID, baseURL: String) async throws {
        let url = try makeURL(baseURL: baseURL, endpointPath: "/v1/memories/\(id.uuidString.upper())")
        try validateReachableHost(url.host)

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.timeoutInterval = 10

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw clientError(for: error, url: url)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ClientError.httpStatus(httpResponse.statusCode, body)
        }
    }

    func importEntries(_ entries: [LifeEntry], baseURL: String, overwrite: Bool) async throws -> ImportResult {
        let url = try makeURL(baseURL: baseURL, endpointPath: "/v1/memories/import?overwrite=\(overwrite)")
        try validateReachableHost(url.host)

        let payload = entries.map { BackendMemory($0) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30
        request.httpBody = try makeEncoder().encode(payload)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw clientError(for: error, url: url)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ClientError.httpStatus(httpResponse.statusCode, body)
        }

        do {
            return try makeDecoder().decode(ImportResult.self, from: data)
        } catch {
            throw ClientError.serializationError(error.localizedDescription)
        }
    }

    // MARK: - Private Helpers

    private func makeURL(baseURL: String, endpointPath: String) throws -> URL {
        guard var components = URLComponents(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw ClientError.invalidBaseURL
        }

        let basePath = components.path.trimmingTrailingSlash()
        let endpoint = endpointPath.hasPrefix("/") ? endpointPath : "/" + endpointPath

        if endpoint.hasPrefix("/v1"), basePath.hasSuffix("/v1") {
            components.path = basePath + endpoint.dropFirst(3)
        } else {
            components.path = basePath + endpoint
        }

        guard let url = components.url else {
            throw ClientError.invalidBaseURL
        }

        return url
    }

    private func validateReachableHost(_ host: String?) throws {
        guard let host else { return }

        #if targetEnvironment(simulator)
        return
        #else
        if host == "127.0.0.1" || host.localizedCaseInsensitiveCompare("localhost") == .orderedSame {
            throw ClientError.loopbackAddressOnDevice
        }
        #endif
    }

    private func clientError(for error: URLError, url: URL) -> ClientError {
        switch error.code {
        case .timedOut:
            return .requestTimedOut(url.absoluteString)
        case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .notConnectedToInternet:
            return .cannotReachServer(url.absoluteString)
        default:
            return .httpStatus(error.errorCode, error.localizedDescription)
        }
    }
}

// Codable representation of back-end memory representation
private struct BackendMemory: Codable {
    let id: String
    let title: String
    let content: String
    let category: String
    let date: Date
    let tags: [String]

    init(_ entry: LifeEntry) {
        self.id = entry.id.uuidString.upper()
        self.title = entry.title
        self.content = entry.content
        self.category = entry.category.rawValue
        self.date = entry.date
        self.tags = entry.tags
    }

    func toLifeEntry() -> LifeEntry? {
        guard let uuid = UUID(uuidString: id),
              let entryCategory = LifeEntry.Category(rawValue: category) else {
            return nil
        }
        return LifeEntry(
            id: uuid,
            title: title,
            content: content,
            category: entryCategory,
            tags: tags,
            date: date
        )
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
    
    func upper() -> String {
        return self.uppercased()
    }
}
