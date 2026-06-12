//
//  NetworkSession.swift
//  EventHorizon
//

import Foundation

/// A concrete implementation of `NetworkSessionProtocol` that wraps `URLSession` with configurable timeout support.
public final class NetworkSession: NetworkSessionProtocol {

    let session: URLSession

    /// Initializes a `NetworkSession` with optional timeout settings.
    ///
    /// - Parameters:
    ///   - timeout: The timeout interval to apply for both the request and resource. Defaults to 60 seconds.
    ///   - delegate: Optional `URLSessionDelegate`, if needed for custom behavior.
    public init(
        timeout: TimeInterval = 60,
        delegate: URLSessionDelegate? = nil
    ) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        self.session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    /// Initializes a `NetworkSession` with distinct request and resource timeouts.
    ///
    /// - Parameters:
    ///   - requestTimeout: The idle interval allowed between data arrivals (`timeoutIntervalForRequest`).
    ///   - resourceTimeout: The total interval allowed for the whole transfer (`timeoutIntervalForResource`).
    ///   - delegate: Optional `URLSessionDelegate`, if needed for custom behavior.
    public init(
        requestTimeout: TimeInterval,
        resourceTimeout: TimeInterval,
        delegate: URLSessionDelegate? = nil
    ) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = resourceTimeout
        self.session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    /// Initializes with a pre-configured `URLSession`.
    ///
    /// - Parameter session: The `URLSession` instance to use.
    public init(session: URLSession) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        return try await session.data(for: request)
    }
}
