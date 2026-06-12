//
//  RemoteFallbackExecutorTests.swift
//  EventHorizonTests
//

import XCTest
@testable import EventHorizon

final class RemoteFallbackExecutorTests: XCTestCase {

    // MARK: - Properties

    private var executor: DefaultRemoteFallbackExecutor!

    private enum TestError: Error, Equatable {
        case remoteFailed
        case fallbackFailed
    }

    // MARK: - Setup & Teardown

    override func setUp() {
        super.setUp()
        executor = DefaultRemoteFallbackExecutor()
    }

    override func tearDown() {
        executor = nil
        super.tearDown()
    }

    // MARK: - Tests

    func test_execute_remoteSucceeds_returnsCloudOutcome() async throws {
        let outcome = try await executor.execute(
            remote: { "fresh" },
            fallback: { "stale" }
        )

        XCTAssertTrue(outcome.isFromCloud)
        XCTAssertEqual(outcome.value, "fresh")
        XCTAssertNil(outcome.underlyingError)
    }

    func test_execute_remoteFails_returnsCacheOutcomeWithUnderlyingError() async throws {
        let outcome = try await executor.execute(
            remote: { () async throws -> String in throw TestError.remoteFailed },
            fallback: { "stale" }
        )

        XCTAssertFalse(outcome.isFromCloud)
        XCTAssertEqual(outcome.value, "stale")
        XCTAssertEqual(outcome.underlyingError as? TestError, .remoteFailed)
    }

    func test_execute_bothFail_throwsRemoteError() async {
        do {
            _ = try await executor.execute(
                remote: { () async throws -> String in throw TestError.remoteFailed },
                fallback: { () async throws -> String in throw TestError.fallbackFailed }
            )
            XCTFail("Expected the remote error to be thrown")
        } catch {
            XCTAssertEqual(error as? TestError, .remoteFailed)
        }
    }

    func test_execute_timeoutElapses_fallbackIsUsed() async throws {
        let outcome = try await executor.execute(
            timeout: 0.05,
            remote: { () async throws -> String in
                try await Task.sleep(nanoseconds: 2_000_000_000)
                return "fresh"
            },
            fallback: { "stale" }
        )

        XCTAssertFalse(outcome.isFromCloud)
        XCTAssertEqual(outcome.value, "stale")
        XCTAssertEqual(
            outcome.underlyingError as? RemoteFallbackError,
            .timedOut(after: 0.05)
        )
    }

    func test_execute_remoteFinishesBeforeTimeout_returnsCloudOutcome() async throws {
        let outcome = try await executor.execute(
            timeout: 5,
            remote: { "fresh" },
            fallback: { "stale" }
        )

        XCTAssertTrue(outcome.isFromCloud)
        XCTAssertEqual(outcome.value, "fresh")
    }

    func test_execute_surroundingTaskCancelled_throwsCancellationWithoutFallback() async {
        let fallbackCalled = expectation(description: "fallback must not be called")
        fallbackCalled.isInverted = true

        let task = Task { [executor] in
            _ = try await executor!.execute(
                remote: { () async throws -> String in
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                    return "fresh"
                },
                fallback: { () async throws -> String in
                    fallbackCalled.fulfill()
                    return "stale"
                }
            )
        }

        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation to propagate")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }

        await fulfillment(of: [fallbackCalled], timeout: 0.2)
    }

    func test_fetchOutcome_map_preservesOriginAndError() {
        let cloud: FetchOutcome<Int> = .cloud(1)
        let mappedCloud = cloud.map { $0 + 1 }
        XCTAssertTrue(mappedCloud.isFromCloud)
        XCTAssertEqual(mappedCloud.value, 2)

        let cache: FetchOutcome<Int> = .cache(1, underlyingError: TestError.remoteFailed)
        let mappedCache = cache.map { $0 + 1 }
        XCTAssertFalse(mappedCache.isFromCloud)
        XCTAssertEqual(mappedCache.value, 2)
        XCTAssertEqual(mappedCache.underlyingError as? TestError, .remoteFailed)
    }
}
