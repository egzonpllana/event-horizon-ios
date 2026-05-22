import Foundation

/// A network interceptor that monitors network connectivity and provides better error handling for network-related issues.
///
/// `NetworkAwareInterceptor` checks network availability before making requests and provides
/// specific error types that help distinguish between network connectivity issues and server errors.
/// This prevents inappropriate user logout when there are only connectivity problems.
///
/// - Note: This interceptor requires a NetworkMonitorProtocol dependency to check connectivity.
/// - Important: Network connectivity errors should NOT cause user token clearing or logout.
public struct NetworkAwareInterceptor: NetworkInterceptorProtocol {
    
    private let networkMonitor: any NetworkMonitorProtocol
    
    public init(networkMonitor: any NetworkMonitorProtocol) {
        self.networkMonitor = networkMonitor
    }

    public func intercept(request: URLRequest) -> URLRequest {
        return request
    }

    public func intercept(response: URLResponse?, data: Data?) -> (URLResponse?, Data?) {
        return (response, data)
    }

    public func interceptAsync(request: URLRequest) async throws -> URLRequest {
        // Check network availability before making the request
        guard networkMonitor.isNetworkAvailable else {
            // Force refresh network state in case it's stuck
            networkMonitor.forceRefresh()
            
            // Wait a moment for the refresh to take effect
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            // Check again after refresh
            guard networkMonitor.isNetworkAvailable else {
                throw APIClientError.networkUnavailable
            }
            return request
        }
        return request
    }

    public func interceptAsync(response: URLResponse?, data: Data?) async throws -> (URLResponse?, Data?) {
        return (response, data)
    }
}

// MARK: - APIClientError Extension

extension APIClientError {
    /// Determines if an error is network-related and should not cause logout
    public var isNetworkConnectivityError: Bool {
        switch self {
        case .networkError(let urlError):
            return [
                .notConnectedToInternet,
                .networkConnectionLost,
                .dataNotAllowed,
                .internationalRoamingOff
            ].contains(urlError.code)
        case .timeout, .networkUnavailable:
            return true
        default:
            return false
        }
    }
} 
