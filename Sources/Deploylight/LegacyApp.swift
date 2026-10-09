import AppKit
import ServiceManagement

/// Deploylight used to be called Vercel Deployment Menu Bar and keeps its bundle ID, so
/// installing it leaves the old app beside it, sharing its settings. Once Deploylight is
/// installed, it offers to quit the old app and move it to the Trash.
@MainActor
enum LegacyApp {
    static let bundleName = "Vercel Deployment Menu Bar.app"
    private static let declinedKey = "declinedLegacyAppRemoval"

    static func offerReplacement() {
        // Only an installed copy replaces the old app, never a development build or a
        // copy opened from Downloads or a disk image.
        guard
            let bundleID = Bundle.main.bundleIdentifier,
            isInApplicationsFolder(Bundle.main.bundleURL),
            !UserDefaults.standard.bool(forKey: declinedKey)
        else { return }

        let oldInstalls = applicationsFolders()
            .map { $0.appendingPathComponent(bundleName) }
            .filter { Bundle(url: $0)?.bundleIdentifier == bundleID }
        guard !oldInstalls.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "Move Vercel Deployment Menu Bar to the Trash?"
        alert.informativeText = "Deploylight is its new name, and your tokens and settings are already here. This quits the old app and moves it to the Trash:\n\n"
            + oldInstalls.map(\.path).joined(separator: "\n")
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Keep It")

        // The old app was often a login item, which stops working once it's gone.
        let openAtLogin = NSButton(checkboxWithTitle: "Open Deploylight at login", target: nil, action: nil)
        openAtLogin.state = .on
        alert.accessoryView = openAtLogin

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else {
            UserDefaults.standard.set(true, forKey: declinedKey)
            return
        }

        if openAtLogin.state == .on {
            do {
                try LoginItem.setEnabled(true)
            } catch {
                // Keep the old app, and ask again next launch, rather than lose the login item.
                NSAlert(error: error).runModal()
                return
            }
        }

        for app in NSWorkspace.shared.runningApplications where oldInstalls.contains(where: { $0.standardizedFileURL == app.bundleURL?.standardizedFileURL }) {
            app.terminate()
        }
        NSWorkspace.shared.recycle(oldInstalls) { _, error in
            guard let error else { return }
            Task { @MainActor in
                NSAlert(error: error).runModal()
            }
        }
    }

    nonisolated static func isInApplicationsFolder(_ url: URL, folders: [URL] = applicationsFolders()) -> Bool {
        let parent = url.standardizedFileURL.deletingLastPathComponent().path
        return folders.contains { $0.standardizedFileURL.path == parent }
    }

    nonisolated static func applicationsFolders() -> [URL] {
        FileManager.default.urls(for: .applicationDirectory, in: [.localDomainMask, .userDomainMask])
    }
}

/// Opening at login, which the system keeps track of rather than Preferences.
@MainActor
enum LoginItem {
    /// Only an app bundle can be registered, not a bare development build.
    static var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    static func setEnabled(_ enabled: Bool) throws {
        guard isAvailable else { return }
        if enabled {
            try SMAppService.mainApp.register()
            // macOS can hold a new login item until it's allowed in System Settings.
            if status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
