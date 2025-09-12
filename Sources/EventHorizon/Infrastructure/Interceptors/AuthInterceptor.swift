import Foundation

/// An interceptor that injects an authorization token into network requests.
///
/// `AuthInterceptor` is responsible for modifying outgoing network requests by adding an
/// `Authorization` header if a valid token is available. This is useful for APIs that require
/// authentication via bearer tokens.
///
/// This interceptor conforms to `Sendable`, ensuring safe usage across concurrency domains.
///
/// ## Example Usage
/// ```swift
/// let authInterceptor = AuthInterceptor(tokenProvider: "your_access_token_here")
/// let apiClient = APIClient(interceptors: [authInterceptor])
/// ```
///
/// - Note: The `tokenProvider` is a closure that returns an optional `String` representing the authentication token.
///         It is marked as `@Sendable` to ensure thread-safety when accessed in concurrent execution contexts.
public struct AuthInterceptor: NetworkInterceptorProtocol {

    private let tokenProvider: @Sendable () -> String?

    /// Initializes the interceptor with a closure that provides the access token.
    ///
    /// - Parameter tokenProvider: A closure returning the access token, or `nil` if none exists.
    ///
    /// ## Example Usage
    ///
    /// ```swift
    /// // Using static token
    /// let authInterceptor = AuthInterceptor(tokenProvider: { "my_static_token" })
    ///
    public init(tokenProvider: @Sendable @escaping () -> String?) {
        self.tokenProvider = tokenProvider
    }

    public func intercept(request: URLRequest) -> URLRequest {
        var modifiedRequest = request

        // Inject the Authorization header if a token is available
        if let token = tokenProvider() {
            modifiedRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        return modifiedRequest
    }

    public func intercept(response: URLResponse?, data: Data?) -> (URLResponse?, Data?) {
        // No response modifications needed for now
        return (response, data)
    }
}
