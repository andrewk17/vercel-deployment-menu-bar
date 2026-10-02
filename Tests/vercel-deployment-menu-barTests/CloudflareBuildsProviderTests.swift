import XCTest
@testable import vercel_deployment_menu_bar

final class CloudflareBuildsProviderTests: XCTestCase {
    private var provider: CloudflareBuildsProvider!
    private var preferences = Preferences.default

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        provider = CloudflareBuildsProvider(client: CloudflareClient(session: URLSession(configuration: configuration)))
        preferences.cloudflareToken = "token"

        StubURLProtocol.responses["/client/v4/accounts"] = envelope(#"[{"id": "acc", "name": "Personal"}]"#)
        StubURLProtocol.responses["/client/v4/accounts/acc/workers/scripts"] = envelope(
            #"[{"id": "my-worker", "tag": "t1"}, {"id": "local-only", "tag": "t2"}]"#
        )
    }

    func testMapsBuildHistoryAndOnlyRefetchesWhenLatestBuildChanges() async throws {
        let running = build(uuid: "b2", status: "running", outcome: nil, created: "2026-10-02T18:25:00.123456Z")
        let finished = build(uuid: "b1", status: "stopped", outcome: "success", created: "2026-10-02T17:00:00Z")
        StubURLProtocol.responses["/client/v4/accounts/acc/builds/builds/latest"] = envelope(#"{"builds": {"t1": \#(running)}}"#)
        StubURLProtocol.responses["/client/v4/accounts/acc/builds/workers/t1/builds"] = envelope("[\(finished), \(running)]")

        let first = try await provider.fetchDeployments(preferences: preferences)

        XCTAssertEqual(first.map(\.id), ["b2", "b1"])
        XCTAssertEqual(first.map(\.state), [.building, .ready])
        XCTAssertEqual(first[0].projectName, "my-worker")
        XCTAssertEqual(first[0].branch, "main")
        XCTAssertEqual(first[0].target, .production)
        XCTAssertEqual(
            first[0].link,
            URL(string: "https://dash.cloudflare.com/acc/workers/services/view/my-worker/production/builds/b2")
        )
        XCTAssertEqual(StubURLProtocol.requestedQueries["/client/v4/accounts/acc/builds/builds/latest"], ["external_script_ids=t1,t2"])

        // The running build finishes: the latest build is updated in place without refetching history.
        let done = build(uuid: "b2", status: "stopped", outcome: "fail", created: "2026-10-02T18:25:00.123456Z")
        StubURLProtocol.responses["/client/v4/accounts/acc/builds/builds/latest"] = envelope(#"{"builds": {"t1": \#(done)}}"#)

        let second = try await provider.fetchDeployments(preferences: preferences)

        XCTAssertEqual(second.map(\.state), [.error, .ready])
        XCTAssertEqual(StubURLProtocol.requestCounts["/client/v4/accounts/acc/builds/workers/t1/builds"], 1)
        XCTAssertEqual(StubURLProtocol.requestCounts["/client/v4/accounts/acc/workers/scripts"], 1, "Worker list is cached")
    }

    func testShowsLatestBuildWhenItsHistoryFailsToLoad() async throws {
        let ready = build(uuid: "b1", created: "2026-10-02T17:00:00Z")
        StubURLProtocol.responses["/client/v4/accounts/acc/builds/builds/latest"] = envelope(#"{"builds": {"t1": \#(ready)}}"#)
        StubURLProtocol.responses["/client/v4/accounts/acc/builds/workers/t1/builds"] = envelope("[\(ready)]")
        _ = try await provider.fetchDeployments(preferences: preferences)

        // A newer build fails, and fetching the Worker's history fails too.
        let failed = build(uuid: "b2", outcome: "fail", created: "2026-10-02T18:00:00Z")
        StubURLProtocol.responses["/client/v4/accounts/acc/builds/builds/latest"] = envelope(#"{"builds": {"t1": \#(failed)}}"#)
        StubURLProtocol.responses["/client/v4/accounts/acc/builds/workers/t1/builds"] = (500, #"{"success": false, "errors": [{"message": "Internal error"}]}"#)

        let deployments = try await provider.fetchDeployments(preferences: preferences)

        XCTAssertEqual(deployments.map(\.id), ["b2", "b1"])
        XCTAssertEqual(deployments.map(\.state), [.error, .ready])
    }

    func testChangingTheTokenClearsCachedAccountsAndWorkers() async throws {
        StubURLProtocol.responses["/client/v4/accounts/acc/builds/builds/latest"] = envelope(#"{"builds": {}}"#)
        _ = try await provider.fetchDeployments(preferences: preferences)

        preferences.cloudflareToken = "other-token"
        _ = try await provider.fetchDeployments(preferences: preferences)

        XCTAssertEqual(StubURLProtocol.requestCounts["/client/v4/accounts"], 2)
        XCTAssertEqual(StubURLProtocol.requestCounts["/client/v4/accounts/acc/workers/scripts"], 2)
    }

    func testMapsBuildStatesAndSkipsSkippedBuilds() throws {
        let cases: [(String, String?, Deployment.State?)] = [
            ("queued", nil, .queued),
            ("initializing", nil, .building),
            ("running", nil, .building),
            ("stopped", "success", .ready),
            ("stopped", "fail", .error),
            ("stopped", "terminated", .error),
            ("stopped", "cancelled", .canceled),
            ("stopped", "skipped", nil),
            ("something_new", nil, .unknown),
        ]
        for (status, outcome, expected) in cases {
            let deployment = try decodeBuild(build(uuid: "b", status: status, outcome: outcome))
                .asDeployment(workerName: "w", accountId: "acc")
            XCTAssertEqual(deployment?.state, expected, "\(status)/\(outcome ?? "nil")")
        }
    }

    func testPreviewBuildsAreMarkedAsPreview() throws {
        let preview = try decodeBuild(build(uuid: "b", deployCommand: "npx wrangler versions upload"))
        XCTAssertEqual(preview.asDeployment(workerName: "w", accountId: "acc")?.target, .preview)
    }

    func testReportsCloudflareErrorMessages() async {
        StubURLProtocol.responses["/client/v4/accounts/acc/builds/builds/latest"] = (
            403, #"{"success": false, "errors": [{"code": 10000, "message": "Authentication error"}], "result": null}"#
        )

        do {
            _ = try await provider.fetchDeployments(preferences: preferences)
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "Cloudflare API error (403): Authentication error. Workers Builds requires a user API token with Workers Builds Configuration: Read."
            )
        }
    }

    // MARK: - Fixtures

    private func envelope(_ result: String) -> (Int, String) {
        (200, #"{"success": true, "errors": [], "messages": [], "result": \#(result)}"#)
    }

    private func build(
        uuid: String,
        status: String = "stopped",
        outcome: String? = "success",
        created: String = "2026-10-02T18:25:00Z",
        deployCommand: String = "npx wrangler deploy"
    ) -> String {
        let outcomeJSON = outcome.map { "\"\($0)\"" } ?? "null"
        let stopped = status == "stopped" ? "\"2026-10-02T18:26:00Z\"" : "null"
        return """
        {
          "build_uuid": "\(uuid)", "status": "\(status)", "build_outcome": \(outcomeJSON),
          "created_on": "\(created)", "initializing_on": "\(created)", "running_on": null,
          "stopped_on": \(stopped), "pull_request": null,
          "build_trigger_metadata": {
            "branch": "main", "commit_hash": "abc123", "commit_message": "Ship it",
            "deploy_command": "\(deployCommand)", "build_trigger_source": "push", "author": "someone"
          },
          "trigger": { "external_script_id": "t1", "trigger_name": "Deploy" }
        }
        """
    }

    private func decodeBuild(_ json: String) throws -> CloudflareBuild {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            CloudflareClient.parseTimestamp(try decoder.singleValueContainer().decode(String.self))!
        }
        return try decoder.decode(CloudflareBuild.self, from: Data(json.utf8))
    }
}

/// Serves canned responses keyed by URL path and records requests.
final class StubURLProtocol: URLProtocol {
    static var responses: [String: (Int, String)] = [:]
    static var requestCounts: [String: Int] = [:]
    static var requestedQueries: [String: [String]] = [:]
    private static let lock = NSLock()

    static func reset() {
        lock.withLock {
            responses = [:]
            requestCounts = [:]
            requestedQueries = [:]
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let (status, body) = Self.lock.withLock { () -> (Int, String) in
            Self.requestCounts[url.path, default: 0] += 1
            Self.requestedQueries[url.path, default: []].append(url.query ?? "")
            return Self.responses[url.path] ?? (404, #"{"success": false, "errors": [{"message": "Not stubbed"}]}"#)
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
