import Foundation

/// Reports Workers Builds (Cloudflare's git-connected CI) as deployments.
///
/// Workers deployed directly with `wrangler deploy` have no builds and don't appear.
/// Each refresh asks for the latest build of every Worker in batches, and only
/// re-downloads a Worker's build history when that changes.
actor CloudflareBuildsProvider: DeploymentProvider {
    nonisolated let kind = Deployment.Provider.cloudflare

    private static let listTTL: TimeInterval = 5 * 60
    private static let historyDepth = 10

    private struct Cached<Value> {
        let value: Value
        let fetchedAt: Date

        var isFresh: Bool {
            Date().timeIntervalSince(fetchedAt) < CloudflareBuildsProvider.listTTL
        }
    }

    private let client: CloudflareClient
    /// The token the caches below were filled with. They're cleared when it changes.
    private var cacheToken: String?
    private var accountIds: Cached<[String]>?
    private var workersByAccount: [String: Cached<[CloudflareWorker]>] = [:]
    /// Recent builds per script tag, newest first.
    private var historyByTag: [String: [CloudflareBuild]] = [:]

    init(client: CloudflareClient = CloudflareClient()) {
        self.client = client
    }

    nonisolated func isConfigured(_ preferences: Preferences) -> Bool {
        preferences.hasCloudflareToken
    }

    func fetchDeployments(preferences: Preferences) async throws -> [Deployment] {
        let token = preferences.cloudflareToken
        if token != cacheToken {
            cacheToken = token
            accountIds = nil
            workersByAccount = [:]
            historyByTag = [:]
        }

        let accounts = try await resolveAccountIds(preferences: preferences)
        let workerNames = Set(preferences.cloudflareWorkerList.map { $0.lowercased() })

        return try await gatherConcurrently(accounts) { accountId in
            try await self.deployments(token: token, accountId: accountId, workerNames: workerNames)
        }
    }

    private func deployments(token: String, accountId: String, workerNames: Set<String>) async throws -> [Deployment] {
        let workers = try await workers(token: token, accountId: accountId)
            .filter { workerNames.isEmpty || workerNames.contains($0.id.lowercased()) }
        let latest = try await client.latestBuilds(token: token, accountId: accountId, scriptTags: workers.map(\.tag))

        var stale: [String] = []
        for (tag, build) in latest {
            if needsHistoryRefresh(tag: tag, latest: build) {
                stale.append(tag)
            } else if token == cacheToken, let index = historyByTag[tag]?.firstIndex(where: { $0.buildUuid == build.buildUuid }) {
                historyByTag[tag]?[index] = build
            }
        }

        if !stale.isEmpty {
            let histories = (try? await gatherConcurrently(stale) { tag -> [(String, [CloudflareBuild])] in
                let builds = try await self.client.builds(token: token, accountId: accountId, scriptTag: tag, limit: Self.historyDepth)
                return [(tag, builds)]
            }) ?? []
            if token == cacheToken {
                for (tag, builds) in histories {
                    historyByTag[tag] = builds
                }
            }
        }

        return workers.flatMap { worker in
            var builds = historyByTag[worker.tag] ?? []
            // When a history refresh fails, still show the latest build ahead of the older
            // cached ones. The cache stays stale, so the next refresh retries.
            if let build = latest[worker.tag], !builds.contains(where: { $0.buildUuid == build.buildUuid }) {
                builds.insert(build, at: 0)
            }
            return builds.compactMap { build in
                build.asDeployment(workerName: worker.id, accountId: accountId)
            }
        }
    }

    /// The cached history is stale when it doesn't contain the latest build, or when an older
    /// build is still unfinished and its final state hasn't been seen.
    private func needsHistoryRefresh(tag: String, latest: CloudflareBuild) -> Bool {
        guard let history = historyByTag[tag], history.contains(where: { $0.buildUuid == latest.buildUuid }) else {
            return true
        }
        return history.contains { $0.buildUuid != latest.buildUuid && !$0.isFinished }
    }

    private func resolveAccountIds(preferences: Preferences) async throws -> [String] {
        let configured = preferences.cloudflareAccountIdList
        if !configured.isEmpty {
            return configured
        }
        if let accountIds, accountIds.isFresh {
            return accountIds.value
        }
        let token = preferences.cloudflareToken
        let ids = try await client.accounts(token: token).map(\.id)
        if token == cacheToken {
            accountIds = Cached(value: ids, fetchedAt: Date())
        }
        return ids
    }

    private func workers(token: String, accountId: String) async throws -> [CloudflareWorker] {
        if let cached = workersByAccount[accountId], cached.isFresh {
            return cached.value
        }
        let workers = try await client.workers(token: token, accountId: accountId)
        if token == cacheToken {
            workersByAccount[accountId] = Cached(value: workers, fetchedAt: Date())
        }
        return workers
    }
}

extension CloudflareBuild {
    /// Skipped builds (for example, no watched paths changed) never deploy and are omitted.
    func asDeployment(workerName: String, accountId: String) -> Deployment? {
        let state: Deployment.State
        switch status {
        case .queued:
            state = .queued
        case .initializing, .running:
            state = .building
        case .stopped:
            switch buildOutcome {
            case .success: state = .ready
            case .fail, .terminated: state = .error
            case .cancelled: state = .canceled
            case .skipped: return nil
            case .unknown, nil: state = .unknown
            }
        case .unknown:
            state = .unknown
        }

        // Non-production branches run `wrangler versions upload` by default, which creates
        // a preview version instead of deploying.
        let isPreview = pullRequest != nil
            || buildTriggerMetadata?.deployCommand?.contains("versions upload") == true
        let branch = buildTriggerMetadata?.branch

        return Deployment(
            id: buildUuid,
            provider: .cloudflare,
            projectName: workerName,
            state: state,
            target: isPreview ? .preview : .production,
            branch: branch?.isEmpty == false ? branch : nil,
            commitMessage: buildTriggerMetadata?.commitMessage,
            createdAt: createdOn,
            buildStartedAt: initializingOn ?? runningOn ?? createdOn,
            finishedAt: stoppedOn,
            link: URL(string: "https://dash.cloudflare.com/\(accountId)/workers/services/view/\(workerName)/production/builds/\(buildUuid)")
        )
    }
}
