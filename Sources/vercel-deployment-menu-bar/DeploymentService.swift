import Foundation

final class DeploymentService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchAllDeployments(preferences: Preferences) async throws -> [Deployment] {
        guard preferences.hasToken else {
            throw APIError.missingToken
        }

        // If team is explicitly provided, fetch only for that team.
        if !preferences.teamId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return try await fetchDeployments(
                token: preferences.vercelToken,
                teamId: preferences.teamId,
                projectName: emptyToNil(preferences.projectName),
                limit: 100
            )
        }

        // Otherwise, attempt to fetch across user + teams matching Raycast behavior.
        do {
            let teams = try await fetchTeams(token: preferences.vercelToken)
            async let personalDeployments: [Deployment] = fetchDeployments(
                token: preferences.vercelToken,
                teamId: nil,
                projectName: emptyToNil(preferences.projectName),
                limit: 100
            )

            let teamDeployments = try await withThrowingTaskGroup(of: [Deployment].self) { group -> [[Deployment]] in
                for team in teams {
                    group.addTask {
                        do {
                            return try await self.fetchDeployments(
                                token: preferences.vercelToken,
                                teamId: team.id,
                                projectName: emptyToNil(preferences.projectName),
                                limit: 100
                            )
                        } catch {
                            return []
                        }
                    }
                }

                var all: [[Deployment]] = []
                for try await deployments in group {
                    all.append(deployments)
                }
                return all
            }

            let combined = try await personalDeployments + teamDeployments.flatMap { $0 }
            return combined.sorted { $0.created > $1.created }
        } catch {
            // If team fetch fails (scoped token), fallback to fetching without team.
            return try await fetchDeployments(
                token: preferences.vercelToken,
                teamId: nil,
                projectName: emptyToNil(preferences.projectName),
                limit: 100
            )
        }
    }

    private func fetchTeams(token: String) async throws -> [Team] {
        guard let url = URL(string: "https://api.vercel.com/v2/teams") else {
            return []
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse(status: -1, message: "No response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.invalidResponse(status: httpResponse.statusCode, message: message)
        }

        guard let decoded = try? JSONDecoder().decode(TeamsResponse.self, from: data) else {
            throw APIError.decodingFailure
        }
        return decoded.teams
    }

    private func fetchDeployments(
        token: String,
        teamId: String?,
        projectName: String?,
        limit: Int
    ) async throws -> [Deployment] {
        var components = URLComponents(string: "https://api.vercel.com/v6/deployments")!
        var queryItems = [
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        if let teamId, !teamId.isEmpty {
            queryItems.append(URLQueryItem(name: "teamId", value: teamId))
        }
        if let projectName, !projectName.isEmpty {
            queryItems.append(URLQueryItem(name: "app", value: projectName))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            return []
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse(status: -1, message: "No response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.invalidResponse(status: httpResponse.statusCode, message: message)
        }

        guard let decoded = try? JSONDecoder().decode(DeploymentsResponse.self, from: data) else {
            throw APIError.decodingFailure
        }
        return decoded.deployments
    }
}

private func emptyToNil(_ string: String) -> String? {
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
