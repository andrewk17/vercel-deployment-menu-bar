import Foundation

/// A project's deployments, for the menu's Projects section.
struct ProjectSummary: Equatable {
    static let maxProjects = 10
    static let historyDepth = 5

    let provider: Deployment.Provider
    let name: String
    /// Newest first.
    let deployments: [Deployment]

    /// The latest production deployment, since that's what the live site runs, or the
    /// latest of any kind when there's no production deployment.
    var headline: Deployment {
        deployments.first { $0.target == .production } ?? deployments[0]
    }

    /// Groups newest-first deployments by project, ordered by each project's latest
    /// activity and capped at `maxProjects`.
    static func summaries(from deployments: [Deployment]) -> [ProjectSummary] {
        struct Key: Hashable {
            let provider: Deployment.Provider
            let name: String
        }

        var order: [Key] = []
        var grouped: [Key: [Deployment]] = [:]
        for deployment in deployments {
            let key = Key(provider: deployment.provider, name: deployment.projectName.lowercased())
            if grouped[key] == nil {
                order.append(key)
            }
            grouped[key, default: []].append(deployment)
        }

        return order.prefix(maxProjects).map { key in
            let projectDeployments = grouped[key]!
            return ProjectSummary(provider: key.provider, name: projectDeployments[0].projectName, deployments: projectDeployments)
        }
    }
}
