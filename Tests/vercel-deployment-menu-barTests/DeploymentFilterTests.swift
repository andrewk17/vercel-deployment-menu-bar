import XCTest
@testable import vercel_deployment_menu_bar

final class DeploymentFilterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testMapsVercelDeployment() throws {
        let json = """
        {
          "uid": "dpl_1", "name": "web", "url": "web-abc.vercel.app", "inspectorUrl": "",
          "created": 1800000000000, "state": "SOMETHING_NEW", "target": null,
          "meta": { "githubCommitRef": "main", "githubCommitMessage": "Ship it" }
        }
        """
        let deployment = try JSONDecoder().decode(VercelDeployment.self, from: Data(json.utf8)).asDeployment

        XCTAssertEqual(deployment.provider, .vercel)
        XCTAssertEqual(deployment.state, .unknown)
        XCTAssertEqual(deployment.target, .preview, "Vercel previews have a null target")
        XCTAssertEqual(deployment.branch, "main")
        XCTAssertEqual(deployment.commitMessage, "Ship it")
        XCTAssertEqual(deployment.link, URL(string: "https://web-abc.vercel.app"))
        XCTAssertEqual(deployment.buildStartedAt, now)
    }

    func testFiltersByStateTargetAndBranch() {
        var preferences = Preferences.default
        preferences.limitByCount = nil
        preferences.showError = false
        preferences.showPreview = false
        preferences.gitBranches = "Main"

        let deployments = [
            deployment("keep"),
            deployment("error", state: .error),
            deployment("preview", target: .preview),
            deployment("branch", branch: "feature"),
            deployment("no-branch", branch: nil),
        ]

        let result = DeploymentFilter(preferences: preferences).apply(to: deployments, now: now)

        XCTAssertEqual(result.map(\.id), ["keep"])
    }

    func testCountLimitAppliesAcrossProvidersNewestFirst() {
        var preferences = Preferences.default
        preferences.limitByCount = 2
        preferences.limitByHours = 1

        let deployments = [
            deployment("old", createdHoursAgo: 6),
            deployment("cf", provider: .cloudflare, createdHoursAgo: 1),
            deployment("vercel", createdHoursAgo: 0),
        ]
        let result = DeploymentFilter(preferences: preferences).apply(to: deployments, now: now)

        XCTAssertEqual(result.map(\.id), ["vercel", "cf"])
    }

    func testHoursLimitAppliesWithoutCountLimit() {
        var preferences = Preferences.default
        preferences.limitByCount = nil
        preferences.limitByHours = 4

        let deployments = (0..<4).map { deployment("d\($0)", createdHoursAgo: Double($0) * 3) }
        let result = DeploymentFilter(preferences: preferences).apply(to: deployments, now: now)

        XCTAssertEqual(result.map(\.id), ["d0", "d1"])
    }

    func testInProgressBuildsSurviveTheCountLimit() {
        var preferences = Preferences.default
        preferences.limitByCount = 1

        let deployments = [
            deployment("building", state: .building, createdHoursAgo: 2),
            deployment("older", createdHoursAgo: 1),
            deployment("newest", createdHoursAgo: 0),
        ]
        let result = DeploymentFilter(preferences: preferences).apply(to: deployments, now: now)

        XCTAssertEqual(result.map(\.id), ["newest", "building"])
    }

    private func deployment(
        _ id: String,
        provider: Deployment.Provider = .vercel,
        state: Deployment.State = .ready,
        target: Deployment.Target = .production,
        branch: String? = "main",
        createdHoursAgo: Double = 0
    ) -> Deployment {
        let created = now.addingTimeInterval(-createdHoursAgo * 3600)
        return Deployment(
            id: id,
            provider: provider,
            projectName: "web",
            state: state,
            target: target,
            branch: branch,
            commitMessage: nil,
            createdAt: created,
            buildStartedAt: created,
            finishedAt: nil,
            link: nil
        )
    }
}
