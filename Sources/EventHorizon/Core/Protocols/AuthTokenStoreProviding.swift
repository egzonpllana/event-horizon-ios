//
//  AuthTokenStoreProviding.swift
//  EventHorizon
//
//  Created by Egzon Pllana on 10.7.25.
//

import Foundation

/// A repository for managing authentication tokens, such as access and refresh tokens.
/// Typically backed by secure storage (e.g. Keychain), this protocol abstracts how tokens
/// are persisted and accessed across the app.
///
/// Implementations should ensure secure and thread-safe storage of sensitive credentials.
public protocol AuthTokenStoreProviding {

    /// The access token used to authenticate API requests.
    ///
    /// Use this value to populate the `Authorization` header.
    var accessToken: String? { get }

    /// The refresh token used to obtain new access tokens when expired.
    ///
    /// This token should also be stored securely and persisted across sessions.
    var refreshToken: String? { get }

    /// Clears all authentication tokens from storage.
    ///
    /// This is typically called on user logout or session expiration.
    func clear()

    func setAccessToken(_ token: String)
    func setRefreshToken(_ token: String)
}
