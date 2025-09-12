//
//  AuthTokenStoreProviding.swift
//  EventHorizon
//
//  Created by Egzon Pllana on 10.7.25.
//

import Foundation

/// A protocol for interceptors capable of handling authentication token refresh logic.
///
/// Conformers to this protocol can inspect a network response and determine whether
/// the original request should be retried after performing a token refresh operation.
///
/// This protocol should be used when an interceptor needs to signal retry behavior
/// to the API client without throwing an error.
///
/// - Note: This is typically used to implement token refreshing interceptors that
///         inspect 401 Unauthorized responses and attempt to refresh expired tokens.
public protocol TokenRefreshingInterceptorProtocol: NetworkInterceptorProtocol {

    /// Intercepts the given response and data, and determines what the API client should do next.
    ///
    /// - Parameters:
    ///   - response: The original `URLResponse` returned by the network call.
    ///   - data: The data associated with the response.
    ///
    /// - Returns: A tuple containing:
    ///   - `InterceptorAction`: The recommended action to take (`proceed` or `retryWithUpdatedToken`).
    ///   - `URLResponse?`: An optionally modified response.
    ///   - `Data?`: Optionally modified data.
    func interceptAsync(
        response: URLResponse?,
        data: Data?
    ) async -> (InterceptorAction, URLResponse?, Data?)
}

/// An action returned by an interceptor to guide the API client on how to proceed after interception.
public enum InterceptorAction {
    /// Indicates that the API client should continue processing the response as normal.
    case proceed

    /// Indicates that the interceptor has refreshed authentication credentials,
    /// and the original request should be retried with updated tokens.
    case retryWithUpdatedToken
}
