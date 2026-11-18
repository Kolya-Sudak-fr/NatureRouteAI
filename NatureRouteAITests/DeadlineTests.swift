import XCTest
@testable import NatureRouteAI

@MainActor
final class DeadlineTests: XCTestCase {

    func testOperationThatFinishesInTimeReturnsItsValue() async throws {
        let value = try await withDeadline(.seconds(5)) { 42 }

        XCTAssertEqual(value, 42)
    }

    /// Stands in for a MapKit request that never calls back.
    func testOperationThatNeverAnswersIsCutOffAtTheDeadline() async {
        let started = ContinuousClock.now
        do {
            _ = try await withDeadline(.milliseconds(100)) {
                try await Task.sleep(for: .seconds(60))
                return 1
            }
            XCTFail("The deadline should have fired")
        } catch DeadlineError.exceeded {
            XCTAssertLessThan(ContinuousClock.now - started, .seconds(5))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCancellingTheCallerStillCancelsTheOperation() async {
        let task = Task {
            try await withDeadline(.seconds(60)) {
                try await Task.sleep(for: .seconds(60))
                return 1
            }
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Cancellation should reach the caller")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
