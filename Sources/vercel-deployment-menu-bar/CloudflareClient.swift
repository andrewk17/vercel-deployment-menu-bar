import Foundation

struct CloudflareAccount: Decodable {
    let id: String
    let name: String
}

struct CloudflareWorker: Decodable {
    /// The Worker's name.
    let id: String
    /// Immutable script tag; the Builds API calls this `external_script_id`.
    let tag: String
}

/// A Workers Builds build.
struct CloudflareBuild: Decodable {
    enum Status: String, Decodable {
        case queued, initializing, running, stopped, unknown

        init(from decoder: Decoder) throws {
            self = Status(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }
    }

    enum Outcome: String, Decodable {
        case success, fail, skipped, cancelled, terminated, unknown

        init(from decoder: Decoder) throws {
            self = Outcome(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }
    }

    struct TriggerMetadata: Decodable {
        let branch: String?
        let commitMessage: String?
        let deployCommand: String?
    }

    struct PullRequest: Decodable {}

    let buildUuid: String
    let status: Status
    let buildOutcome: Outcome?
    let createdOn: Date
    let initializingOn: Date?
    let runningOn: Date?
    let stoppedOn: Date?
    let buildTriggerMetadata: TriggerMetadata?
    let pullRequest: PullRequest?

    var isFinished: Bool {
        status == .stopped
    }
}

/// Client for the Cloudflare account, Workers script, and Workers Builds APIs.
/// The Builds endpoints require a user-scoped API token.
final class CloudflareClient {
    /// The latest-builds endpoint accepts at most this many script tags per request.
    static let latestBuildsBatchSize = 20

    private let http: HTTPClient

    init(session: URLSession = .shared) {
        http = HTTPClient(
            service: "Cloudflare",
            baseURL: "https://api.cloudflare.com/client/v4",
            decoder: Self.makeDecoder(),
            session: session,
            errorMessage: Self.errorMessage(from:)
        )
    }

    func accounts(token: String) async throws -> [CloudflareAccount] {
        try await get("/accounts", query: ["per_page": "50"], token: token)
    }

    func workers(token: String, accountId: String) async throws -> [CloudflareWorker] {
        try await get("/accounts/\(accountId)/workers/scripts", token: token)
    }

    /// The most recent build for each Worker that has one, keyed by script tag.
    func latestBuilds(token: String, accountId: String, scriptTags: [String]) async throws -> [String: CloudflareBuild] {
        var builds: [String: CloudflareBuild] = [:]
        for batch in scriptTags.chunked(into: Self.latestBuildsBatchSize) {
            let response: LatestBuilds
            do {
                response = try await get(
                    "/accounts/\(accountId)/builds/builds/latest",
                    query: ["external_script_ids": batch.joined(separator: ",")],
                    token: token
                )
            } catch let APIError.invalidResponse(service, status, message) where status == 401 || status == 403 {
                // Account-scoped tokens can list Workers but are rejected here.
                throw APIError.invalidResponse(
                    service: service,
                    status: status,
                    message: "\(message). Workers Builds requires a user API token with Workers Builds Configuration: Read."
                )
            }
            builds.merge(response.builds ?? [:]) { _, new in new }
        }
        return builds
    }

    /// Recent builds for one Worker, newest first.
    func builds(token: String, accountId: String, scriptTag: String, limit: Int) async throws -> [CloudflareBuild] {
        let builds: [CloudflareBuild] = try await get(
            "/accounts/\(accountId)/builds/workers/\(scriptTag)/builds",
            query: ["per_page": "\(limit)"],
            token: token
        )
        return builds.sorted { $0.createdOn > $1.createdOn }
    }

    private func get<Result: Decodable>(
        _ path: String,
        query: [String: String?] = [:],
        token: String
    ) async throws -> Result {
        let envelope: Envelope<Result> = try await http.get(path, query: query, token: token)
        guard let result = envelope.result else {
            throw APIError.decodingFailure(service: "Cloudflare")
        }
        return result
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            guard let date = parseTimestamp(value) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid date: \(value)"))
            }
            return date
        }
        return decoder
    }

    /// Cloudflare timestamps are ISO 8601, with or without fractional seconds.
    static func parseTimestamp(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private static func errorMessage(from data: Data) -> String? {
        let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
        let messages = envelope?.errors.map(\.message) ?? []
        return messages.isEmpty ? String(data: data, encoding: .utf8) : messages.joined(separator: "; ")
    }
}

private struct Envelope<Result: Decodable>: Decodable {
    let result: Result?
}

private struct ErrorEnvelope: Decodable {
    struct Message: Decodable {
        let message: String
    }

    let errors: [Message]
}

private struct LatestBuilds: Decodable {
    let builds: [String: CloudflareBuild]?
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
