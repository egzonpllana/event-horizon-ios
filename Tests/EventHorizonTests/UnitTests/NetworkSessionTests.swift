//
//  NetworkSessionTests.swift
//  EventHorizonTests
//

import XCTest
@testable import EventHorizon

final class NetworkSessionTests: XCTestCase {

    func test_init_singleTimeout_appliesToRequestAndResource() {
        let networkSession = NetworkSession(timeout: 42)

        XCTAssertEqual(networkSession.session.configuration.timeoutIntervalForRequest, 42)
        XCTAssertEqual(networkSession.session.configuration.timeoutIntervalForResource, 42)
    }

    func test_init_dualTimeouts_appliesDistinctValues() {
        let networkSession = NetworkSession(requestTimeout: 30, resourceTimeout: 120)

        XCTAssertEqual(networkSession.session.configuration.timeoutIntervalForRequest, 30)
        XCTAssertEqual(networkSession.session.configuration.timeoutIntervalForResource, 120)
    }
}
