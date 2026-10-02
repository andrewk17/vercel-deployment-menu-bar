import Foundation

struct VercelTeam: Decodable {
    let id: String
    let slug: String
    let name: String
}

struct VercelProject: Decodable {
    let id: String
    let name: String
}

struct VercelDeployment: Decodable {
    enum State: String, Decodable {
        case building = "BUILDING"
        case error = "ERROR"
        case ready = "READY"
        case queued = "QUEUED"
        case canceled = "CANCELED"
        case unknown

        init(from decoder: Decoder) throws {
            let rawValue = try decoder.singleValueContainer().decode(String.self)
            self = State(rawValue: rawValue) ?? .unknown
        }
    }

    struct Meta: Decodable {
        let githubCommitMessage: String?
        let githubCommitRef: String?
    }

    struct GitSource: Decodable {
        let ref: String?
    }

    let uid: String
    let name: String
    let url: String
    let inspectorUrl: String?
    /// Milliseconds since 1970.
    let created: TimeInterval
    let state: State
    let ready: TimeInterval?
    let buildingAt: TimeInterval?
    let target: String?
    let meta: Meta?
    let gitSource: GitSource?
}

extension VercelDeployment {
    var createdDate: Date {
        Date(timeIntervalSince1970: created / 1000)
    }

    var readyDate: Date? {
        ready.map { Date(timeIntervalSince1970: $0 / 1000) }
    }

    var buildingAtDate: Date {
        Date(timeIntervalSince1970: (buildingAt ?? created) / 1000)
    }

    var branch: String? {
        let ref = gitSource?.ref ?? meta?.githubCommitRef
        return ref?.isEmpty == false ? ref : nil
    }

    var commitMessage: String? {
        meta?.githubCommitMessage
    }

    /// The inspector page when available, otherwise the deployment itself.
    var link: URL? {
        if let inspectorUrl, let url = URL(string: inspectorUrl.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme != nil {
            return url
        }
        return URL(string: url.hasPrefix("http://") || url.hasPrefix("https://") ? url : "https://\(url)")
    }
}

enum APIError: LocalizedError {
    case missingToken
    case invalidResponse(status: Int, message: String)
    case decodingFailure

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "Vercel token is missing. Please update Preferences."
        case let .invalidResponse(status, message):
            return "Vercel API error (\(status)): \(message)"
        case .decodingFailure:
            return "Failed to decode response from Vercel."
        }
    }
}

final class VercelClient {
    private static let baseURL = "https://api.vercel.com"
    private static let pageSize = 100

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func teams(token: String) async throws -> [VercelTeam] {
        let response: TeamsResponse = try await get("/v2/teams", token: token)
        return response.teams
    }

    func projects(token: String, teamId: String?) async throws -> [VercelProject] {
        let response: ProjectsResponse = try await get(
            "/v9/projects",
            query: ["limit": "\(Self.pageSize)", "teamId": teamId],
            token: token
        )
        return response.projects
    }

    func deployments(token: String, teamId: String?, projectName: String?) async throws -> [VercelDeployment] {
        let response: DeploymentsResponse = try await get(
            "/v6/deployments",
            query: ["limit": "\(Self.pageSize)", "teamId": teamId, "app": projectName],
            token: token
        )
        return response.deployments
    }

    private func get<Response: Decodable>(
        _ path: String,
        query: [String: String?] = [:],
        token: String
    ) async throws -> Response {
        var components = URLComponents(string: Self.baseURL + path)!
        let queryItems = query
            .compactMap { name, value in value.flatMap { $0.isEmpty ? nil : URLQueryItem(name: name, value: $0) } }
            .sorted { $0.name < $1.name }
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse(status: -1, message: "No response")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.invalidResponse(status: httpResponse.statusCode, message: message)
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw APIError.decodingFailure
        }
        return decoded
    }
}

private struct TeamsResponse: Decodable {
    let teams: [VercelTeam]
}

private struct ProjectsResponse: Decodable {
    let projects: [VercelProject]
}

private struct DeploymentsResponse: Decodable {
    let deployments: [VercelDeployment]
}
