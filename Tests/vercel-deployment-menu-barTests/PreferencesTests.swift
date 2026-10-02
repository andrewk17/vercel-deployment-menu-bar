import XCTest
@testable import vercel_deployment_menu_bar

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
    }

    func testRoundTrips() throws {
        var preferences = Preferences.default
        preferences.cloudflareToken = "cf"
        preferences.cloudflareWorkers = "api, site, API"

        let decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))

        XCTAssertEqual(decoded, preferences)
        XCTAssertEqual(decoded.cloudflareWorkerList, ["api", "site"])
    }
}
