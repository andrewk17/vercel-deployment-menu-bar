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

        let teamIds = preferences.teamIdList
        let projectNames = preferences.projectNameList
        let singleProjectName = preferences.singleProjectName
        let hasMultipleProjects = projectNames.count > 1

        // Preserve strict error behavior for the single-team case.
        if teamIds.count == 1 {
            let resolvedTeamId = normalizedTeamID(from: teamIds[0])
            if hasMultipleProjects {
                let deployments = try await fetchDeploymentsForProjects(
                    token: preferences.vercelToken,
                    teamId: resolvedTeamId,
                    projectNames: projectNames,
                    limit: 100
                )
                return mergeAndSortDeployments(deployments)
            }

            return try await fetchDeployments(
                token: preferences.vercelToken,
                teamId: resolvedTeamId,
                projectName: singleProjectName,
                limit: 100
            )
        }

        // If team IDs are explicitly provided, fetch only those teams.
        if !teamIds.isEmpty {
            if hasMultipleProjects {
                let deployments = await fetchDeploymentsForTeamsAndProjects(
                    token: preferences.vercelToken,
                    teamIds: teamIds,
                    projectNames: projectNames,
                    limit: 100
                )
                return mergeAndSortDeployments(deployments)
            } else {
                let deployments = await fetchDeploymentsForTeams(
                    token: preferences.vercelToken,
                    teamIds: teamIds,
                    projectName: singleProjectName,
                    limit: 100
                )
                return mergeAndSortDeployments(deployments)
            }
        }

        // Otherwise, attempt to fetch across user + teams matching Raycast behavior.
        do {
            let teams = try await fetchTeams(token: preferences.vercelToken)
            if hasMultipleProjects {
                async let personalDeployments: [Deployment] = fetchDeploymentsForProjects(
                    token: preferences.vercelToken,
                    teamId: nil,
                    projectNames: projectNames,
                    limit: 100
                )

                async let teamDeployments: [Deployment] = fetchDeploymentsForTeamsAndProjects(
                    token: preferences.vercelToken,
                    teamIds: teams.map(\.id),
                    projectNames: projectNames,
                    limit: 100
                )

                let combined = try await personalDeployments + teamDeployments
                return mergeAndSortDeployments(combined)
            } else {
                async let personalDeployments: [Deployment] = fetchDeployments(
                    token: preferences.vercelToken,
                    teamId: nil,
                    projectName: singleProjectName,
                    limit: 100
                )

                async let teamDeployments: [Deployment] = fetchDeploymentsForTeams(
                    token: preferences.vercelToken,
                    teamIds: teams.map(\.id),
                    projectName: singleProjectName,
                    limit: 100
                )

                let combined = try await personalDeployments + teamDeployments
                return mergeAndSortDeployments(combined)
            }
        } catch {
            // If team fetch fails (scoped token), fallback to fetching without team.
            if hasMultipleProjects {
                let deployments = try await fetchDeploymentsForProjects(
                    token: preferences.vercelToken,
                    teamId: nil,
                    projectNames: projectNames,
                    limit: 100
                )
                return mergeAndSortDeployments(deployments)
            } else {
                return try await fetchDeployments(
                    token: preferences.vercelToken,
                    teamId: nil,
                    projectName: singleProjectName,
                    limit: 100
                )
            }
        }
    }

    private func fetchDeploymentsForProjects(
        token: String,
        teamId: String?,
        projectNames: [String],
        limit: Int
    ) async throws -> [Deployment] {
        let outcome = await withTaskGroup(
            of: Result<[Deployment], Error>.self,
            returning: (deployments: [Deployment], successCount: Int, firstError: Error?).self
        ) { group in
            for projectName in projectNames {
                group.addTask {
                    do {
                        let deployments = try await self.fetchDeployments(
                            token: token,
                            teamId: teamId,
                            projectName: projectName,
                            limit: limit
                        )
                        return .success(deployments)
                    } catch {
                        return .failure(error)
                    }
                }
            }

            var all: [Deployment] = []
            var successCount = 0
            var firstError: Error?

            for await result in group {
                switch result {
                case let .success(deployments):
                    successCount += 1
                    all.append(contentsOf: deployments)
                case let .failure(error):
                    if firstError == nil {
                        firstError = error
                    }
                }
            }
            return (all, successCount, firstError)
        }

        if outcome.successCount == 0, let firstError = outcome.firstError {
            throw firstError
        }

        return outcome.deployments
    }

    private func fetchDeploymentsForTeams(
        token: String,
        teamIds: [String],
        projectName: String?,
        limit: Int
    ) async -> [Deployment] {
        await withTaskGroup(of: [Deployment].self) { group in
            for teamId in teamIds {
                group.addTask {
                    do {
                        return try await self.fetchDeployments(
                            token: token,
                            teamId: self.normalizedTeamID(from: teamId),
                            projectName: projectName,
                            limit: limit
                        )
                    } catch {
                        return []
                    }
                }
            }

            var all: [Deployment] = []
            for await deployments in group {
                all.append(contentsOf: deployments)
            }
            return all
        }
    }

    private func fetchDeploymentsForTeamsAndProjects(
        token: String,
        teamIds: [String],
        projectNames: [String],
        limit: Int
    ) async -> [Deployment] {
        await withTaskGroup(of: [Deployment].self) { group in
            for teamId in teamIds {
                for projectName in projectNames {
                    group.addTask {
                        do {
                            return try await self.fetchDeployments(
                                token: token,
                                teamId: self.normalizedTeamID(from: teamId),
                                projectName: projectName,
                                limit: limit
                            )
                        } catch {
                            return []
                        }
                    }
                }
            }

            var all: [Deployment] = []
            for await deployments in group {
                all.append(contentsOf: deployments)
            }
            return all
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

    private func mergeAndSortDeployments(_ deployments: [Deployment]) -> [Deployment] {
        var byUID: [String: Deployment] = [:]
        for deployment in deployments {
            if let current = byUID[deployment.uid] {
                if deployment.created > current.created {
                    byUID[deployment.uid] = deployment
                }
            } else {
                byUID[deployment.uid] = deployment
            }
        }
        return byUID.values.sorted { $0.created > $1.created }
    }

    private func normalizedTeamID(from rawTeamID: String) -> String? {
        let trimmed = rawTeamID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed == Preferences.personalScopeIdentifier {
            return nil
        }
        return trimmed
    }
}
