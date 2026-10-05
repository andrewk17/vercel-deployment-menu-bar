import XCTest
@testable import Deploylight

final class VercelClientTests: XCTestCase {
    func testReadsMessageFromVercelErrorBody() {
        let body = Data(#"{"error": {"code": "forbidden", "message": "Not authorized"}}"#.utf8)
        XCTAssertEqual(VercelClient.errorMessage(from: body), "Not authorized")
        XCTAssertEqual(VercelClient.errorMessage(from: Data("Bad gateway".utf8)), "Bad gateway")
    }
}
