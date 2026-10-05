import XCTest
@testable import Deploylight

final class GatherConcurrentlyTests: XCTestCase {
    private struct Failure: Error {}

    func testToleratesPartialFailure() async throws {
        let result = try await gatherConcurrently([1, 2, 3]) { value -> [Int] in
            if value == 2 { throw Failure() }
            return [value]
        }
        XCTAssertEqual(result.sorted(), [1, 3])
    }

    func testThrowsWhenEveryCallFails() async {
        do {
            _ = try await gatherConcurrently([1, 2]) { _ -> [Int] in throw Failure() }
            XCTFail("Expected an error")
        } catch {
            XCTAssertTrue(error is Failure)
        }
    }

    func testEmptyInputReturnsEmpty() async throws {
        let result = try await gatherConcurrently([Int]()) { _ -> [Int] in throw Failure() }
        XCTAssertEqual(result, [])
    }
}
