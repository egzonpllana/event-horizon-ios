import Foundation

/// A network interceptor that sets a custom timeout interval for outgoing requests.
///
/// `RequestTimeoutInterceptor` modifies the timeout interval of network requests, ensuring that
/// requests do not hang indefinitely. This is useful for enforcing strict request timing policies.
///
/// - Note: This interceptor does not modify the response.
/// - Important: This interceptor only affects the timeout value stored in the request.
///   The actual timeout enforcement depends on the URLSession configuration.
public struct RequestTimeoutInterceptor: NetworkInterceptorProtocol {
    private let timeout: TimeInterval

    public init(timeout: TimeInterval) {
        self.timeout = timeout
    }

    public func intercept(request: URLRequest) -> URLRequest {
        var modifiedRequest = request
        modifiedRequest.timeoutInterval = timeout
        return modifiedRequest
    }

    public func intercept(response: URLResponse?, data: Data?) -> (URLResponse?, Data?) {
        return (response, data)
    }
}
