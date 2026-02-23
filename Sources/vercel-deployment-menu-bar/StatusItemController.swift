import AppKit
import Foundation

final class StatusItemController {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let deploymentService = DeploymentService()

    private var refreshTimer: Timer?
    private var tickTimer: Timer?
    private var latestDeployments: [Deployment] = []
    private var lastError: Error?
    private var lastFetchDate: Date?
    private var missingToken: Bool = false

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
            self?.refreshDeployments(userInitiated: true)
        }

        buildMenu()
        startTickTimer()
        refreshDeployments()
    }

    func stop() {
        preferencesObserver.flatMap(NotificationCenter.default.removeObserver)
        preferencesObserver = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
        tickTimer?.invalidate()
        tickTimer = nil
    }

    @objc private func refreshFromMenu(_ sender: Any?) {
        refreshDeployments(userInitiated: true)
    }

    @objc private func openDashboard(_ sender: Any?) {
        let preferences = PreferencesStore.shared.current
        var urlString = "https://vercel.com/deployments"
        let teamIds = preferences.teamIdList
        if
            teamIds.count == 1,
            teamIds[0] != Preferences.personalScopeIdentifier
        {
            urlString = "https://vercel.com/\(teamIds[0])/deployments"
        }
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openDeployment(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openPreferences(_ sender: Any?) {
        PreferencesWindowController.shared.show()
    }

    @objc private func quitApp(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    private func startTickTimer() {
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(
            timeInterval: 1.0,
            target: self,
            selector: #selector(tick),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(tickTimer!, forMode: .common)
    }

    @objc private func tick() {
        updateStatusButton()
    }

    private func scheduleRefreshTimer(hasBuilding: Bool) {
        refreshTimer?.invalidate()
        let preferences = PreferencesStore.shared.current
        let idleInterval = TimeInterval(preferences.refreshIntervalIdle ?? 15)
        let buildingInterval = TimeInterval(preferences.refreshIntervalBuilding ?? 2)
        let interval: TimeInterval = hasBuilding ? buildingInterval : idleInterval
        refreshTimer = Timer.scheduledTimer(
            timeInterval: interval,
            target: self,
            selector: #selector(triggerRefreshTimer),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(refreshTimer!, forMode: .common)
    }

    @objc private func triggerRefreshTimer() {
        refreshDeployments()
    }

    private func refreshDeployments(userInitiated: Bool = false) {
        Task {
            do {
                let preferences = PreferencesStore.shared.current
                guard preferences.hasToken else {
                    await MainActor.run {
                        self.latestDeployments = []
                        self.lastError = nil
                        self.missingToken = true
                        self.buildMenu()
                        self.updateStatusButton()
                    }
                    return
                }

                let deployments = try await deploymentService.fetchAllDeployments(preferences: preferences)
                let filtered = filterDeployments(deployments, with: preferences)

                await MainActor.run {
                    self.latestDeployments = filtered
                    self.lastError = nil
                    self.missingToken = false
                    self.lastFetchDate = Date()
                    let hasBuilding = filtered.contains { $0.state == .building || $0.state == .queued }
                    self.scheduleRefreshTimer(hasBuilding: hasBuilding)
                    self.buildMenu()
                    self.updateStatusButton()
                }
            } catch {
                await MainActor.run {
                    self.latestDeployments = []
                    self.lastError = error
                    self.missingToken = false
                    self.buildMenu()
                    self.updateStatusButton()
                }
            }
        }
    }

    private func filterDeployments(_ deployments: [Deployment], with preferences: Preferences) -> [Deployment] {
        let normalizedProjectNames = preferences.normalizedProjectNameSet

        var filtered = deployments.filter { deployment in
            if !normalizedProjectNames.isEmpty {
                let normalizedDeploymentName = deployment.name.lowercased()
                guard normalizedProjectNames.contains(normalizedDeploymentName) else { return false }
            }

            switch deployment.state {
            case .ready:
                guard preferences.showReady else { return false }
            case .building:
                guard preferences.showBuilding else { return false }
            case .error:
                guard preferences.showError else { return false }
            case .queued:
                guard preferences.showQueued else { return false }
            case .canceled:
                guard preferences.showCanceled else { return false }
            case .unknown:
                break
            }

            if let target = deployment.target?.lowercased() {
                if target == "production", !preferences.showProduction {
                    return false
                }
                if target == "preview", !preferences.showPreview {
                    return false
                }
            }

            if !preferences.branchList.isEmpty {
                let branch = (deployment.gitSource?.ref ?? deployment.meta?.githubCommitRef ?? "").lowercased()
                if branch.isEmpty || !preferences.branchList.contains(branch) {
                    return false
                }
            }

            return true
        }

        if let limit = preferences.limitByCount, limit > 0 {
            filtered = Array(filtered.prefix(limit))
        } else if let hours = preferences.limitByHours, hours > 0 {
            let cutoff = Date().addingTimeInterval(TimeInterval(-hours * 3600))
            filtered = filtered.filter { $0.createdDate >= cutoff }
        }

        return filtered.sorted { $0.created > $1.created }
    }

    private func updateStatusButton() {
        guard let button = statusItem.button else { return }

        if missingToken {
            button.title = "No Token"
            button.image = NSImage(systemSymbolName: "key.slash", accessibilityDescription: nil)
            return
        }

        guard lastError == nil else {
            button.title = "Error"
            button.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
            return
        }

        guard let latest = latestDeployments.first else {
            button.title = "VRC"
            button.image = NSImage(systemSymbolName: "circle", accessibilityDescription: nil)
            return
        }

        button.image = icon(for: latest.state)
        button.title = formattedStatusTitle(for: latest)
    }

    private func formattedStatusTitle(for deployment: Deployment) -> String {
        let label = String(deployment.name.prefix(3)).uppercased()
        switch deployment.state {
        case .building:
            let elapsed = Date().timeIntervalSince(deployment.buildingAtDate)
            return "\(label) \(formatDuration(elapsed))"
        case .queued:
            let elapsed = Date().timeIntervalSince(deployment.createdDate)
            return "\(label) \(formatDuration(elapsed))"
        case .ready:
            if let readyDate = deployment.readyDate {
                let elapsed = readyDate.timeIntervalSince(deployment.buildingAtDate)
                return "\(label) \(formatDuration(max(elapsed, 0)))"
            }
            return label
        case .error:
            if let readyDate = deployment.readyDate {
                let elapsed = readyDate.timeIntervalSince(deployment.buildingAtDate)
                let formatted = formatDuration(max(elapsed, 0))
                return "\(label) \(formatted)"
            }
            return label
        case .canceled, .unknown:
            return label
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let sec = Int(seconds)
        let hours = sec / 3600
        let minutes = (sec % 3600) / 60
        let remaining = sec % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m \(remaining)s"
        } else if minutes > 0 {
            return "\(minutes)m \(remaining)s"
        } else {
            return "\(remaining)s"
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    private func icon(for state: Deployment.State) -> NSImage? {
        let symbolName: String
        let color: NSColor

        switch state {
        case .ready:
            symbolName = "checkmark.circle.fill"
            color = .systemGreen
        case .error:
            symbolName = "xmark.circle.fill"
            color = .systemRed
        case .building:
            symbolName = "hourglass"
            color = .systemYellow
        case .queued:
            symbolName = "clock.fill"
            color = .systemOrange
        case .canceled:
            symbolName = "minus.circle.fill"
            color = .systemGray
        case .unknown:
            symbolName = "questionmark.circle"
            color = .systemGray
        }

        guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else {
            return nil
        }

        // Create a colored version of the image
        let coloredImage = NSImage(size: image.size)
        coloredImage.lockFocus()
        color.set()

        let rect = NSRect(origin: .zero, size: image.size)
        image.draw(in: rect, from: rect, operation: .sourceOver, fraction: 1.0)

        // Apply the color using a compositing operation
        rect.fill(using: .sourceAtop)

        coloredImage.unlockFocus()
        coloredImage.isTemplate = false

        return coloredImage
    }

    private func buildMenu() {
        menu.removeAllItems()

        if missingToken {
            menu.addItem(NSMenuItem(title: "Add your Vercel token in Preferences", action: nil, keyEquivalent: ""))
            menu.addItem(.separator())
        } else if let error = lastError {
            let errorItem = NSMenuItem(
                title: "Error: \(error.localizedDescription)",
                action: nil,
                keyEquivalent: ""
            )
            menu.addItem(errorItem)
            menu.addItem(.separator())
        }

        if latestDeployments.isEmpty && lastError == nil && !missingToken {
            menu.addItem(NSMenuItem(title: "No deployments found", action: nil, keyEquivalent: ""))
        } else if !missingToken {
            for deployment in latestDeployments {
                let title = menuTitle(for: deployment)
                let item = NSMenuItem(
                    title: title,
                    action: #selector(openDeployment(_:)),
                    keyEquivalent: ""
                )
                item.target = self

                if
                    let inspectorUrl = deployment.inspectorUrl,
                    !inspectorUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    let url = URL(string: inspectorUrl)
                {
                    item.representedObject = url
                } else {
                    let deploymentUrl: String
                    if deployment.url.hasPrefix("http://") || deployment.url.hasPrefix("https://") {
                        deploymentUrl = deployment.url
                    } else {
                        deploymentUrl = "https://\(deployment.url)"
                    }
                    if let url = URL(string: deploymentUrl) {
                        item.representedObject = url
                    }
                }
                item.toolTip = commitToolTip(for: deployment)
                item.image = icon(for: deployment.state)
                menu.addItem(item)
            }
        }

        if let lastFetchDate {
            menu.addItem(.separator())
            let formatter = DateFormatter()
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            let updatedTitle = "Last updated: \(formatter.string(from: lastFetchDate))"
            let updatedItem = NSMenuItem(title: updatedTitle, action: nil, keyEquivalent: "")
            updatedItem.isEnabled = false
            menu.addItem(updatedItem)
        }

        menu.addItem(.separator())

        let refreshItem = NSMenuItem(title: "Refresh Now", action: #selector(refreshFromMenu(_:)), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let dashboardItem = NSMenuItem(title: "Open Vercel Dashboard", action: #selector(openDashboard(_:)), keyEquivalent: "")
        dashboardItem.target = self
        menu.addItem(dashboardItem)

        let preferencesItem = NSMenuItem(title: "Preferences…", action: #selector(openPreferences(_:)), keyEquivalent: ",")
        preferencesItem.target = self
        menu.addItem(preferencesItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Vercel Deployment Menu Bar", action: #selector(quitApp(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func menuTitle(for deployment: Deployment) -> String {
        var components: [String] = []

        let gitBranch = deployment.gitSource?.ref ?? deployment.meta?.githubCommitRef ?? ""
        if gitBranch.isEmpty {
            components.append(deployment.name)
        } else {
            components.append("\(deployment.name) (\(gitBranch))")
        }

        var statusParts: [String] = []
        if let target = deployment.target {
            statusParts.append(target.capitalized)
        }

        switch deployment.state {
        case .building:
            statusParts.append("Building \(formatDuration(Date().timeIntervalSince(deployment.buildingAtDate)))")
        case .queued:
            statusParts.append("Queued \(formatDuration(Date().timeIntervalSince(deployment.createdDate)))")
        case .ready:
            if let readyDate = deployment.readyDate {
                let duration = readyDate.timeIntervalSince(deployment.buildingAtDate)
                statusParts.append("Ready \(formatDuration(max(duration, 0)))")
            } else {
                statusParts.append("Ready")
            }
        case .error:
            statusParts.append("Error")
        case .canceled:
            statusParts.append("Canceled")
        case .unknown:
            statusParts.append("Unknown")
        }

        let timeString = formatTime(deployment.buildingAtDate)
        statusParts.append(timeString)

        if !statusParts.isEmpty {
            components.append(statusParts.joined(separator: " • "))
        }

        return components.joined(separator: " — ")
    }

    private func commitToolTip(for deployment: Deployment) -> String? {
        Self.sanitizedCommitToolTip(from: deployment.meta?.githubCommitMessage)
    }

    static func sanitizedCommitToolTip(from rawMessage: String?) -> String? {
        guard let rawMessage else {
            return nil
        }

        let firstLine = rawMessage
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? ""
        guard !firstLine.isEmpty else {
            return nil
        }

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
        let cutoff = collapsed.index(collapsed.startIndex, offsetBy: maxLength - 1)
        return String(collapsed[..<cutoff]) + "…"
    }
}
