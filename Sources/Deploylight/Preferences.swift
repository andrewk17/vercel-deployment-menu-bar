import Foundation

/// What the menu bar item shows next to the status icon.
enum MenuBarStyle: String, Codable, CaseIterable {
    /// The project and build time while a build is running, otherwise just the icon.
    case auto
    /// Just the icon.
    case compact
    /// The project and build time, always.
    case detailed
}

/// How build durations are written.
enum TimeFormat: String, Codable, CaseIterable {
    /// "2:14"
    case clock
    /// "2m 14s"
    case units
    /// "2m"
    case minutes
}

/// How menu rows show which provider a deployment came from, when more than one is in use.
enum ProviderStyle: String, Codable, CaseIterable {
    case icon
    case name
    case hidden
}

/// How menu rows show whether a deployment is production or preview.
enum EnvironmentStyle: String, Codable, CaseIterable {
    /// A colored badge, filled for production and outlined for preview.
    case badge
    case text
    case hidden
}

struct Preferences: Codable, Equatable {
    static let personalScopeIdentifier = "__personal__"

    var vercelToken: String
    /// Comma-separated Vercel team IDs; empty means all accessible scopes.
    var teamId: String
    /// Comma-separated Vercel project names; empty means all.
    var projectName: String
    var cloudflareToken: String
    /// Comma-separated Cloudflare account IDs; empty means all accessible accounts.
    var cloudflareAccountIds: String
    /// Comma-separated Worker names; empty means all.
    var cloudflareWorkers: String
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
    var menuBarStyle: MenuBarStyle
    var timeFormat: TimeFormat
    /// Whether the menu lists each project's latest deployment below the recent ones.
    var showProjects: Bool
    var providerStyle: ProviderStyle
    var environmentStyle: EnvironmentStyle

    static let `default` = Preferences(
        vercelToken: "",
        teamId: "",
        projectName: "",
        cloudflareToken: "",
        cloudflareAccountIds: "",
        cloudflareWorkers: "",
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
        refreshIntervalBuilding: 2,
        menuBarStyle: .auto,
        timeFormat: .clock,
        showProjects: true,
        providerStyle: .icon,
        environmentStyle: .badge
    )

    var hasVercelToken: Bool {
        !vercelToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasCloudflareToken: Bool {
        !cloudflareToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var teamIdList: [String] {
        commaSeparatedList(from: teamId)
    }

    var projectNameList: [String] {
        commaSeparatedList(from: projectName)
    }

    var cloudflareAccountIdList: [String] {
        commaSeparatedList(from: cloudflareAccountIds)
    }

    var cloudflareWorkerList: [String] {
        commaSeparatedList(from: cloudflareWorkers)
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

extension Preferences {
    /// Missing keys fall back to defaults so preferences saved by older versions still load.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Preferences.default

        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) throws -> T {
            try container.decodeIfPresent(T.self, forKey: key) ?? fallback
        }

        self.init(
            vercelToken: try value(.vercelToken, defaults.vercelToken),
            teamId: try value(.teamId, defaults.teamId),
            projectName: try value(.projectName, defaults.projectName),
            cloudflareToken: try value(.cloudflareToken, defaults.cloudflareToken),
            cloudflareAccountIds: try value(.cloudflareAccountIds, defaults.cloudflareAccountIds),
            cloudflareWorkers: try value(.cloudflareWorkers, defaults.cloudflareWorkers),
            gitBranches: try value(.gitBranches, defaults.gitBranches),
            showProduction: try value(.showProduction, defaults.showProduction),
            showPreview: try value(.showPreview, defaults.showPreview),
            showReady: try value(.showReady, defaults.showReady),
            showBuilding: try value(.showBuilding, defaults.showBuilding),
            showError: try value(.showError, defaults.showError),
            showQueued: try value(.showQueued, defaults.showQueued),
            showCanceled: try value(.showCanceled, defaults.showCanceled),
            // A missing optional was saved as nil (cleared), so it stays nil.
            limitByCount: try container.decodeIfPresent(Int.self, forKey: .limitByCount),
            limitByHours: try container.decodeIfPresent(Int.self, forKey: .limitByHours),
            refreshIntervalIdle: try container.decodeIfPresent(Int.self, forKey: .refreshIntervalIdle),
            refreshIntervalBuilding: try container.decodeIfPresent(Int.self, forKey: .refreshIntervalBuilding),
            // An unrecognized style (say, from a newer version) falls back to the default.
            menuBarStyle: MenuBarStyle(rawValue: try value(.menuBarStyle, defaults.menuBarStyle.rawValue)) ?? defaults.menuBarStyle,
            timeFormat: TimeFormat(rawValue: try value(.timeFormat, defaults.timeFormat.rawValue)) ?? defaults.timeFormat,
            showProjects: try value(.showProjects, defaults.showProjects),
            providerStyle: ProviderStyle(rawValue: try value(.providerStyle, defaults.providerStyle.rawValue)) ?? defaults.providerStyle,
            environmentStyle: EnvironmentStyle(rawValue: try value(.environmentStyle, defaults.environmentStyle.rawValue)) ?? defaults.environmentStyle
        )
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
