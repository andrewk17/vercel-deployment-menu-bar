import XCTest
@testable import Deploylight

final class ProjectSummaryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testGroupsByProjectInOrderOfLatestActivity() {
        let summaries = ProjectSummary.summaries(from: [
            deployment("a3", project: "api", minutesAgo: 1),
            deployment("s1", project: "site", minutesAgo: 5),
            deployment("a2", project: "API", minutesAgo: 10),
            deployment("w1", project: "api", provider: .cloudflare, minutesAgo: 20),
        ])

        XCTAssertEqual(summaries.map(\.name), ["api", "site", "api"])
        XCTAssertEqual(summaries.map(\.provider), [.vercel, .vercel, .cloudflare])
        XCTAssertEqual(summaries[0].deployments.map(\.id), ["a3", "a2"], "Names match case-insensitively")
    }

    func testHeadlineIsLatestProductionDeployment() {
        let summary = ProjectSummary.summaries(from: [
            deployment("preview", target: .preview, minutesAgo: 1),
            deployment("prod", target: .production, minutesAgo: 30),
        ])[0]

        XCTAssertEqual(summary.headline.id, "prod")
    }

    func testHeadlineFallsBackToLatestWithoutProduction() {
        let summary = ProjectSummary.summaries(from: [
            deployment("newer", target: .preview, minutesAgo: 1),
            deployment("older", target: .preview, minutesAgo: 30),
        ])[0]

        XCTAssertEqual(summary.headline.id, "newer")
    }

    func testCapsTheNumberOfProjects() {
        let deployments = (0..<15).map { deployment("d\($0)", project: "p\($0)", minutesAgo: Double($0)) }

        let summaries = ProjectSummary.summaries(from: deployments)

        XCTAssertEqual(summaries.count, ProjectSummary.maxProjects)
        XCTAssertEqual(summaries.first?.name, "p0")
    }


    private func deployment(
        _ id: String,
        project: String = "web",
        provider: Deployment.Provider = .vercel,
        target: Deployment.Target = .production,
        minutesAgo: Double
    ) -> Deployment {
        let created = now.addingTimeInterval(-minutesAgo * 60)
        return Deployment(
            id: id,
            provider: provider,
            projectName: project,
            state: .ready,
            target: target,
            branch: "main",
            commitMessage: nil,
            createdAt: created,
            buildStartedAt: created,
            finishedAt: nil,
            link: nil
        )
    }
}
