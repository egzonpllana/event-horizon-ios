//
//  FetchOutcome.swift
//  EventHorizon
//

import Foundation

/// The result of a remote-with-fallback fetch, making the data's origin explicit.
///
/// Callers can distinguish a genuine remote success from cached data returned
/// after a remote failure, and react accordingly (e.g. only mark a screen as
/// "synced" on `.cloud`).
public enum FetchOutcome<T> {

    /// The remote operation succeeded; the value is fresh.
    case cloud(T)

    /// The remote operation failed; the value comes from the fallback provider.
    /// The error that caused the fallback is attached.
    case cache(T, underlyingError: any Error)

    /// The wrapped value, regardless of origin.
    public var value: T {
        switch self {
        case .cloud(let value):
            return value
        case .cache(let value, _):
            return value
        }
    }

    /// `true` when the value came from a successful remote operation.
    public var isFromCloud: Bool {
        if case .cloud = self {
            return true
        }
        return false
    }

    /// The remote error that triggered the fallback, or `nil` for `.cloud`.
    public var underlyingError: (any Error)? {
        if case .cache(_, let error) = self {
            return error
        }
        return nil
    }

    /// Transforms the wrapped value while preserving the outcome's origin.
    public func map<U>(_ transform: (T) -> U) -> FetchOutcome<U> {
        switch self {
        case .cloud(let value):
            return .cloud(transform(value))
        case .cache(let value, let error):
            return .cache(transform(value), underlyingError: error)
        }
    }
}

extension FetchOutcome: Sendable where T: Sendable {}
