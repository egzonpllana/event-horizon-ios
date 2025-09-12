import Foundation

/// An error type representing failures that can occur during API client operations.
///
/// `APIClientError` conforms to `Error`, `LocalizedError`, and `CustomNSError`,
/// providing detailed cases for common networking and request issues such as
/// invalid URLs, unauthorized access, token refresh problems, network errors,
/// and server messages.
///
/// Use this enum to standardize error handling across API client interactions.
///
/// Cases include:
/// - `invalidURL`: The provided URL was invalid.
/// - `unauthorized`: The request was unauthorized due to missing or invalid credentials.
/// - `refreshTokenInvalid`: The refresh token is invalid or expired.
/// - `retryWithNewToken`: The request should be retried with a new access token.
/// - `statusCode(Int)`: The server returned a non-success status code.
/// - `invalidResponse(Data)`: The response data is not in a valid format.
/// - `networkError(URLError)`: A `URLError` occurred during the request.
/// - `requestFailed(Error)`: The request failed with a general error.
/// - `taskFinished`: The task has already finished.
/// - `taskCanceled`: The task was canceled.
/// - `taskInProgress`: The task is already in progress.
/// - `urlRequestIsEmpty`: The `URLRequest` was empty or not properly configured.
/// - `serverMessage(message: String, statusCode: Int)`: A server-provided error message with a status code.
/// - `timeout`: The request timed out.
/// - `networkUnavailable`: No network connection was available.
///
/// This type also provides localized error descriptions and user info dictionaries
/// suitable for presenting errors to end users.
public enum APIClientError: Error, LocalizedError, CustomNSError {
    case invalidURL
    case unauthorized
    case refreshTokenInvalid
    case retryWithNewToken
    case statusCode(Int)
    case invalidResponse(Data)
    case networkError(URLError)
    case requestFailed(Error)
    case taskFinished
    case taskCanceled
    case taskInProgress
    case urlRequestIsEmpty
    case serverMessage(message: String, statusCode: Int)
    case timeout
    case networkUnavailable

    public var errorDescription: String? {
        switch self {
            case .serverMessage(let message, _):
                return message
            case .timeout:
                return "The request timed out. Please try again."
            case .networkUnavailable:
                return "Network is not available. Please check your connection."
            default:
                return nil
        }
    }

    public var errorUserInfo: [String : Any] {
        switch self {
            case .serverMessage(let message, _):
                return [NSLocalizedDescriptionKey: message]
            case .timeout:
                return [NSLocalizedDescriptionKey: "The request timed out."]
            case .networkUnavailable:
                return [NSLocalizedDescriptionKey: "Network is not available."]
            default:
                return [:]
        }
    }
}
