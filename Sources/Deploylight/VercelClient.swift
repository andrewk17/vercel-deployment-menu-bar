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
    var asDeployment: Deployment {
        let createdAt = Date(timeIntervalSince1970: created / 1000)
        let ref = gitSource?.ref ?? meta?.githubCommitRef

        return Deployment(
            id: uid,
            provider: .vercel,
            projectName: name,
            state: deploymentState,
            // Vercel reports preview deployments with a null target.
            target: target?.lowercased() == "production" ? .production : .preview,
            branch: ref?.isEmpty == false ? ref : nil,
            commitMessage: meta?.githubCommitMessage,
            createdAt: createdAt,
            buildStartedAt: buildingAt.map { Date(timeIntervalSince1970: $0 / 1000) } ?? createdAt,
            finishedAt: ready.map { Date(timeIntervalSince1970: $0 / 1000) },
            link: link
        )
    }

    private var deploymentState: Deployment.State {
        switch state {
        case .building: return .building
        case .error: return .error
        case .ready: return .ready
        case .queued: return .queued
        case .canceled: return .canceled
        case .unknown: return .unknown
        }
    }

    /// The inspector page when available, otherwise the deployment itself.
    private var link: URL? {
        if let inspectorUrl, let url = URL(string: inspectorUrl.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme != nil {
            return url
        }
        return URL(string: url.hasPrefix("http://") || url.hasPrefix("https://") ? url : "https://\(url)")
    }
}

final class VercelClient {
    private static let pageSize = 100

    private let http: HTTPClient

    init(session: URLSession = .shared) {
        http = HTTPClient(
            service: "Vercel",
            baseURL: "https://api.vercel.com",
            session: session,
            errorMessage: Self.errorMessage(from:)
        )
    }

    /// Vercel errors look like `{"error": {"code": "forbidden", "message": "..."}}`.
    static func errorMessage(from data: Data) -> String? {
        struct ErrorResponse: Decodable {
            struct Detail: Decodable {
                let message: String?
            }
            let error: Detail
        }
        if let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error.message, !message.isEmpty {
            return message
        }
        return String(data: data, encoding: .utf8)
    }

    func teams(token: String) async throws -> [VercelTeam] {
        let response: TeamsResponse = try await http.get("/v2/teams", token: token)
        return response.teams
    }

    func projects(token: String, teamId: String?) async throws -> [VercelProject] {
        let response: ProjectsResponse = try await http.get(
            "/v9/projects",
            query: ["limit": "\(Self.pageSize)", "teamId": teamId],
            token: token
        )
        return response.projects
    }

    func deployments(token: String, teamId: String?, projectName: String?) async throws -> [VercelDeployment] {
        let response: DeploymentsResponse = try await http.get(
            "/v6/deployments",
            query: ["limit": "\(Self.pageSize)", "teamId": teamId, "app": projectName],
            token: token
        )
        return response.deployments
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
