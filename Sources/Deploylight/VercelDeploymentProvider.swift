import Foundation

final class VercelDeploymentProvider: DeploymentProvider {
    let kind = Deployment.Provider.vercel
    private let client: VercelClient

    init(client: VercelClient = VercelClient()) {
        self.client = client
    }

    func isConfigured(_ preferences: Preferences) -> Bool {
        preferences.hasVercelToken
    }

    /// Fetches deployments for every configured (scope, project) pair.
    func fetchDeployments(preferences: Preferences) async throws -> [Deployment] {
        let token = preferences.vercelToken
        let scopes = await resolveScopes(preferences: preferences)
        let projects: [String?] = preferences.projectNameList.isEmpty ? [nil] : preferences.projectNameList
        let requests = scopes.flatMap { scope in projects.map { (teamId: scope, projectName: $0) } }

        let deployments = try await gatherConcurrently(requests) { request in
            try await self.client.deployments(token: token, teamId: request.teamId, projectName: request.projectName)
        }

        var seen: Set<String> = []
        return deployments
            .filter { seen.insert($0.uid).inserted }
            .map(\.asDeployment)
    }

    /// Team IDs to query, where `nil` is the personal scope. Uses the configured scopes when set,
    /// otherwise the personal scope plus every team the token can list.
    private func resolveScopes(preferences: Preferences) async -> [String?] {
        let configured = preferences.teamIdList
        if !configured.isEmpty {
            return configured.map { $0 == Preferences.personalScopeIdentifier ? nil : $0 }
        }

        // Team-scoped tokens can't list teams; fall back to the token's default scope.
        let teams = (try? await client.teams(token: preferences.vercelToken)) ?? []
        return [nil] + teams.map(\.id)
    }
}
