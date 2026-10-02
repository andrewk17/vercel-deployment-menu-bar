import XCTest
@testable import vercel_deployment_menu_bar

final class DeploymentFilterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testDecodesVercelDeploymentAndDerivesDisplayFields() throws {
        let json = """
        {
          "uid": "dpl_1", "name": "web", "url": "web-abc.vercel.app", "inspectorUrl": "",
          "created": 1800000000000, "state": "SOMETHING_NEW", "target": "production",
          "meta": { "githubCommitRef": "main", "githubCommitMessage": "Ship it" }
        }
        """
        let deployment = try JSONDecoder().decode(VercelDeployment.self, from: Data(json.utf8))

        XCTAssertEqual(deployment.state, .unknown)
        XCTAssertEqual(deployment.branch, "main")
        XCTAssertEqual(deployment.commitMessage, "Ship it")
        XCTAssertEqual(deployment.link, URL(string: "https://web-abc.vercel.app"))
        XCTAssertEqual(deployment.buildingAtDate, now)
    }

    func testFiltersByStateTargetBranchAndProject() {
        var preferences = Preferences.default
        preferences.limitByCount = nil
        preferences.showError = false
        preferences.showPreview = false
        preferences.gitBranches = "Main"
        preferences.projectName = "web"

        let deployments = [
            deployment("keep", state: "READY", target: "production", branch: "main"),
            deployment("error", state: "ERROR", target: "production", branch: "main"),
            deployment("preview", state: "READY", target: "preview", branch: "main"),
            deployment("branch", state: "READY", target: "production", branch: "feature"),
            deployment("no-branch", state: "READY", target: "production", branch: nil),
            deployment("project", name: "api", state: "READY", target: "production", branch: "main"),
        ]

        let result = DeploymentFilter(preferences: preferences).apply(to: deployments, now: now)

        XCTAssertEqual(result.map(\.uid), ["keep"])
    }

    func testCountLimitTakesPriorityOverHours() {
        var preferences = Preferences.default
        preferences.limitByCount = 2
        preferences.limitByHours = 1

        let deployments = (0..<4).map { deployment("d\($0)", createdHoursAgo: Double($0) * 3) }
        let result = DeploymentFilter(preferences: preferences).apply(to: deployments, now: now)

        XCTAssertEqual(result.map(\.uid), ["d0", "d1"])
    }

    func testHoursLimitAppliesWithoutCountLimit() {
        var preferences = Preferences.default
        preferences.limitByCount = nil
        preferences.limitByHours = 4

        let deployments = (0..<4).map { deployment("d\($0)", createdHoursAgo: Double($0) * 3) }
        let result = DeploymentFilter(preferences: preferences).apply(to: deployments, now: now)

        XCTAssertEqual(result.map(\.uid), ["d0", "d1"])
    }

    private func deployment(
        _ uid: String,
        name: String = "web",
        state: String = "READY",
        target: String? = "production",
        branch: String? = "main",
        createdHoursAgo: Double = 0
    ) -> VercelDeployment {
        let created = (now.timeIntervalSince1970 - createdHoursAgo * 3600) * 1000
        var object: [String: Any] = ["uid": uid, "name": name, "url": "\(uid).vercel.app", "created": created, "state": state]
        object["target"] = target
        object["meta"] = branch.map { ["githubCommitRef": $0] }
        let data = try! JSONSerialization.data(withJSONObject: object)
        return try! JSONDecoder().decode(VercelDeployment.self, from: data)
    }
}
