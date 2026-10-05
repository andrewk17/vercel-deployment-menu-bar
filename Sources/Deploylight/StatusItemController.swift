import AppKit
import Foundation

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let deploymentService = DeploymentService()

    private var refreshTimer: Timer?
    private var tickTimer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var latestDeployments: [Deployment] = []
    private var projects: [ProjectSummary] = []
    /// Every fetched deployment, filtered or not, so an open row still updates when its
    /// build finishes into a hidden state.
    private var deploymentsByID: [String: Deployment] = [:]
    private var errors: [Deployment.Provider: Error] = [:]
    private var configuredProviders: [Deployment.Provider] = []
    private var lastFetchDate: Date?

    private var preferencesObserver: NSObjectProtocol?

    /// A menu row that's updated in place while the menu is open.
    private struct LiveRow {
        enum Source {
            case deployment(id: String, includeProject: Bool)
            case project(provider: Deployment.Provider, name: String)
        }

        let item: NSMenuItem
        let source: Source
    }

    private var liveRows: [LiveRow] = []
    /// What each row was last set to. An item's own title can't be compared, since an
    /// attributed title with icons rewrites it.
    private var shownTitles: [ObjectIdentifier: String] = [:]
    private var isMenuOpen = false
    /// Fixed-width digits keep rows, and so the menu, from changing width as times tick.
    private static let rowFont = NSFont.monospacedDigitSystemFont(ofSize: NSFont.menuFont(ofSize: 0).pointSize, weight: .regular)

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        // The menu is built as it opens rather than on every refresh, so it doesn't
        // shift or redraw under the pointer while it's open.
        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.imagePosition = .imageLeft
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        statusItem.button?.image = NSImage(systemSymbolName: "circle", accessibilityDescription: nil)
    }

    func start() {
        preferencesObserver = NotificationCenter.default.addObserver(
            forName: PreferencesStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshDeployments(restartInFlight: true)
            }
        }

        startTickTimer()
        refreshDeployments()
    }

    func stop() {
        preferencesObserver.flatMap(NotificationCenter.default.removeObserver)
        preferencesObserver = nil
        refreshTask?.cancel()
        refreshTimer?.invalidate()
        tickTimer?.invalidate()
    }

    // MARK: - Actions

    @objc private func refreshFromMenu(_ sender: Any?) {
        refreshDeployments(restartInFlight: true)
    }

    @objc private func openURL(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openPreferences(_ sender: Any?) {
        PreferencesWindowController.shared.show()
    }

    @objc private func quitApp(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    // MARK: - Refreshing

    private func startTickTimer() {
        let timer = Timer(timeInterval: 1.0, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    @objc private func tick() {
        updateStatusButton()
        updateOpenMenu()
    }

    private func scheduleNextRefresh() {
        refreshTimer?.invalidate()
        let preferences = PreferencesStore.shared.current
        let hasActiveBuild = latestDeployments.contains { $0.state.isActive }
        let seconds = hasActiveBuild
            ? preferences.refreshIntervalBuilding ?? 2
            : preferences.refreshIntervalIdle ?? 15
        let timer = Timer(
            timeInterval: TimeInterval(max(seconds, 1)),
            target: self,
            selector: #selector(refreshTimerFired),
            userInfo: nil,
            repeats: false
        )
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    @objc private func refreshTimerFired() {
        refreshDeployments()
    }

    /// Starts a refresh unless one is already running. Pass `restartInFlight` when the
    /// in-flight request may be stale, such as after a preferences change.
    private func refreshDeployments(restartInFlight: Bool = false) {
        if refreshTask != nil {
            guard restartInFlight else { return }
            refreshTask?.cancel()
        }

        refreshTimer?.invalidate()
        let preferences = PreferencesStore.shared.current
        configuredProviders = deploymentService.configuredProviders(preferences)

        guard !configuredProviders.isEmpty else {
            refreshTask = nil
            latestDeployments = []
            projects = []
            deploymentsByID = [:]
            errors = [:]
            render()
            return
        }

        refreshTask = Task {
            let snapshot = await deploymentService.fetch(preferences: preferences)
            guard !Task.isCancelled else { return }

            let filter = DeploymentFilter(preferences: preferences)
            let matching = filter.matching(snapshot.deployments)
            latestDeployments = filter.limit(matching)
            projects = ProjectSummary.summaries(from: matching)
            deploymentsByID = Dictionary(snapshot.deployments.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            errors = snapshot.errors
            if snapshot.errors.count < configuredProviders.count {
                lastFetchDate = Date()
            }
            refreshTask = nil
            render()
            scheduleNextRefresh()
        }
    }

    // MARK: - Rendering

    private func render() {
        updateStatusButton()
        updateOpenMenu()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        buildMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
    }

    /// Refreshes the open menu's rows in place: build times tick, and a refresh can turn a
    /// building row into a finished one. Rows are only added or removed when it reopens.
    private func updateOpenMenu() {
        guard isMenuOpen else { return }

        let formatter = rowFormatter()
        for row in liveRows {
            switch row.source {
            case let .deployment(id, includeProject):
                guard let deployment = deploymentsByID[id] else { continue }
                setTitle(formatter.title(for: deployment, includeProject: includeProject), on: row.item)
                setImage(StatusIcon.image(for: deployment.state), on: row.item)
            case let .project(provider, name):
                guard let project = projects.first(where: { $0.provider == provider && $0.name.lowercased() == name }) else { continue }
                setTitle(formatter.title(for: project), on: row.item)
                setImage(StatusIcon.image(for: project.headline.state), on: row.item)
            }
        }
    }

    private func rowFormatter() -> MenuRowFormatter {
        MenuRowFormatter(
            preferences: PreferencesStore.shared.current,
            showsProvider: configuredProviders.count > 1,
            font: Self.rowFont
        )
    }

    private func setTitle(_ title: MenuRowTitle, on item: NSMenuItem) {
        let key = ObjectIdentifier(item)
        guard shownTitles[key] != title.plain else { return }
        shownTitles[key] = title.plain
        item.attributedTitle = title.attributed
    }

    private func setImage(_ image: NSImage?, on item: NSMenuItem) {
        guard item.image !== image else { return }
        item.image = image
    }

    private func updateStatusButton() {
        guard let button = statusItem.button else { return }

        // An in-progress build is the most useful thing to show, even if a newer one finished.
        if let shown = latestDeployments.first(where: { $0.state.isActive }) ?? latestDeployments.first {
            button.image = StatusIcon.image(for: shown.state)
            let preferences = PreferencesStore.shared.current
            button.title = StatusTitle.text(
                projectName: shown.projectName,
                state: shown.state,
                elapsed: shown.elapsed(),
                style: preferences.menuBarStyle,
                timeFormat: preferences.timeFormat
            )
        } else if configuredProviders.isEmpty {
            button.title = "No Token"
            button.image = NSImage(systemSymbolName: "key.slash", accessibilityDescription: nil)
        } else if !errors.isEmpty {
            button.title = "Error"
            button.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
        } else {
            button.title = ""
            button.image = NSImage(systemSymbolName: "circle", accessibilityDescription: nil)
        }
        button.imagePosition = button.title.isEmpty ? .imageOnly : .imageLeft
    }


    private func buildMenu() {
        menu.removeAllItems()
        liveRows = []
        shownTitles = [:]

        if configuredProviders.isEmpty {
            menu.addItem(disabledItem("Add a Vercel or Cloudflare token in Preferences"))
            menu.addItem(.separator())
        } else {
            for provider in Deployment.Provider.allCases {
                guard let error = errors[provider] else { continue }
                menu.addItem(disabledItem("\(provider.rawValue) error: \(error.localizedDescription)"))
            }
            if latestDeployments.isEmpty, errors.isEmpty {
                menu.addItem(disabledItem("No deployments found"))
            }
            if !errors.isEmpty, !latestDeployments.isEmpty {
                menu.addItem(.separator())
            }
        }

        let formatter = rowFormatter()
        let showsProjects = PreferencesStore.shared.current.showProjects && !projects.isEmpty
        if showsProjects, !latestDeployments.isEmpty {
            menu.addItem(sectionHeader("Recent"))
        }
        for deployment in latestDeployments {
            menu.addItem(deploymentItem(for: deployment, formatter: formatter))
        }

        if showsProjects {
            menu.addItem(.separator())
            menu.addItem(sectionHeader("Projects"))
            for project in projects {
                menu.addItem(projectItem(for: project, formatter: formatter))
            }
        }

        if let lastFetchDate {
            menu.addItem(.separator())
            menu.addItem(disabledItem("Last updated: \(Formatting.time(lastFetchDate))"))
        }

        menu.addItem(.separator())
        menu.addItem(actionItem("Refresh Now", #selector(refreshFromMenu(_:)), key: "r"))
        let preferences = PreferencesStore.shared.current
        for provider in configuredProviders {
            let item = actionItem("Open \(provider.rawValue) Dashboard", #selector(openURL(_:)))
            item.representedObject = dashboardURL(for: provider, preferences: preferences)
            menu.addItem(item)
        }
        menu.addItem(actionItem("Preferences…", #selector(openPreferences(_:)), key: ","))
        menu.addItem(.separator())
        menu.addItem(actionItem("Quit Deploylight", #selector(quitApp(_:)), key: "q"))
    }

    private func dashboardURL(for provider: Deployment.Provider, preferences: Preferences) -> URL? {
        switch provider {
        case .vercel:
            let teamIds = preferences.teamIdList
            if teamIds.count == 1, teamIds[0] != Preferences.personalScopeIdentifier {
                return URL(string: "https://vercel.com/\(teamIds[0])/deployments")
            }
            return URL(string: "https://vercel.com/deployments")
        case .cloudflare:
            let accountIds = preferences.cloudflareAccountIdList
            if accountIds.count == 1 {
                return URL(string: "https://dash.cloudflare.com/\(accountIds[0])/workers-and-pages")
            }
            return URL(string: "https://dash.cloudflare.com/")
        }
    }

    private func deploymentItem(for deployment: Deployment, includeProject: Bool = true, formatter: MenuRowFormatter) -> NSMenuItem {
        let item = NSMenuItem(title: "", action: #selector(openURL(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = deployment.link
        item.toolTip = Self.sanitizedCommitToolTip(from: deployment.commitMessage)
        setTitle(formatter.title(for: deployment, includeProject: includeProject), on: item)
        item.image = StatusIcon.image(for: deployment.state)
        liveRows.append(LiveRow(item: item, source: .deployment(id: deployment.id, includeProject: includeProject)))
        return item
    }

    /// A project's latest production deployment, with its recent history in a submenu.
    private func projectItem(for project: ProjectSummary, formatter: MenuRowFormatter) -> NSMenuItem {
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        setTitle(formatter.title(for: project), on: item)
        item.image = StatusIcon.image(for: project.headline.state)
        liveRows.append(LiveRow(item: item, source: .project(provider: project.provider, name: project.name.lowercased())))

        let submenu = NSMenu()
        for deployment in project.deployments.prefix(ProjectSummary.historyDepth) {
            submenu.addItem(deploymentItem(for: deployment, includeProject: false, formatter: formatter))
        }
        item.submenu = submenu
        return item
    }

    private func sectionHeader(_ title: String) -> NSMenuItem {
        if #available(macOS 14.0, *) {
            return .sectionHeader(title: title)
        }
        return disabledItem(title)
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func actionItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    nonisolated static func sanitizedCommitToolTip(from rawMessage: String?) -> String? {
        guard let rawMessage else {
            return nil
        }

        let firstLine = rawMessage
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? ""

        let collapsed = firstLine
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else {
            return nil
        }

        let maxLength = 90
        guard collapsed.count > maxLength else {
            return collapsed
        }
        return String(collapsed.prefix(maxLength - 1)) + "…"
    }
}
