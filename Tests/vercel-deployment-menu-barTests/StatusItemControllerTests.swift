import XCTest
@testable import vercel_deployment_menu_bar

final class StatusItemControllerTests: XCTestCase {
    func testSanitizedCommitToolTipTruncatesLongMultilineMessage() {
        let longSubject = "Fix deployment sorting by switching to ISO dates and preserving year info across month boundaries while cleaning edge case display output for menu labels"
        let rawMessage = """
        \(longSubject)

        Body details should not be shown in the tooltip.
        Co-authored-by: Example <example@example.com>
        """

        let tooltip = StatusItemController.sanitizedCommitToolTip(from: rawMessage)

        XCTAssertNotNil(tooltip)
        guard let tooltip else { return }

        XCTAssertEqual(tooltip.count, 90)
        XCTAssertFalse(tooltip.contains("\n"))
        XCTAssertFalse(tooltip.contains("Body details"))
    }

    func testSanitizedCommitToolTipReturnsNilForEmptyMessage() {
        XCTAssertNil(StatusItemController.sanitizedCommitToolTip(from: nil))
        XCTAssertNil(StatusItemController.sanitizedCommitToolTip(from: "   \n\n   "))
    }
}
