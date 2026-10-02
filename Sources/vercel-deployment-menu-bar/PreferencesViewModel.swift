import Combine
import Foundation

enum SelectionMode: String, CaseIterable, Identifiable {
    case all
    case selected

    var id: String { rawValue }
}

struct SelectionOption: Identifiable, Hashable {
    let id: String
    let title: String
    var subtitle: String?
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
    @Published var limitByCount = ""
    @Published var limitByHours = ""
    @Published var refreshIntervalIdle = ""
    @Published var refreshIntervalBuilding = ""

    @Published var teamSelectionMode = SelectionMode.all
    @Published var selectedTeamScopeIDs: Set<String> = []
    @Published var projectSelectionMode = SelectionMode.all
    @Published var selectedProjectNames: Set<String> = []

    @Published private(set) var availableTeamScopes: [SelectionOption] = [personalScope]
    @Published private(set) var availableProjects: [SelectionOption] = []
    @Published private(set) var teamsLoading = false
    @Published private(set) var projectsLoading = false
    @Published private(set) var optionsErrorMessage: String?

    private static let personalScope = SelectionOption(
        id: Preferences.personalScopeIdentifier,
        title: "Personal Account",
        subtitle: "Deployments under your personal scope"
    )

    private let store: PreferencesStore
    private let client: VercelClient

    private var cancellables: Set<AnyCancellable> = []
    private var lookupTask: Task<Void, Never>?
    private var isHydrating = false

    init(store: PreferencesStore, client: VercelClient = VercelClient()) {
        self.store = store
        self.client = client
        hydrate(from: store.current)
        setupObservers()
        refreshRemoteOptions(reloadTeams: true)
    }

    var hasToken: Bool {
        !vercelToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Discards unsaved edits and reloads from the store.
    func reset() {
        hydrate(from: store.current)
        refreshRemoteOptions(reloadTeams: true)
    }

    func save() {
        persistPreferences()
    }

    func refreshRemoteOptions(reloadTeams: Bool) {
        guard !isHydrating else { return }

        lookupTask?.cancel()
        let token = vercelToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            availableTeamScopes = [Self.personalScope]
            availableProjects = []
            teamsLoading = false
            projectsLoading = false
            optionsErrorMessage = nil
            return
        }

        lookupTask = Task { [weak self] in
            await self?.loadRemoteOptions(token: token, reloadTeams: reloadTeams)
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
        limitByCount = current.limitByCount.map(String.init) ?? ""
        limitByHours = current.limitByHours.map(String.init) ?? ""
        refreshIntervalIdle = current.refreshIntervalIdle.map(String.init) ?? ""
        refreshIntervalBuilding = current.refreshIntervalBuilding.map(String.init) ?? ""

        let teamIds = current.teamIdList
        teamSelectionMode = teamIds.isEmpty ? .all : .selected
        selectedTeamScopeIDs = Set(teamIds)

        let projectNames = current.projectNameList
        projectSelectionMode = projectNames.isEmpty ? .all : .selected
        selectedProjectNames = Set(projectNames)
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
            .sink { [weak self] _ in self?.refreshRemoteOptions(reloadTeams: true) }
            .store(in: &cancellables)

        Publishers.Merge(
            $teamSelectionMode.dropFirst().map { _ in () },
            $selectedTeamScopeIDs.dropFirst().map { _ in () }
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] in self?.refreshRemoteOptions(reloadTeams: false) }
        .store(in: &cancellables)
    }

    private func persistPreferences() {
        guard !isHydrating else { return }

        store.update { preferences in
            preferences.vercelToken = vercelToken.trimmingCharacters(in: .whitespacesAndNewlines)
            preferences.teamId = Self.serialize(selectedTeamScopeIDs, mode: teamSelectionMode)
            preferences.projectName = Self.serialize(selectedProjectNames, mode: projectSelectionMode)
            preferences.gitBranches = gitBranches
            preferences.showProduction = showProduction
            preferences.showPreview = showPreview
            preferences.showReady = showReady
            preferences.showBuilding = showBuilding
            preferences.showError = showError
            preferences.showQueued = showQueued
            preferences.showCanceled = showCanceled
            preferences.limitByCount = Int(limitByCount)
            preferences.limitByHours = Int(limitByHours)
            preferences.refreshIntervalIdle = Int(refreshIntervalIdle)
            preferences.refreshIntervalBuilding = Int(refreshIntervalBuilding)
        }
    }

    /// An empty value means "all".
    private static func serialize(_ selection: Set<String>, mode: SelectionMode) -> String {
        guard mode == .selected else { return "" }
        return selection.sorted().joined(separator: ",")
    }

    private func loadRemoteOptions(token: String, reloadTeams: Bool) async {
        optionsErrorMessage = nil

        if reloadTeams {
            teamsLoading = true
            do {
                let teams = try await client.teams(token: token)
                    .map { SelectionOption(id: $0.slug, title: $0.name, subtitle: $0.slug) }
                    .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
                let options = [Self.personalScope] + teams
                availableTeamScopes = options
                selectedTeamScopeIDs.formIntersection(options.map(\.id))
            } catch where !Self.isCancellation(error) {
                availableTeamScopes = [Self.personalScope]
                optionsErrorMessage = error.localizedDescription
            } catch {}
            teamsLoading = false
        }

        projectsLoading = true
        do {
            let names = try await fetchProjectNamesForCurrentScope(token: token)
            availableProjects = names.map { SelectionOption(id: $0, title: $0) }
            selectedProjectNames.formIntersection(names)
        } catch where !Self.isCancellation(error) {
            availableProjects = []
            optionsErrorMessage = error.localizedDescription
        } catch {}
        projectsLoading = false
    }

    private func fetchProjectNamesForCurrentScope(token: String) async throws -> [String] {
        let scopes: [String?] = teamSelectionMode == .all
            ? [nil]
            : selectedTeamScopeIDs.map { $0 == Preferences.personalScopeIdentifier ? nil : $0 }

        let projects = try await gatherConcurrently(scopes) { teamId in
            try await self.client.projects(token: token, teamId: teamId)
        }

        var seen: Set<String> = []
        return projects
            .map(\.name)
            .filter { seen.insert($0.lowercased()).inserted }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
}
