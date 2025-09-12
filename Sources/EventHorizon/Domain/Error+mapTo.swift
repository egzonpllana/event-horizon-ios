//
//  Error+mapTo.swift
//  EventHorizon
//
//  Created by Egzon Pllana on 10.7.25.
//

import Foundation

public extension Error {
    func mapTo<T: Error>(_ transform: (String) -> T) -> Error {
        if let apiError = self as? APIClientError,
           case let .serverMessage(message, _) = apiError {
            return transform(message)
        } else {
            return self
        }
    }
}
