import AppKit
import Combine
import SwiftUI

final class PreferencesWindowController: NSWindowController {
    static let shared = PreferencesWindowController()

    private let viewModel: PreferencesViewModel

    private init() {
        let viewModel = PreferencesViewModel(store: PreferencesStore.shared)
        self.viewModel = viewModel
        let view = PreferencesView(viewModel: viewModel)
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 760),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Vercel Status Preferences"
        window.contentViewController = hostingController
        super.init(window: window)
        self.window?.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }
        viewModel.reset()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension PreferencesWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        viewModel.saveAndClose()
    }
}

enum TeamSelectionMode: String, CaseIterable, Identifiable {
    case allAccessible
    case selected

    var id: String { rawValue }
}

enum ProjectSelectionMode: String, CaseIterable, Identifiable {
    case allAccessible
    case selected

    var id: String { rawValue }
}

struct TeamScopeOption: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String?

    static let personal = TeamScopeOption(
        id: Preferences.personalScopeIdentifier,
        title: "Personal Account",
        subtitle: "Deployments under your personal scope"
    )
}

struct ProjectFilterOption: Identifiable, Hashable {
    let id: String
    let name: String
}

final class PreferencesLookupService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchTeams(token: String) async throws -> [Team] {
        guard let url = URL(string: "https://api.vercel.com/v2/teams") else {
            return []
        }

        let data = try await requestData(url: url, token: token)
        guard let decoded = try? JSONDecoder().decode(TeamsResponse.self, from: data) else {
            throw APIError.decodingFailure
        }
        return decoded.teams
    }

    func fetchProjects(token: String, teamId: String?) async throws -> [Project] {
        var components = URLComponents(string: "https://api.vercel.com/v9/projects")!
        var queryItems = [URLQueryItem(name: "limit", value: "100")]
        if let teamId, !teamId.isEmpty {
            queryItems.append(URLQueryItem(name: "teamId", value: teamId))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            return []
        }

        let data = try await requestData(url: url, token: token)
        guard let decoded = try? JSONDecoder().decode(ProjectsResponse.self, from: data) else {
            throw APIError.decodingFailure
        }
        return decoded.projects
    }

    private func requestData(url: URL, token: String) async throws -> Data {
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

        return data
    }
}

final class PreferencesViewModel: ObservableObject {
    @Published var vercelToken: String
    @Published var gitBranches: String
    @Published var showProduction: Bool
    @Published var showPreview: Bool
    @Published var showReady: Bool
    @Published var showBuilding: Bool
    @Published var showError: Bool
    @Published var showQueued: Bool
    @Published var showCanceled: Bool
    @Published var limitByCount: String
    @Published var limitByHours: String
    @Published var refreshIntervalIdle: String
    @Published var refreshIntervalBuilding: String

    @Published var teamSelectionMode: TeamSelectionMode
    @Published var selectedTeamScopeIDs: Set<String>
    @Published var projectSelectionMode: ProjectSelectionMode
    @Published var selectedProjectNames: Set<String>

    @Published private(set) var availableTeamScopes: [TeamScopeOption]
    @Published private(set) var availableProjects: [ProjectFilterOption]
    @Published private(set) var teamsLoading: Bool
    @Published private(set) var projectsLoading: Bool
    @Published private(set) var optionsErrorMessage: String?

    private let store: PreferencesStore
    private let lookupService: PreferencesLookupService

    private var cancellables: Set<AnyCancellable> = []
    private var lookupTask: Task<Void, Never>?
    private var isHydrating = false

    init(
        store: PreferencesStore,
        lookupService: PreferencesLookupService = PreferencesLookupService()
    ) {
        self.store = store
        self.lookupService = lookupService

        let current = store.current

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
        teamSelectionMode = teamIds.isEmpty ? .allAccessible : .selected
        selectedTeamScopeIDs = Set(teamIds)

        let projectNames = current.projectNameList
        projectSelectionMode = projectNames.isEmpty ? .allAccessible : .selected
        selectedProjectNames = Set(projectNames)

        availableTeamScopes = [.personal]
        availableProjects = []
        teamsLoading = false
        projectsLoading = false
        optionsErrorMessage = nil

        setupObservers()
        refreshRemoteOptions(forceReloadTeams: true)
    }

    var hasToken: Bool {
        !vercelToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func reset() {
        hydrate(from: store.current)
        refreshRemoteOptions(forceReloadTeams: true)
    }

    func saveAndClose() {
        persistPreferences()
    }

    func refreshRemoteOptions(forceReloadTeams: Bool = true) {
        guard !isHydrating else { return }

        let token = vercelToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            availableTeamScopes = [.personal]
            availableProjects = []
            teamsLoading = false
            projectsLoading = false
            optionsErrorMessage = nil
            return
        }

        lookupTask?.cancel()
        lookupTask = Task { [weak self] in
            guard let self else { return }
            await self.loadRemoteOptions(token: token, forceReloadTeams: forceReloadTeams)
        }
    }

    func teamSelectionBinding(for scopeId: String) -> Binding<Bool> {
        Binding(
            get: { self.selectedTeamScopeIDs.contains(scopeId) },
            set: { isSelected in
                var updated = self.selectedTeamScopeIDs
                if isSelected {
                    updated.insert(scopeId)
                } else {
                    updated.remove(scopeId)
                }
                self.selectedTeamScopeIDs = updated
                self.persistPreferences()
            }
        )
    }

    func projectSelectionBinding(for projectName: String) -> Binding<Bool> {
        Binding(
            get: { self.selectedProjectNames.contains(projectName) },
            set: { isSelected in
                var updated = self.selectedProjectNames
                if isSelected {
                    updated.insert(projectName)
                } else {
                    updated.remove(projectName)
                }
                self.selectedProjectNames = updated
                self.persistPreferences()
            }
        )
    }

    private func hydrate(from current: Preferences) {
        isHydrating = true

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
        teamSelectionMode = teamIds.isEmpty ? .allAccessible : .selected
        selectedTeamScopeIDs = Set(teamIds)

        let projectNames = current.projectNameList
        projectSelectionMode = projectNames.isEmpty ? .allAccessible : .selected
        selectedProjectNames = Set(projectNames)

        isHydrating = false
    }

    private func setupObservers() {
        observeAutoSave($vercelToken)
        observeAutoSave($gitBranches)
        observeAutoSave($showProduction)
        observeAutoSave($showPreview)
        observeAutoSave($showReady)
        observeAutoSave($showBuilding)
        observeAutoSave($showError)
        observeAutoSave($showQueued)
        observeAutoSave($showCanceled)
        observeAutoSave($limitByCount)
        observeAutoSave($limitByHours)
        observeAutoSave($refreshIntervalIdle)
        observeAutoSave($refreshIntervalBuilding)
        observeAutoSave($teamSelectionMode)
        observeAutoSave($selectedTeamScopeIDs)
        observeAutoSave($projectSelectionMode)
        observeAutoSave($selectedProjectNames)

        $vercelToken
            .dropFirst()
            .removeDuplicates()
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshRemoteOptions(forceReloadTeams: true)
            }
            .store(in: &cancellables)

        Publishers.Merge(
            $teamSelectionMode.dropFirst().map { _ in () },
            $selectedTeamScopeIDs.dropFirst().map { _ in () }
        )
        .sink { [weak self] _ in
            self?.refreshRemoteOptions(forceReloadTeams: false)
        }
        .store(in: &cancellables)
    }

    private func observeAutoSave<T>(_ publisher: Published<T>.Publisher) {
        publisher
            .dropFirst()
            .sink { [weak self] _ in
                self?.persistPreferences()
            }
            .store(in: &cancellables)
    }

    private func persistPreferences() {
        guard !isHydrating else { return }

        store.update { preferences in
            preferences.vercelToken = vercelToken.trimmingCharacters(in: .whitespacesAndNewlines)
            preferences.teamId = serializedTeamScopeIDs
            preferences.projectName = serializedProjectNames
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

    private var serializedTeamScopeIDs: String {
        guard teamSelectionMode == .selected else { return "" }
        guard !selectedTeamScopeIDs.isEmpty else { return "" }
        return selectedTeamScopeIDs.sorted().joined(separator: ",")
    }

    private var serializedProjectNames: String {
        guard projectSelectionMode == .selected else { return "" }
        guard !selectedProjectNames.isEmpty else { return "" }
        return selectedProjectNames.sorted().joined(separator: ",")
    }

    private func loadRemoteOptions(token: String, forceReloadTeams: Bool) async {
        if forceReloadTeams {
            await MainActor.run {
                teamsLoading = true
                optionsErrorMessage = nil
            }

            do {
                let teams = try await lookupService.fetchTeams(token: token)
                let teamOptions = [TeamScopeOption.personal] + teams
                    .map { TeamScopeOption(id: $0.slug, title: $0.name, subtitle: $0.slug) }
                    .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

                await MainActor.run {
                    availableTeamScopes = teamOptions
                    selectedTeamScopeIDs = selectedTeamScopeIDs.intersection(Set(teamOptions.map(\.id)))
                }
            } catch {
                if !shouldIgnoreLookupError(error) {
                    await MainActor.run {
                        availableTeamScopes = [.personal]
                        optionsErrorMessage = error.localizedDescription
                    }
                }
            }

            await MainActor.run {
                teamsLoading = false
            }
        }

        await MainActor.run {
            projectsLoading = true
        }

        do {
            let projects = try await fetchProjectsForCurrentScope(token: token)
            let options = deduplicateProjects(projects).map {
                ProjectFilterOption(id: $0, name: $0)
            }

            await MainActor.run {
                availableProjects = options
                selectedProjectNames = selectedProjectNames.intersection(Set(options.map(\.name)))
                optionsErrorMessage = nil
            }
        } catch {
            if !shouldIgnoreLookupError(error) {
                await MainActor.run {
                    availableProjects = []
                    optionsErrorMessage = error.localizedDescription
                }
            }
        }

        await MainActor.run {
            projectsLoading = false
        }
    }

    private func fetchProjectsForCurrentScope(token: String) async throws -> [Project] {
        if teamSelectionMode == .allAccessible {
            return try await lookupService.fetchProjects(token: token, teamId: nil)
        }

        let scopeIds = selectedTeamScopeIDs
        guard !scopeIds.isEmpty else { return [] }

        let outcome = await withTaskGroup(
            of: Result<[Project], Error>.self,
            returning: (projects: [Project], successCount: Int, firstError: Error?).self
        ) { group in
            for scopeId in scopeIds {
                group.addTask {
                    do {
                        let teamId: String? = (scopeId == Preferences.personalScopeIdentifier) ? nil : scopeId
                        let projects = try await self.lookupService.fetchProjects(token: token, teamId: teamId)
                        return .success(projects)
                    } catch {
                        return .failure(error)
                    }
                }
            }

            var all: [Project] = []
            var successCount = 0
            var firstError: Error?

            for await result in group {
                switch result {
                case let .success(projects):
                    successCount += 1
                    all.append(contentsOf: projects)
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

        return outcome.projects
    }

    private func deduplicateProjects(_ projects: [Project]) -> [String] {
        var seen: Set<String> = []
        var names: [String] = []

        for project in projects {
            let key = project.name.lowercased()
            guard seen.insert(key).inserted else { continue }
            names.append(project.name)
        }

        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func shouldIgnoreLookupError(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
}

struct PreferencesView: View {
    @ObservedObject var viewModel: PreferencesViewModel
    @State private var showToken = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Authentication")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Vercel API Token")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            if showToken {
                                TextField("", text: $viewModel.vercelToken, prompt: Text("Enter your token"))
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                            } else {
                                PasteableSecureField(text: $viewModel.vercelToken, placeholder: "Enter your token")
                            }

                            Button(showToken ? "Hide" : "Show") {
                                showToken.toggle()
                            }
                            .buttonStyle(.bordered)
                        }
                        .help("Required. Create a token at vercel.com/account/tokens with 'Read Deployments' permission.")
                    }

                    HStack {
                        Text("Scope & Project")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Refresh") {
                            viewModel.refreshRemoteOptions(forceReloadTeams: true)
                        }
                        .disabled(!viewModel.hasToken || viewModel.teamsLoading || viewModel.projectsLoading)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Team Scopes")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Picker("", selection: $viewModel.teamSelectionMode) {
                                Text("All Accessible Scopes").tag(TeamSelectionMode.allAccessible)
                                Text("Choose Specific Scopes").tag(TeamSelectionMode.selected)
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }

                        if viewModel.teamsLoading {
                            ProgressView("Loading team scopes…")
                                .controlSize(.small)
                        } else if viewModel.teamSelectionMode == .selected {
                            if viewModel.availableTeamScopes.isEmpty {
                                Text("No scopes available for this token.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(alignment: .leading, spacing: 6) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        ForEach(viewModel.availableTeamScopes) { scope in
                                            Toggle(isOn: viewModel.teamSelectionBinding(for: scope.id)) {
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(scope.title)
                                                    if let subtitle = scope.subtitle {
                                                        Text(subtitle)
                                                            .font(.caption)
                                                            .foregroundStyle(.secondary)
                                                    }
                                                }
                                            }
                                            .toggleStyle(.checkbox)
                                        }
                                    }
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Projects")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Picker("", selection: $viewModel.projectSelectionMode) {
                                Text("All Projects In Scope").tag(ProjectSelectionMode.allAccessible)
                                Text("Choose Specific Projects").tag(ProjectSelectionMode.selected)
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }

                        if viewModel.projectsLoading {
                            ProgressView("Loading projects…")
                                .controlSize(.small)
                        } else if viewModel.projectSelectionMode == .selected {
                            if viewModel.availableProjects.isEmpty {
                                Text("No projects found for the selected scope(s).")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(alignment: .leading, spacing: 6) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        ForEach(viewModel.availableProjects) { project in
                                            Toggle(project.name, isOn: viewModel.projectSelectionBinding(for: project.name))
                                                .toggleStyle(.checkbox)
                                        }
                                    }
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }

                    if let optionsErrorMessage = viewModel.optionsErrorMessage {
                        Text("Couldn’t refresh scopes/projects: \(optionsErrorMessage)")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Filters")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Git Branches (optional)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField("", text: $viewModel.gitBranches, prompt: Text("e.g. main, develop"))
                            .textFieldStyle(.roundedBorder)
                            .help("Comma-separated list of branches to filter (e.g. main, develop)")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Deployment Types")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 16) {
                            Toggle("Production", isOn: $viewModel.showProduction)
                            Toggle("Preview", isOn: $viewModel.showPreview)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Deployment States")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 16) {
                                Toggle("Ready", isOn: $viewModel.showReady)
                                Toggle("Building", isOn: $viewModel.showBuilding)
                            }
                            HStack(spacing: 16) {
                                Toggle("Error", isOn: $viewModel.showError)
                                Toggle("Queued", isOn: $viewModel.showQueued)
                            }
                            Toggle("Canceled", isOn: $viewModel.showCanceled)
                        }
                    }
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Limits")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Maximum Deployments (optional)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        NumericTextField(text: $viewModel.limitByCount, placeholder: "e.g. 5")
                            .help("Maximum number of deployments to display (leave blank to ignore)")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Show Only Last X Hours (optional)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        NumericTextField(text: $viewModel.limitByHours, placeholder: "e.g. 24")
                            .help("Only show deployments created within the last X hours (used when Maximum Deployments is empty)")
                    }

                    Text("Limit by count OR by time. If both are set, count takes priority.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Refresh Intervals")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Idle Interval (seconds)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        NumericTextField(text: $viewModel.refreshIntervalIdle, placeholder: "Default: 15")
                            .help("How often to check for new deployments when none are building (in seconds)")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Building Interval (seconds)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        NumericTextField(text: $viewModel.refreshIntervalBuilding, placeholder: "Default: 2")
                            .help("How often to check for updates when deployments are building or queued (in seconds)")
                    }

                    Text("Lower values provide faster updates but may use more API requests. Defaults: 15s idle, 2s building.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)

                HStack {
                    Text("Changes auto-save.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Close") {
                        PreferencesWindowController.shared.close()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.return)
                }
                .padding(.top, 8)
            }
            .padding()
        }
        .frame(minWidth: 560, minHeight: 760)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct PasteableSecureField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSSecureTextField {
        let field = PasteEnabledSecureTextField()
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.isBezeled = true
        field.drawsBackground = true
        field.focusRingType = .default
        field.usesSingleLineMode = true
        field.isBordered = true
        return field
    }

    func updateNSView(_ nsView: NSSecureTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.placeholderString = placeholder
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        private let parent: PasteableSecureField

        init(parent: PasteableSecureField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSSecureTextField else { return }
            parent.text = field.stringValue
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let field = obj.object as? NSSecureTextField else { return }
            parent.text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

private final class PasteEnabledSecureTextField: NSSecureTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        if event.modifierFlags.contains(.command),
           let characters = event.charactersIgnoringModifiers?.lowercased() {
            switch characters {
            case "a":
                NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self)
                return true
            case "v":
                NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self)
                return true
            default:
                break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

private struct NumericTextField: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder))
            .textFieldStyle(.roundedBorder)
            .onChange(of: text) { newValue in
                let filtered = newValue.filter { $0.isNumber }
                if filtered != newValue {
                    text = filtered
                }
            }
    }
}
