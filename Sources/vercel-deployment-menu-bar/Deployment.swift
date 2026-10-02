import Foundation

/// A deployment from any provider, normalized for display.
struct Deployment: Equatable {
    enum Provider: String, CaseIterable {
        case vercel = "Vercel"
        case cloudflare = "Cloudflare"
    }

    enum State: Hashable {
        case queued
        case building
        case ready
        case error
        case canceled
        case unknown

        var isActive: Bool {
            self == .queued || self == .building
        }
    }

    enum Target: String {
        case production = "Production"
        case preview = "Preview"
    }

    let id: String
    let provider: Provider
    let projectName: String
    let state: State
    let target: Target?
    let branch: String?
    let commitMessage: String?
    let createdAt: Date
    let buildStartedAt: Date
    let finishedAt: Date?
    let link: URL?
}

protocol DeploymentProvider {
    var kind: Deployment.Provider { get }
    func isConfigured(_ preferences: Preferences) -> Bool
    func fetchDeployments(preferences: Preferences) async throws -> [Deployment]
}

struct DeploymentSnapshot {
    var deployments: [Deployment] = []
    var errors: [Deployment.Provider: Error] = [:]
}

/// Fetches from every configured provider concurrently. A failing provider is reported
/// in `errors` without hiding deployments from the others.
final class DeploymentService {
    private let providers: [DeploymentProvider]

    init(providers: [DeploymentProvider] = [VercelDeploymentProvider(), CloudflareBuildsProvider()]) {
        self.providers = providers
    }

    func configuredProviders(_ preferences: Preferences) -> [Deployment.Provider] {
        providers.filter { $0.isConfigured(preferences) }.map(\.kind)
    }

    func fetch(preferences: Preferences) async -> DeploymentSnapshot {
        let configured = providers.filter { $0.isConfigured(preferences) }

        return await withTaskGroup(of: (Deployment.Provider, Result<[Deployment], Error>).self) { group in
            for provider in configured {
                group.addTask {
                    do {
                        return (provider.kind, .success(try await provider.fetchDeployments(preferences: preferences)))
                    } catch {
                        return (provider.kind, .failure(error))
                    }
                }
            }

            var snapshot = DeploymentSnapshot()
            for await (kind, result) in group {
                switch result {
                case let .success(deployments):
                    snapshot.deployments.append(contentsOf: deployments)
                case let .failure(error):
                    snapshot.errors[kind] = error
                }
            }
            snapshot.deployments.sort { $0.createdAt > $1.createdAt }
            return snapshot
        }
    }
}
