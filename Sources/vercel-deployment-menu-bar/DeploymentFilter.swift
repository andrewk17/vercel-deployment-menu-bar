import Foundation

/// Applies the user's display preferences to fetched deployments.
struct DeploymentFilter {
    let preferences: Preferences

    func apply(to deployments: [VercelDeployment], now: Date = Date()) -> [VercelDeployment] {
        let filtered = deployments
            .filter(matches)
            .sorted { $0.created > $1.created }

        if let limit = preferences.limitByCount, limit > 0 {
            return Array(filtered.prefix(limit))
        }
        if let hours = preferences.limitByHours, hours > 0 {
            let cutoff = now.addingTimeInterval(TimeInterval(-hours * 3600))
            return filtered.filter { $0.createdDate >= cutoff }
        }
        return filtered
    }

    private func matches(_ deployment: VercelDeployment) -> Bool {
        let projectNames = preferences.normalizedProjectNameSet
        if !projectNames.isEmpty, !projectNames.contains(deployment.name.lowercased()) {
            return false
        }

        guard showsState(deployment.state) else { return false }

        switch deployment.target?.lowercased() {
        case "production" where !preferences.showProduction:
            return false
        case "preview" where !preferences.showPreview:
            return false
        default:
            break
        }

        let branches = preferences.branchList
        if !branches.isEmpty {
            guard let branch = deployment.branch?.lowercased(), branches.contains(branch) else {
                return false
            }
        }

        return true
    }

    private func showsState(_ state: VercelDeployment.State) -> Bool {
        switch state {
        case .ready: return preferences.showReady
        case .building: return preferences.showBuilding
        case .error: return preferences.showError
        case .queued: return preferences.showQueued
        case .canceled: return preferences.showCanceled
        case .unknown: return true
        }
    }
}
