import XCTest
@testable import Deploylight

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

    func testOnlyInstalledCopiesReplaceTheOldApp() {
        let folders = [URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: "/Users/someone/Applications")]

        XCTAssertTrue(LegacyApp.isInApplicationsFolder(URL(fileURLWithPath: "/Applications/Deploylight.app"), folders: folders))
        XCTAssertTrue(LegacyApp.isInApplicationsFolder(URL(fileURLWithPath: "/Users/someone/Applications/Deploylight.app"), folders: folders))
        XCTAssertFalse(LegacyApp.isInApplicationsFolder(URL(fileURLWithPath: "/Users/someone/Downloads/Deploylight.app"), folders: folders))
        XCTAssertFalse(LegacyApp.isInApplicationsFolder(URL(fileURLWithPath: "/Volumes/Deploylight/Deploylight.app"), folders: folders))
        XCTAssertFalse(LegacyApp.isInApplicationsFolder(URL(fileURLWithPath: "/Applications/Tools/Deploylight.app"), folders: folders))
    }
}
