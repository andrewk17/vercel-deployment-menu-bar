import Foundation

struct Preferences: Codable, Equatable {
    static let personalScopeIdentifier = "__personal__"

    var vercelToken: String
    var teamId: String
    var projectName: String
    var gitBranches: String
    var showProduction: Bool
    var showPreview: Bool
    var showReady: Bool
    var showBuilding: Bool
    var showError: Bool
    var showQueued: Bool
    var showCanceled: Bool
    var limitByCount: Int?
    var limitByHours: Int?
    var refreshIntervalIdle: Int?
    var refreshIntervalBuilding: Int?

    static let `default` = Preferences(
        vercelToken: "",
        teamId: "",
        projectName: "",
        gitBranches: "",
        showProduction: true,
        showPreview: true,
        showReady: true,
        showBuilding: true,
        showError: true,
        showQueued: true,
        showCanceled: true,
        limitByCount: 5,
        limitByHours: nil,
        refreshIntervalIdle: 15,
        refreshIntervalBuilding: 2
    )

    var hasToken: Bool {
        !vercelToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var teamIdList: [String] {
        commaSeparatedList(from: teamId)
    }

    var projectNameList: [String] {
        commaSeparatedList(from: projectName)
    }

    var normalizedProjectNameSet: Set<String> {
        Set(projectNameList.map { $0.lowercased() })
    }

    var branchList: [String] {
        commaSeparatedList(from: gitBranches).map { $0.lowercased() }
    }

    private func commaSeparatedList(from value: String) -> [String] {
        var results: [String] = []
        var seen: Set<String> = []

        for token in value.split(separator: ",") {
            let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let normalized = trimmed.lowercased()
            guard seen.insert(normalized).inserted else { continue }
            results.append(trimmed)
        }

        return results
    }
}

final class PreferencesStore {
    static let shared = PreferencesStore()

    static let didChangeNotification = Notification.Name("PreferencesStoreDidChange")

    private let storageKey = "vercelStatusPreferences"
    private let userDefaults: UserDefaults

    private(set) var current: Preferences {
        didSet {
            guard current != oldValue else { return }
            persist()
            NotificationCenter.default.post(name: Self.didChangeNotification, object: current)
        }
    }

    private init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if
            let data = userDefaults.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode(Preferences.self, from: data)
        {
            current = decoded
        } else {
            current = .default
        }
    }

    func update(_ transform: (inout Preferences) -> Void) {
        var updated = current
        transform(&updated)
        current = updated
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(current) {
            userDefaults.set(data, forKey: storageKey)
        }
    }
}
