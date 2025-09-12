import Foundation

/// A network interceptor that provides retry configuration for failed requests.
///
/// `RetryInterceptor` examines HTTP response status codes and determines if a request
/// should be retried. It implements exponential backoff for retry delays.
///
/// The interceptor tracks retry attempts using request headers and implements
/// exponential backoff for retry delays.
///
/// - Note: This interceptor focuses on server errors (5xx) and specific client errors.
/// - Important: The actual retry mechanism is implemented in the network client.
public struct RetryInterceptor: NetworkInterceptorProtocol {
    public let maxRetries: Int
    private let retryableStatusCodes: Set<Int>
    private let baseDelay: TimeInterval
    private let maxDelay: TimeInterval
    
    private static let retryCountHeaderKey = "X-Retry-Count"
    
    public init(
        maxRetries: Int = 3,
        retryableStatusCodes: Set<Int> = [500, 502, 503, 504],
        baseDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 30.0
    ) {
        self.maxRetries = maxRetries
        self.retryableStatusCodes = retryableStatusCodes
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
    }

    public func intercept(request: URLRequest) -> URLRequest {
        return request
    }

    public func intercept(response: URLResponse?, data: Data?) -> (URLResponse?, Data?) {
        return (response, data)
    }

    public func interceptAsync(request: URLRequest) async throws -> URLRequest {
        var modifiedRequest = request
        
        // Get current retry count
        let currentCount = getCurrentRetryCount(from: request)
        
        // Check if we've exceeded max retries
        if currentCount > maxRetries {
            throw APIClientError.serverMessage(
                message: "Maximum retry attempts (\(maxRetries)) exceeded",
                statusCode: 503
            )
        }
        
        // If this is a retry (count > 0), apply exponential backoff delay
        if currentCount > 0 {
            let delay = retryDelay(for: currentCount)
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        
        // Set/update the retry count header
        modifiedRequest.setValue("\(currentCount)", forHTTPHeaderField: Self.retryCountHeaderKey)
        
        return modifiedRequest
    }

    public func interceptAsync(response: URLResponse?, data: Data?) async throws -> (URLResponse?, Data?) {
        return (response, data)
    }
    
    /// Gets the current retry count from the request, incrementing it for the next attempt
    private func getCurrentRetryCount(from request: URLRequest) -> Int {
        if let countString = request.value(forHTTPHeaderField: Self.retryCountHeaderKey),
           let currentCount = Int(countString) {
            return currentCount + 1 // Increment for this retry attempt
        }
        return 0 // First attempt
    }

    /// Determines if a response indicates the request should be retried
    public func shouldRetry(response: URLResponse?) -> Bool {
        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }
        return retryableStatusCodes.contains(httpResponse.statusCode)
    }
    
    /// Determines if we can retry based on the current attempt count
    public func canRetry(request: URLRequest) -> Bool {
        let currentCount = getCurrentRetryCount(from: request)
        return currentCount <= maxRetries
    }

    /// Calculates delay for the given retry attempt using exponential backoff
    public func retryDelay(for attempt: Int) -> TimeInterval {
        let delay = baseDelay * pow(2.0, Double(attempt))
        return min(delay, maxDelay)
    }
}
