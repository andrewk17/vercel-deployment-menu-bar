import AppKit
import Foundation

@MainActor
final class StatusItemController {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let deploymentService = DeploymentService()

    private var refreshTimer: Timer?
    private var tickTimer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var latestDeployments: [Deployment] = []
    private var errors: [Deployment.Provider: Error] = [:]
    private var configuredProviders: [Deployment.Provider] = []
    private var lastFetchDate: Date?

    private var preferencesObserver: NSObjectProtocol?

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = menu
        statusItem.button?.imagePosition = .imageLeft
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        statusItem.button?.title = "VRC"
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

        buildMenu()
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
            errors = [:]
            render()
            return
        }

        refreshTask = Task {
            let snapshot = await deploymentService.fetch(preferences: preferences)
            guard !Task.isCancelled else { return }

            latestDeployments = DeploymentFilter(preferences: preferences).apply(to: snapshot.deployments)
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
        buildMenu()
        updateStatusButton()
    }

    private func updateStatusButton() {
        guard let button = statusItem.button else { return }

        // An in-progress build is the most useful thing to show, even if a newer one finished.
        if let shown = latestDeployments.first(where: { $0.state.isActive }) ?? latestDeployments.first {
            button.image = StatusIcon.image(for: shown.state)
            button.title = statusTitle(for: shown)
        } else if configuredProviders.isEmpty {
            button.title = "No Token"
            button.image = NSImage(systemSymbolName: "key.slash", accessibilityDescription: nil)
        } else if !errors.isEmpty {
            button.title = "Error"
            button.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
        } else {
            button.title = "VRC"
            button.image = NSImage(systemSymbolName: "circle", accessibilityDescription: nil)
        }
    }

    private func statusTitle(for deployment: Deployment) -> String {
        let label = String(deployment.projectName.prefix(3)).uppercased()
        guard let duration = elapsedDuration(for: deployment) else { return label }
        return "\(label) \(Formatting.duration(duration))"
    }

    /// Time spent building so far, or the final build time once finished.
    private func elapsedDuration(for deployment: Deployment) -> TimeInterval? {
        switch deployment.state {
        case .building:
            return Date().timeIntervalSince(deployment.buildStartedAt)
        case .queued:
            return Date().timeIntervalSince(deployment.createdAt)
        case .ready, .error:
            return deployment.finishedAt.map { max($0.timeIntervalSince(deployment.buildStartedAt), 0) }
        case .canceled, .unknown:
            return nil
        }
    }

    private func buildMenu() {
        menu.removeAllItems()

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

        for deployment in latestDeployments {
            let item = NSMenuItem(title: menuTitle(for: deployment), action: #selector(openURL(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = deployment.link
            item.toolTip = Self.sanitizedCommitToolTip(from: deployment.commitMessage)
            item.image = StatusIcon.image(for: deployment.state)
            menu.addItem(item)
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
        menu.addItem(actionItem("Quit Vercel Deployment Menu Bar", #selector(quitApp(_:)), key: "q"))
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

    private func menuTitle(for deployment: Deployment) -> String {
        let name = deployment.branch.map { "\(deployment.projectName) (\($0))" } ?? deployment.projectName

        var statusParts: [String] = []
        if configuredProviders.count > 1 {
            statusParts.append(deployment.provider.rawValue)
        }
        if let target = deployment.target {
            statusParts.append(target.rawValue)
        }
        statusParts.append(statusDescription(for: deployment))
        statusParts.append(Formatting.time(deployment.buildStartedAt))

        return "\(name) — \(statusParts.joined(separator: " • "))"
    }

    private func statusDescription(for deployment: Deployment) -> String {
        let duration = elapsedDuration(for: deployment).map { " \(Formatting.duration($0))" } ?? ""
        switch deployment.state {
        case .building: return "Building\(duration)"
        case .queued: return "Queued\(duration)"
        case .ready: return "Ready\(duration)"
        case .error: return "Error"
        case .canceled: return "Canceled"
        case .unknown: return "Unknown"
        }
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

private enum Formatting {
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    static func time(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remaining = total % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m \(remaining)s"
        } else if minutes > 0 {
            return "\(minutes)m \(remaining)s"
        } else {
            return "\(remaining)s"
        }
    }
}

@MainActor
private enum StatusIcon {
    private static var cache: [Deployment.State: NSImage] = [:]

    static func image(for state: Deployment.State) -> NSImage? {
        if let cached = cache[state] {
            return cached
        }

        let (symbolName, color): (String, NSColor) = switch state {
        case .ready: ("checkmark.circle.fill", .systemGreen)
        case .error: ("xmark.circle.fill", .systemRed)
        case .building: ("hourglass", .systemYellow)
        case .queued: ("clock.fill", .systemOrange)
        case .canceled: ("minus.circle.fill", .systemGray)
        case .unknown: ("questionmark.circle", .systemGray)
        }

        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [color]))
        cache[state] = image
        return image
    }
}
