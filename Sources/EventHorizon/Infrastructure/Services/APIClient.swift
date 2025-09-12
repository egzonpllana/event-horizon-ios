import Foundation

public final class APIClient: APIClientProtocol {

    // MARK: - Properties -

    public let session: (any NetworkSessionProtocol)
    public let interceptors: [any NetworkInterceptorProtocol]
    private let taskManager: (any APIClientTaskManagerProtocol)
    private let logger: (any EHLoggerProtocol)

    // MARK: - Initialization -

    public init(
        session: NetworkSessionProtocol = NetworkSession(timeout: 10),
        interceptors: [any NetworkInterceptorProtocol] = [],
        taskManager: APIClientTaskManagerProtocol = APIClientTaskManager.shared,
        logger: EHLoggerProtocol = DefaultEHLogger()
    ) {
        self.session = session
        self.interceptors = interceptors
        self.taskManager = taskManager
        self.taskManager.configure(logger: logger)
        self.logger = logger
    }

    // MARK: - Methods -

    public func request<T: Decodable & Sendable>(
        _ endpoint: any APIEndpointProtocol,
        decoder: JSONDecoder = JSONDecoder(),
        id: String
    ) async throws -> T {
        guard let request = endpoint.urlRequest else {
            throw APIClientError.invalidURL
        }

        return try await executeRequest(id: id) {
            let data = try await self.performRequest(request)
            do {
                return try decoder.decode(T.self, from: data)
            } catch let decodingError as DecodingError {
                self.logDecodingFailure(error: decodingError, data: data, endpoint: endpoint)
                throw APIClientError.requestFailed(decodingError)
            }
        }
    }

    public func request(
        _ endpoint: any APIEndpointProtocol,
        id: String
    ) async throws {
        guard let request = endpoint.urlRequest else {
            throw APIClientError.invalidURL
        }

        _ = try await executeRequest(id: id) {
            try await self.performRequest(request)
        }
    }

    @discardableResult
    public func request(
        _ endpoint: any APIEndpointProtocol,
        progressDelegate: (any UploadProgressDelegateProtocol)? = nil,
        id: String
    ) async throws -> Data? {
        guard let request = endpoint.urlRequest else {
            throw APIClientError.urlRequestIsEmpty
        }

        return try await executeRequest(id: id) {
            try await self.performRequest(request, progressDelegate: progressDelegate)
        }
    }

    public func cancelRequest(with id: String) {
        log(APIClientLogMessages.cancellingRequest(id: id))
        taskManager.cancelTask(for: id)
    }

    public func cancelAllRequests() {
        log(APIClientLogMessages.cancellingAllRequests)
        taskManager.cancelAllTasks()
    }
}

// MARK: - Internal Helpers -
private extension APIClient {
    func executeRequest<T>(
        id: String,
        taskBlock: @escaping () async throws -> T
    ) async throws -> T {
        // Only log essential task lifecycle events
        switch taskManager.getTaskStatus(for: id) {
            case .finished:
                logError(APIClientLogMessages.taskAlreadyFinished(id: id))
                throw APIClientError.taskFinished
            case .canceled:
                logError(APIClientLogMessages.taskCanceled(id: id))
                throw APIClientError.taskCanceled
            case .inProgress, .queued:
                logError(APIClientLogMessages.taskInProgress(id: id))
                throw APIClientError.taskInProgress
            default:
                break
        }

        let task = Task { try await taskBlock() }
        taskManager.addTask(task, for: id)

        defer {
            taskManager.setTaskStatus(for: id, status: .finished)
        }

        do {
            let result = try await task.value
            return result
        } catch {
            logError(APIClientLogMessages.taskFailed(id: id, error: error))
            throw error
        }
    }
}

// MARK: - Perform Request helpers -
private extension APIClient {

    @discardableResult
    func performRequest(
        _ request: URLRequest,
        progressDelegate: (any UploadProgressDelegateProtocol)? = nil,
    ) async throws -> Data {
        // Request Interception
        var mutableRequest = try await interceptRequest(request)

        // Resolve Session
        let sessionToUse = resolveSession(progressDelegate: progressDelegate)

        // Get retry configuration from interceptors
        let retryInterceptor = interceptors.first { $0 is RetryInterceptor } as? RetryInterceptor
        let maxRetries = retryInterceptor?.maxRetries ?? 0
        var attemptCount = 0
        var lastError: Error?

        while attemptCount <= maxRetries {
            do {
                logRequest(mutableRequest)
                let (data, response) = try await sessionToUse.data(for: mutableRequest)

                // Token Refresh
                if let retried = try await handleTokenRefreshing(
                    request: request,
                    progressDelegate: progressDelegate,
                    response: response,
                    data: data
                ) {
                    return retried
                }

                // Response Interception
                let (finalData, finalResponse) = try await handleResponseInterceptors(
                    data: data,
                    response: response
                )
                logResponse(data: finalData, response: finalResponse)

                // Check if we should retry based on response status
                if let retryInterceptor = retryInterceptor,
                   retryInterceptor.shouldRetry(response: finalResponse),
                   attemptCount < maxRetries {
                    attemptCount += 1
                    let delay = retryInterceptor.retryDelay(for: attemptCount)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    
                    // Update retry count in request for next attempt
                    mutableRequest = try await interceptRequest(request)
                    continue
                }

                // Response Validation
                try validateResponse(finalResponse, finalData)
                return finalData
            } catch {
                lastError = error
                
                // Check if we should retry based on error type
                if let retryInterceptor = retryInterceptor,
                   attemptCount < maxRetries,
                   shouldRetryError(error) {
                    attemptCount += 1
                    let delay = retryInterceptor.retryDelay(for: attemptCount)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    
                    // Update retry count in request for next attempt
                    mutableRequest = try await interceptRequest(request)
                    continue
                }
                
                throw handleError(error, request: request)
            }
        }
        
        // If we get here, all retries were exhausted
        throw lastError ?? APIClientError.requestFailed(NSError(domain: "APIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Max retries exceeded"]))
    }
    
    private func shouldRetryError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            return [
                .timedOut,
                .networkConnectionLost,
                .notConnectedToInternet,
                .cannotConnectToHost,
                .cannotFindHost
            ].contains(urlError.code)
        }
        
        if let apiError = error as? APIClientError {
            switch apiError {
            case .timeout, .networkError:
                return true
            default:
                return false
            }
        }
        
        return false
    }

    func interceptRequest(_ request: URLRequest) async throws -> URLRequest {
        var modified = request
        for interceptor in interceptors {
            modified = try await interceptor.interceptAsync(request: modified)
        }
        return modified
    }

    func resolveSession(progressDelegate: (any UploadProgressDelegateProtocol)?) -> NetworkSessionProtocol {
        if let progressDelegate {
            return NetworkSession(timeout: 30, delegate: progressDelegate)
        } else {
            return session
        }
    }

    func handleTokenRefreshing(
        request: URLRequest,
        progressDelegate: (any UploadProgressDelegateProtocol)? = nil,
        response: URLResponse,
        data: Data
    ) async throws -> Data? {

        for interceptor in interceptors {
            guard let refreshable = interceptor as? TokenRefreshingInterceptorProtocol else { continue }

            let (action, newResponse, newData) = await refreshable.interceptAsync(
                response: response,
                data: data
            )

            if action == .retryWithUpdatedToken {
                return try await performRequest(
                    request,
                    progressDelegate: progressDelegate,
                )
            }
        }

        return nil
    }

    func handleResponseInterceptors(
        data: Data,
        response: URLResponse
    ) async throws -> (Data, URLResponse) {
        var modifiedData = data
        var modifiedResponse = response

        for interceptor in interceptors where !(interceptor is TokenRefreshingInterceptorProtocol) {
            let (newResponse, newData) = try await interceptor.interceptAsync(
                response: modifiedResponse,
                data: modifiedData
            )
            modifiedResponse = newResponse ?? modifiedResponse
            modifiedData = newData ?? modifiedData
        }

        return (modifiedData, modifiedResponse)
    }

    func validateResponse(_ response: URLResponse, _ data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse(data)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let message = try? extractErrorMessage(from: data) {
                throw APIClientError.serverMessage(message: message, statusCode: httpResponse.statusCode)
            } else {
                logError(APIClientLogMessages.failedToParseErrorBody(statusCode: httpResponse.statusCode))
                logError(APIClientLogMessages.rawErrorBody(data: data))
                throw APIClientError.statusCode(httpResponse.statusCode)
            }
        }
    }

    func handleError(_ error: Error, request: URLRequest) -> Error {
        let url = request.url?.absoluteString ?? "unknown"
        
        if let urlError = error as? URLError {
            logError(APIClientLogMessages.networkError(error: urlError, url: url))
            switch urlError.code {
                case .timedOut:
                    return APIClientError.timeout
                default:
                    return APIClientError.networkError(urlError)
            }
        } else if let apiError = error as? APIClientError {
            switch apiError {
                case .serverMessage(let message, let statusCode):
                    logError(APIClientLogMessages.serverError(statusCode: statusCode, message: message, url: url))
                default:
                    logError(APIClientLogMessages.apiError(error: apiError, url: url))
            }
            return apiError
        } else {
            logError(APIClientLogMessages.unknownError(error: error, url: url))
            return APIClientError.requestFailed(error)
        }
    }

    func extractErrorMessage(from data: Data) throws -> String? {
        struct ErrorResponse: Decodable {
            let error: String?
        }

        let decoded = try JSONDecoder().decode(ErrorResponse.self, from: data)
        return decoded.error ?? decoded.error
    }
}

// MARK: - Log extension -
private extension APIClient {
    func log(_ message: String) {
        logger.log(message: message, type: .debug)
    }

    func logError(_ message: String) {
        logger.log(message: message, type: .error)
    }

    func logDecodingFailure(
        error: DecodingError,
        data: Data,
        endpoint: any APIEndpointProtocol
    ) {
        let rawResponse = String(data: data, encoding: .utf8) ?? "N/A"

        // Attempt to decode the "message" field if it exists
        let serverMessage: String? = {
            struct ErrorMessageResponse: Decodable {
                let message: String
            }

            return (try? JSONDecoder().decode(ErrorMessageResponse.self, from: data))?.message
        }()

        logError(APIClientLogMessages.decodingFailed(endpoint: endpoint))
        logError(APIClientLogMessages.rawResponse(response: rawResponse))

        if let message = serverMessage {
            logError(APIClientLogMessages.serverMessage(message: message))
        }

        logError(APIClientLogMessages.decodingError(error: error))
    }

    func logRequest(_ request: URLRequest) {
        guard let url = request.url else { return }
        
        log(APIClientLogMessages.logRequestSeparator)

        // Main request line
        log(APIClientLogMessages.requestMethod(method: request.httpMethod ?? "UNKNOWN", url: url.absoluteString))
        
        // Parameters (from URL query)
        if let query = url.query, !query.isEmpty {
            log(APIClientLogMessages.requestParameters(query: query))
        } else {
            log(APIClientLogMessages.requestParametersNone)
        }
        
        // Body
        if let body = request.httpBody {
            if let bodyString = String(data: body, encoding: .utf8), !bodyString.isEmpty {
                log(APIClientLogMessages.requestBody(body: bodyString))
            } else if body.count > 0 {
                log(APIClientLogMessages.requestBodyBinary(size: body.count))
            } else {
                log(APIClientLogMessages.requestBodyEmpty)
            }
        } else {
            log(APIClientLogMessages.requestBodyNone)
        }
        
        // Headers
        if let headers = request.allHTTPHeaderFields, !headers.isEmpty {
            log(APIClientLogMessages.requestHeaders)
            headers.sorted(by: { $0.key < $1.key }).forEach { key, value in
                // Mask sensitive headers for security
                if key.lowercased() == "authorization" {
                    let maskedValue = value.prefix(20) + "..."
                    log(APIClientLogMessages.requestHeaderMasked(key: key, value: String(maskedValue)))
                } else {
                    log(APIClientLogMessages.requestHeader(key: key, value: value))
                }
            }
        } else {
            log(APIClientLogMessages.requestHeadersNone)
        }
        
        log(APIClientLogMessages.endOfLogRequestSeparator)
    }

    func logResponse(data: Data, response: URLResponse) {
        log(APIClientLogMessages.logResponseSeparator)

        if let httpResponse = response as? HTTPURLResponse {
            let statusIcon = httpResponse.statusCode >= 400 ? "❌" : "✅"  
            log(APIClientLogMessages.responseStatus(icon: statusIcon, statusCode: httpResponse.statusCode, url: httpResponse.url?.absoluteString ?? "unknown"))
            
            // Only show relevant headers (compact format)
            let relevantHeaders = ["Content-Type", "Content-Length"]
            let filteredHeaders = httpResponse.allHeaderFields.compactMap { key, value -> String? in
                guard let keyString = key as? String,
                      relevantHeaders.contains(keyString) else { return nil }
                return "\(keyString): \(value)"
            }
            
            if !filteredHeaders.isEmpty {
                log(APIClientLogMessages.responseHeaders(headers: filteredHeaders.joined(separator: " | ")))
            }
            
            // Body (compact)
            if let string = String(data: data, encoding: .utf8), !string.isEmpty {
                log(APIClientLogMessages.responseBody(body: string))
            } else if data.count > 0 {
                log(APIClientLogMessages.responseBodyBinary(size: data.count))
            } else {
                log(APIClientLogMessages.responseBodyEmpty)
            }
        }
        
        log(APIClientLogMessages.endOfLogResponseSeparator)
    }
}

private enum APIClientLogMessages {
    // Currently used messages
    static func cancellingRequest(id: String) -> String { "Cancelling request with id: \(id)" }
    static let cancellingAllRequests = "Cancelling all requests"
    
    // Task management messages
    static func taskAlreadyFinished(id: String) -> String { "🚨 Task already finished: \(id)" }
    static func taskCanceled(id: String) -> String { "🚨 Task canceled: \(id)" }
    static func taskInProgress(id: String) -> String { "🚨 Task in progress: \(id)" }
    static func taskFailed(id: String, error: Error) -> String { "🚨 Task failed (\(id)): \(error)" }
    
    // Error handling messages
    static func failedToParseErrorBody(statusCode: Int) -> String { "Failed to parse error body from status code \(statusCode)" }
    static func rawErrorBody(data: Data) -> String { "Raw error body: \(String(data: data, encoding: .utf8) ?? "N/A")" }
    static func networkError(error: URLError, url: String) -> String { "🚨 Network Error: \(error.localizedDescription) | URL: \(url)" }
    static func serverError(statusCode: Int, message: String, url: String) -> String { "🚨 Server Error (\(statusCode)): \(message) | URL: \(url)" }
    static func apiError(error: APIClientError, url: String) -> String { "🚨 API Error: \(error) | URL: \(url)" }
    static func unknownError(error: Error, url: String) -> String { "🚨 Unknown Error: \(error) | URL: \(url)" }
    
    // Decoding messages
    static func decodingFailed(endpoint: any APIEndpointProtocol) -> String { "❌ Failed to decode response from endpoint: \(endpoint)" }
    static func rawResponse(response: String) -> String { "📦 Raw response: \(response)" }
    static func serverMessage(message: String) -> String { "📨 Server message: \(message)" }
    static func decodingError(error: DecodingError) -> String { "🧨 Decoding error: \(error)" }
    
    // Request logging messages
    static let logRequestSeparator = "───Log Request──────"
    static func requestMethod(method: String, url: String) -> String { "🚀 \(method): \(url)" }
    static func requestParameters(query: String) -> String { "📋 Parameters: \(query)" }
    static let requestParametersNone = "📋 Parameters: (none)"
    static func requestBody(body: String) -> String { "📦 Body: \(body)" }
    static func requestBodyBinary(size: Int) -> String { "📦 Body: \(size) bytes (binary/non-UTF8)" }
    static let requestBodyEmpty = "📦 Body: (empty)"
    static let requestBodyNone = "📦 Body: (none)"
    static let requestHeaders = "🔑 Headers:"
    static func requestHeader(key: String, value: String) -> String { "   \(key): \(value)" }
    static func requestHeaderMasked(key: String, value: String) -> String { "   \(key): \(value)" }
    static let requestHeadersNone = "🔑 Headers: (none)"
    static let endOfLogRequestSeparator = "───End of Log Request──────"

    // Response logging messages
    static let logResponseSeparator = "───Log Response──────"
    static func responseStatus(icon: String, statusCode: Int, url: String) -> String { "\(icon) Response: \(statusCode) | \(url)" }
    static func responseHeaders(headers: String) -> String { "📋 Headers: \(headers)" }
    static func responseBody(body: String) -> String { "📦 Body: \(body)" }
    static func responseBodyBinary(size: Int) -> String { "📦 Body: \(size) bytes (binary)" }
    static let responseBodyEmpty = "📦 Body: (empty)"
    static let endOfLogResponseSeparator = "───End of Log Response──────"
}
