import Combine
import Foundation

enum SelectionMode: String, CaseIterable, Identifiable {
    case all
    case selected

    var id: String { rawValue }
}

enum ConnectionStatus: Equatable {
    case notConnected
    case checking
    /// A short summary, such as "12 projects".
    case connected(String)
    case failed(String)

    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}

struct SelectionOption: Identifiable, Hashable {
    let id: String
    let title: String
    var subtitle: String?
    /// A saved selection the latest lookup didn't return.
    var isMissing = false
}

@MainActor
final class PreferencesViewModel: ObservableObject {
    @Published var vercelToken = ""
    @Published var gitBranches = ""
    @Published var showProduction = true
    @Published var showPreview = true
    @Published var showReady = true
    @Published var showBuilding = true
    @Published var showError = true
    @Published var showQueued = true
    @Published var showCanceled = true
    /// 0 means no limit.
    @Published var limitByCount = 0
    /// 0 means any time.
    @Published var limitByHours = 0
    @Published var refreshIntervalIdle = 15
    @Published var refreshIntervalBuilding = 2
    @Published var menuBarStyle = MenuBarStyle.auto
    @Published var timeFormat = TimeFormat.clock
    @Published var showProjects = true
    @Published var providerStyle = ProviderStyle.icon
    @Published var environmentStyle = EnvironmentStyle.badge

    @Published var cloudflareToken = ""
    @Published var cloudflareAccountMode = SelectionMode.all
    @Published var selectedCloudflareAccountIDs: Set<String> = []
    @Published var cloudflareWorkerMode = SelectionMode.all
    @Published var selectedCloudflareWorkers: Set<String> = []

    @Published var teamSelectionMode = SelectionMode.all
    @Published var selectedTeamScopeIDs: Set<String> = []
    @Published var projectSelectionMode = SelectionMode.all
    @Published var selectedProjectNames: Set<String> = []

    @Published private(set) var availableTeamScopes: [SelectionOption] = [personalScope]
    @Published private(set) var availableProjects: [SelectionOption] = []
    @Published private(set) var teamsLoading = false
    @Published private(set) var projectsLoading = false
    @Published private(set) var vercelOptionsErrorMessage: String?

    @Published private(set) var availableCloudflareAccounts: [SelectionOption] = []
    @Published private(set) var availableCloudflareWorkers: [SelectionOption] = []
    @Published private(set) var cloudflareLoading = false
    @Published private(set) var cloudflareOptionsErrorMessage: String?

    private static let personalScope = SelectionOption(
        id: Preferences.personalScopeIdentifier,
        title: "Personal Account",
        subtitle: "Deployments under your personal scope"
    )

    private let store: PreferencesStore
    private let vercelClient: VercelClient
    private let cloudflareClient: CloudflareClient

    private var cancellables: Set<AnyCancellable> = []
    private var vercelLookupTask: Task<Void, Never>?
    private var cloudflareLookupTask: Task<Void, Never>?
    private var isHydrating = false

    init(
        store: PreferencesStore,
        vercelClient: VercelClient = VercelClient(),
        cloudflareClient: CloudflareClient = CloudflareClient()
    ) {
        self.store = store
        self.vercelClient = vercelClient
        self.cloudflareClient = cloudflareClient
        hydrate(from: store.current)
        setupObservers()
        refreshVercelOptions(reloadTeams: true)
        refreshCloudflareOptions()
    }

    var hasVercelToken: Bool {
        !vercelToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasCloudflareToken: Bool {
        !cloudflareToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var vercelStatus: ConnectionStatus {
        guard hasVercelToken else { return .notConnected }
        if teamsLoading || projectsLoading {
            return .checking
        }
        let projects = availableProjects.filter { !$0.isMissing }.count
        // Team-scoped tokens can't list teams but still work, so an error only counts as
        // failing when no projects loaded either.
        if let message = vercelOptionsErrorMessage, projects == 0 {
            return .failed(message)
        }
        return .connected(Self.count(projects, "project"))
    }

    var cloudflareStatus: ConnectionStatus {
        guard hasCloudflareToken else { return .notConnected }
        if cloudflareLoading {
            return .checking
        }
        if let message = cloudflareOptionsErrorMessage {
            return .failed(message)
        }
        let accounts = availableCloudflareAccounts.filter { !$0.isMissing }.count
        let workers = availableCloudflareWorkers.filter { !$0.isMissing }.count
        return .connected("\(Self.count(accounts, "account")) · \(Self.count(workers, "Worker"))")
    }

    private static func count(_ value: Int, _ noun: String) -> String {
        "\(value) \(noun)\(value == 1 ? "" : "s")"
    }

    /// Discards unsaved edits and reloads from the store.
    func reset() {
        hydrate(from: store.current)
        refreshVercelOptions(reloadTeams: true)
        refreshCloudflareOptions()
    }

    func save() {
        persistPreferences()
    }

    func refreshVercelOptions(reloadTeams: Bool) {
        guard !isHydrating else { return }

        vercelLookupTask?.cancel()
        let token = vercelToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            availableTeamScopes = [Self.personalScope]
            availableProjects = []
            teamsLoading = false
            projectsLoading = false
            vercelOptionsErrorMessage = nil
            return
        }

        // A teams lookup that this replaces still needs to finish.
        let reloadTeams = reloadTeams || teamsLoading
        // Mark loading now, not when the task starts, so the status never shows stale counts.
        if reloadTeams {
            teamsLoading = true
        }
        projectsLoading = true
        vercelLookupTask = Task { [weak self] in
            await self?.loadVercelOptions(token: token, reloadTeams: reloadTeams)
        }
    }

    private func hydrate(from current: Preferences) {
        isHydrating = true
        defer { isHydrating = false }

        vercelToken = current.vercelToken
        gitBranches = current.gitBranches
        showProduction = current.showProduction
        showPreview = current.showPreview
        showReady = current.showReady
        showBuilding = current.showBuilding
        showError = current.showError
        showQueued = current.showQueued
        showCanceled = current.showCanceled
        limitByCount = current.limitByCount ?? 0
        limitByHours = current.limitByHours ?? 0
        refreshIntervalIdle = current.refreshIntervalIdle ?? 15
        refreshIntervalBuilding = current.refreshIntervalBuilding ?? 2
        menuBarStyle = current.menuBarStyle
        timeFormat = current.timeFormat
        showProjects = current.showProjects
        providerStyle = current.providerStyle
        environmentStyle = current.environmentStyle

        let teamIds = current.teamIdList
        teamSelectionMode = teamIds.isEmpty ? .all : .selected
        selectedTeamScopeIDs = Set(teamIds)

        let projectNames = current.projectNameList
        projectSelectionMode = projectNames.isEmpty ? .all : .selected
        selectedProjectNames = Set(projectNames)

        cloudflareToken = current.cloudflareToken
        let accountIds = current.cloudflareAccountIdList
        cloudflareAccountMode = accountIds.isEmpty ? .all : .selected
        selectedCloudflareAccountIDs = Set(accountIds)
        let workers = current.cloudflareWorkerList
        cloudflareWorkerMode = workers.isEmpty ? .all : .selected
        selectedCloudflareWorkers = Set(workers)
    }

    private func setupObservers() {
        // Edits auto-save once typing pauses, which also lets objectWillChange's new value land
        // before it's read. Unchanged preferences are a no-op in the store; closing the window flushes.
        objectWillChange
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] in self?.persistPreferences() }
            .store(in: &cancellables)

        $vercelToken
            .dropFirst()
            .removeDuplicates()
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.refreshVercelOptions(reloadTeams: true) }
            .store(in: &cancellables)

        Publishers.Merge(
            $teamSelectionMode.removeDuplicates().dropFirst().map { _ in () },
            $selectedTeamScopeIDs.removeDuplicates().dropFirst().map { _ in () }
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] in self?.refreshVercelOptions(reloadTeams: false) }
        .store(in: &cancellables)

        $cloudflareToken
            .dropFirst()
            .removeDuplicates()
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.refreshCloudflareOptions() }
            .store(in: &cancellables)

        Publishers.Merge(
            $cloudflareAccountMode.removeDuplicates().dropFirst().map { _ in () },
            $selectedCloudflareAccountIDs.removeDuplicates().dropFirst().map { _ in () }
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] in self?.refreshCloudflareOptions() }
        .store(in: &cancellables)
    }

    private func persistPreferences() {
        guard !isHydrating else { return }

        store.update { preferences in
            preferences.vercelToken = vercelToken.trimmingCharacters(in: .whitespacesAndNewlines)
            preferences.teamId = Self.serialize(selectedTeamScopeIDs, mode: teamSelectionMode)
            preferences.projectName = Self.serialize(selectedProjectNames, mode: projectSelectionMode)
            preferences.cloudflareToken = cloudflareToken.trimmingCharacters(in: .whitespacesAndNewlines)
            preferences.cloudflareAccountIds = Self.serialize(selectedCloudflareAccountIDs, mode: cloudflareAccountMode)
            preferences.cloudflareWorkers = Self.serialize(selectedCloudflareWorkers, mode: cloudflareWorkerMode)
            preferences.gitBranches = gitBranches
            preferences.showProduction = showProduction
            preferences.showPreview = showPreview
            preferences.showReady = showReady
            preferences.showBuilding = showBuilding
            preferences.showError = showError
            preferences.showQueued = showQueued
            preferences.showCanceled = showCanceled
            preferences.limitByCount = limitByCount > 0 ? limitByCount : nil
            preferences.limitByHours = limitByHours > 0 ? limitByHours : nil
            preferences.refreshIntervalIdle = refreshIntervalIdle
            preferences.refreshIntervalBuilding = refreshIntervalBuilding
            preferences.menuBarStyle = menuBarStyle
            preferences.timeFormat = timeFormat
            preferences.showProjects = showProjects
            preferences.providerStyle = providerStyle
            preferences.environmentStyle = environmentStyle
        }
    }

    /// An empty value means "all".
    private static func serialize(_ selection: Set<String>, mode: SelectionMode) -> String {
        guard mode == .selected else { return "" }
        return selection.sorted().joined(separator: ",")
    }

    // A newer lookup cancels the previous one. A cancelled lookup returns without touching
    // any state, so it can't clear the loading flags the newer lookup just set.

    private func loadVercelOptions(token: String, reloadTeams: Bool) async {
        vercelOptionsErrorMessage = nil

        if reloadTeams {
            teamsLoading = true
            do {
                let teams = try await vercelClient.teams(token: token)
                    .map { SelectionOption(id: $0.slug, title: $0.name, subtitle: $0.slug) }
                    .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
                guard !Task.isCancelled else { return }
                availableTeamScopes = Self.options([Self.personalScope] + teams, keeping: selectedTeamScopeIDs)
            } catch {
                guard !Task.isCancelled else { return }
                if !Self.isCancellation(error) {
                    availableTeamScopes = Self.options([Self.personalScope], keeping: selectedTeamScopeIDs)
                    vercelOptionsErrorMessage = error.localizedDescription
                }
            }
            teamsLoading = false
        }

        projectsLoading = true
        do {
            let names = try await fetchProjectNamesForCurrentScope(token: token)
            guard !Task.isCancelled else { return }
            availableProjects = Self.options(names.map { SelectionOption(id: $0, title: $0) }, keeping: selectedProjectNames)
        } catch {
            guard !Task.isCancelled else { return }
            if !Self.isCancellation(error) {
                availableProjects = Self.options([], keeping: selectedProjectNames)
                vercelOptionsErrorMessage = error.localizedDescription
            }
        }
        projectsLoading = false
    }

    /// Uses the same scopes `VercelDeploymentProvider` fetches from, so every project it can
    /// show is selectable.
    private func fetchProjectNamesForCurrentScope(token: String) async throws -> [String] {
        let scopeIDs = teamSelectionMode == .all
            ? availableTeamScopes.filter { !$0.isMissing }.map(\.id)
            : Array(selectedTeamScopeIDs)
        // No scopes yet (or none chosen) means the token's default scope, as when fetching.
        let scopes: [String?] = scopeIDs.isEmpty
            ? [nil]
            : scopeIDs.map { $0 == Preferences.personalScopeIdentifier ? nil : $0 }

        let projects = try await gatherConcurrently(scopes) { teamId in
            try await self.vercelClient.projects(token: token, teamId: teamId)
        }

        var seen: Set<String> = []
        return projects
            .map(\.name)
            .filter { seen.insert($0.lowercased()).inserted }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func refreshCloudflareOptions() {
        guard !isHydrating else { return }

        cloudflareLookupTask?.cancel()
        let token = cloudflareToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            availableCloudflareAccounts = []
            availableCloudflareWorkers = []
            cloudflareLoading = false
            cloudflareOptionsErrorMessage = nil
            return
        }

        cloudflareLoading = true
        cloudflareLookupTask = Task { [weak self] in
            await self?.loadCloudflareOptions(token: token)
        }
    }

    private func loadCloudflareOptions(token: String) async {
        cloudflareLoading = true
        cloudflareOptionsErrorMessage = nil

        do {
            let accounts = try await cloudflareClient.accounts(token: token)
                .map { SelectionOption(id: $0.id, title: $0.name, subtitle: $0.id) }
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            guard !Task.isCancelled else { return }
            availableCloudflareAccounts = Self.options(accounts, keeping: selectedCloudflareAccountIDs)

            let accountIds = cloudflareAccountMode == .all ? accounts.map(\.id) : Array(selectedCloudflareAccountIDs)
            let workers = try await gatherConcurrently(accountIds) { accountId in
                try await self.cloudflareClient.workers(token: token, accountId: accountId)
            }
            guard !Task.isCancelled else { return }
            let names = Set(workers.map(\.id)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            availableCloudflareWorkers = Self.options(names.map { SelectionOption(id: $0, title: $0) }, keeping: selectedCloudflareWorkers)
        } catch {
            guard !Task.isCancelled else { return }
            if !Self.isCancellation(error) {
                cloudflareOptionsErrorMessage = error.localizedDescription
            }
        }
        cloudflareLoading = false
    }

    /// Appends saved selections a lookup didn't return. A failed request or a change in access
    /// shouldn't silently discard, and then auto-save over, what the user chose.
    private static func options(_ options: [SelectionOption], keeping selection: Set<String>) -> [SelectionOption] {
        let known = Set(options.map(\.id))
        let missing = selection.subtracting(known).sorted().map {
            SelectionOption(id: $0, title: $0, subtitle: "Not found", isMissing: true)
        }
        return options + missing
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
}
