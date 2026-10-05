import XCTest
@testable import Deploylight

final class DisplayTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testFormatsDurations() {
        XCTAssertEqual(Formatting.duration(42, format: .clock), "0:42")
        XCTAssertEqual(Formatting.duration(134, format: .clock), "2:14")
        XCTAssertEqual(Formatting.duration(3723, format: .clock), "1:02:03")

        XCTAssertEqual(Formatting.duration(42, format: .units), "42s")
        XCTAssertEqual(Formatting.duration(134, format: .units), "2m 14s")
        XCTAssertEqual(Formatting.duration(3723, format: .units), "1h 2m 3s")

        XCTAssertEqual(Formatting.duration(42, format: .minutes), "<1m")
        XCTAssertEqual(Formatting.duration(134, format: .minutes), "2m")
        XCTAssertEqual(Formatting.duration(3723, format: .minutes), "1h 2m")
    }

    func testFormatsShortAges() {
        XCTAssertEqual(Formatting.age(of: now.addingTimeInterval(-30), now: now), "just now")
        XCTAssertEqual(Formatting.age(of: now.addingTimeInterval(-20 * 60), now: now), "20m ago")
        XCTAssertEqual(Formatting.age(of: now.addingTimeInterval(-3 * 3600), now: now), "3h ago")
        XCTAssertEqual(Formatting.age(of: now.addingTimeInterval(-2 * 86_400), now: now), "2d ago")
        XCTAssertEqual(Formatting.age(of: now.addingTimeInterval(-21 * 86_400), now: now), "3w ago")
    }

    func testMenuBarTextFollowsStyle() {
        func text(_ state: Deployment.State, _ style: MenuBarStyle) -> String {
            StatusTitle.text(projectName: "web", state: state, elapsed: 72, style: style, timeFormat: .clock)
        }

        XCTAssertEqual(text(.ready, .auto), "")
        XCTAssertEqual(text(.building, .auto), "WEB 1:12")
        XCTAssertEqual(text(.ready, .detailed), "WEB 1:12")
        XCTAssertEqual(text(.building, .compact), "")
    }

    func testStatusSaysWhatTheTimeMeasures() {
        func status(_ state: Deployment.State, finished: Bool = true) -> String {
            let deployment = makeDeployment(state: state, finishedAt: finished ? now.addingTimeInterval(-60) : nil)
            return Formatting.status(of: deployment, format: .clock, now: now)
        }

        XCTAssertEqual(status(.building), "Building 3:00")
        XCTAssertEqual(status(.queued), "Queued 4:00")
        XCTAssertEqual(status(.ready), "Built in 2:00")
        XCTAssertEqual(status(.ready, finished: false), "Ready")
        XCTAssertEqual(status(.error), "Failed after 2:00")
        XCTAssertEqual(status(.canceled), "Canceled")
    }

    @MainActor
    func testRowsSpellOutProviderAndEnvironmentInPlainText() {
        var preferences = Preferences.default
        let deployment = makeDeployment(state: .ready, finishedAt: now.addingTimeInterval(-60))
        let time = Formatting.time(deployment.buildStartedAt)

        func row(showsProvider: Bool = true, includeProject: Bool = true) -> String {
            MenuRowFormatter(preferences: preferences, showsProvider: showsProvider, font: .menuFont(ofSize: 0), now: now)
                .title(for: deployment, includeProject: includeProject)
                .plain
        }

        XCTAssertEqual(row(), "web (main) — Vercel • Production • Built in 2:00 • \(time)")
        XCTAssertEqual(row(showsProvider: false), "web (main) — Production • Built in 2:00 • \(time)")
        XCTAssertEqual(row(includeProject: false), "main — Production • Built in 2:00 • \(time)")

        preferences.providerStyle = .hidden
        preferences.environmentStyle = .hidden
        XCTAssertEqual(row(), "web (main) — Built in 2:00 • \(time)")
    }

    @MainActor
    func testRowsDrawIconsAndBadgesWhenChosen() {
        let deployment = makeDeployment(state: .ready, finishedAt: now.addingTimeInterval(-60))

        func attachmentCount(_ preferences: Preferences) -> Int {
            let text = MenuRowFormatter(preferences: preferences, showsProvider: true, font: .menuFont(ofSize: 0), now: now)
                .title(for: deployment, includeProject: true)
                .attributed
            var count = 0
            text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, _, _ in
                if value != nil { count += 1 }
            }
            return count
        }

        var preferences = Preferences.default
        XCTAssertEqual(attachmentCount(preferences), 2, "Provider icon and environment badge")
        preferences.providerStyle = .name
        preferences.environmentStyle = .text
        XCTAssertEqual(attachmentCount(preferences), 0)
    }

    private func makeDeployment(state: Deployment.State, finishedAt: Date?) -> Deployment {
        Deployment(
            id: "1",
            provider: .vercel,
            projectName: "web",
            state: state,
            target: .production,
            branch: "main",
            commitMessage: nil,
            createdAt: now.addingTimeInterval(-240),
            buildStartedAt: now.addingTimeInterval(-180),
            finishedAt: finishedAt,
            link: nil
        )
    }
}
