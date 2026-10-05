import XCTest
@testable import Deploylight

final class PreferencesTests: XCTestCase {
    func testDecodesPreferencesSavedBeforeCloudflareSupport() throws {
        let legacy = """
        {
          "vercelToken": "token", "teamId": "acme", "projectName": "web", "gitBranches": "",
          "showProduction": true, "showPreview": false, "showReady": true, "showBuilding": true,
          "showError": true, "showQueued": true, "showCanceled": true, "refreshIntervalIdle": 30
        }
        """
        let preferences = try JSONDecoder().decode(Preferences.self, from: Data(legacy.utf8))

        XCTAssertEqual(preferences.vercelToken, "token")
        XCTAssertEqual(preferences.teamIdList, ["acme"])
        XCTAssertFalse(preferences.showPreview)
        XCTAssertEqual(preferences.cloudflareToken, "")
        XCTAssertFalse(preferences.hasCloudflareToken)
        XCTAssertNil(preferences.limitByCount, "A cleared limit must stay cleared")
        XCTAssertEqual(preferences.refreshIntervalIdle, 30)
        XCTAssertEqual(preferences.menuBarStyle, .auto)
        XCTAssertEqual(preferences.timeFormat, .clock)
        XCTAssertTrue(preferences.showProjects)
        XCTAssertEqual(preferences.providerStyle, .icon)
        XCTAssertEqual(preferences.environmentStyle, .badge)
    }

    func testUnknownMenuBarStyleFallsBackToDefault() throws {
        let json = #"{"vercelToken": "token", "menuBarStyle": "sparkly", "environmentStyle": "neon", "showProjects": false}"#
        let preferences = try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))

        XCTAssertEqual(preferences.vercelToken, "token", "Other settings survive")
        XCTAssertEqual(preferences.menuBarStyle, .auto)
        XCTAssertEqual(preferences.environmentStyle, .badge)
        XCTAssertFalse(preferences.showProjects)
    }

    func testRoundTrips() throws {
        var preferences = Preferences.default
        preferences.cloudflareToken = "cf"
        preferences.cloudflareWorkers = "api, site, API"
        preferences.menuBarStyle = .detailed
        preferences.timeFormat = .minutes
        preferences.showProjects = false
        preferences.providerStyle = .name
        preferences.environmentStyle = .text

        let decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))

        XCTAssertEqual(decoded, preferences)
        XCTAssertEqual(decoded.cloudflareWorkerList, ["api", "site"])
    }
}
