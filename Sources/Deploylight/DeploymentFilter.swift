import Foundation

/// Applies the user's display preferences to fetched deployments. Scope, project, and
/// Worker selection happen in the providers, which only fetch what's selected.
struct DeploymentFilter {
    let preferences: Preferences

    func apply(to deployments: [Deployment], now: Date = Date()) -> [Deployment] {
        limit(matching(deployments), now: now)
    }

    /// Deployments that pass the type, state, and branch filters, newest first.
    func matching(_ deployments: [Deployment]) -> [Deployment] {
        deployments
            .filter(matches)
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Applies the time window, then the count limit, to newest-first deployments.
    func limit(_ filtered: [Deployment], now: Date = Date()) -> [Deployment] {
        var limited = filtered
        if let hours = preferences.limitByHours, hours > 0 {
            let cutoff = now.addingTimeInterval(TimeInterval(-hours * 3600))
            limited = limited.filter { $0.createdAt >= cutoff }
        }
        if let count = preferences.limitByCount, count > 0 {
            limited = Array(limited.prefix(count))
        }
        guard limited.count < filtered.count else { return filtered }

        // In-progress builds stay past the limits, so the status bar and faster polling
        // still track a build that newer, finished deployments have pushed out.
        let kept = Set(limited.map(\.id))
        return filtered.filter { kept.contains($0.id) || $0.state.isActive }
    }

    private func matches(_ deployment: Deployment) -> Bool {
        guard showsState(deployment.state) else { return false }

        switch deployment.target {
        case .production where !preferences.showProduction:
            return false
        case .preview where !preferences.showPreview:
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

    private func showsState(_ state: Deployment.State) -> Bool {
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
