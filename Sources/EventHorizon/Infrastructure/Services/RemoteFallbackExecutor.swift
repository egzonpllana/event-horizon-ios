//
//  RemoteFallbackExecutor.swift
//  EventHorizon
//

import Foundation

/// Errors produced by `DefaultRemoteFallbackExecutor`.
public enum RemoteFallbackError: Error, Equatable {

    /// The remote operation exceeded the caller-provided overall timeout.
    case timedOut(after: TimeInterval)
}

/// Runs a remote operation with an optional overall timeout, falling back to a
/// local provider when the remote operation fails.
///
/// The outcome is explicit: callers always know whether the returned value is
/// fresh (`.cloud`) or served from the fallback after an error (`.cache`).
public protocol RemoteFallbackExecuting: Sendable {

    /// Executes `remote`, falling back to `fallback` on failure.
    ///
    /// - Parameters:
    ///   - timeout: Optional overall deadline for the remote operation. When it
    ///     elapses, the remote attempt is abandoned and the fallback is used.
    ///     Pass `nil` to rely solely on the transport's own timeouts.
    ///   - remote: The remote operation producing fresh data.
    ///   - fallback: The local provider used when the remote operation fails.
    /// - Returns: `.cloud(value)` on remote success, `.cache(value, underlyingError:)`
    ///   when the fallback supplied the value after a remote failure.
    /// - Throws: The remote error when the fallback also fails, or
    ///   `CancellationError` when the surrounding task was cancelled.
    func execute<T: Sendable>(
        timeout: TimeInterval?,
        remote: @Sendable @escaping () async throws -> T,
        fallback: @Sendable @escaping () async throws -> T
    ) async throws -> FetchOutcome<T>
}

public extension RemoteFallbackExecuting {

    /// Executes `remote` with no overall timeout, falling back to `fallback` on failure.
    func execute<T: Sendable>(
        remote: @Sendable @escaping () async throws -> T,
        fallback: @Sendable @escaping () async throws -> T
    ) async throws -> FetchOutcome<T> {
        try await execute(timeout: nil, remote: remote, fallback: fallback)
    }
}

/// Default `RemoteFallbackExecuting` implementation.
///
/// Behavior:
/// - Remote success → `.cloud(value)`.
/// - Remote failure → `fallback()`; its value is returned as `.cache` carrying
///   the remote error. When the fallback also fails, the remote error is thrown
///   because it is the more informative of the two.
/// - Timeout → the remote attempt loses a structured-concurrency race against
///   `RemoteFallbackError.timedOut` and is cancelled; the failure then routes
///   into the fallback path like any other remote error.
/// - Cancellation of the surrounding task is passed through: a cancelled caller
///   never receives a `.cache` outcome.
public final class DefaultRemoteFallbackExecutor: RemoteFallbackExecuting {

    public init() {}

    public func execute<T: Sendable>(
        timeout: TimeInterval?,
        remote: @Sendable @escaping () async throws -> T,
        fallback: @Sendable @escaping () async throws -> T
    ) async throws -> FetchOutcome<T> {
        let remoteError: any Error
        do {
            let value = try await runRemote(timeout: timeout, remote: remote)
            return .cloud(value)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            guard !Task.isCancelled else {
                throw CancellationError()
            }
            remoteError = error
        }

        guard let cached = try? await fallback() else {
            throw remoteError
        }
        return .cache(cached, underlyingError: remoteError)
    }

    // MARK: - Private

    private func runRemote<T: Sendable>(
        timeout: TimeInterval?,
        remote: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        guard let timeout else {
            return try await remote()
        }

        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await remote()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw RemoteFallbackError.timedOut(after: timeout)
            }

            guard let first = try await group.next() else {
                throw RemoteFallbackError.timedOut(after: timeout)
            }
            group.cancelAll()
            return first
        }
    }
}
