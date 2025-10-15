import Foundation

struct Preferences: Codable, Equatable {
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

    var branchList: [String] {
        gitBranches
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }
}

final class PreferencesStore {
    static let shared = PreferencesStore()

    static let didChangeNotification = Notification.Name("PreferencesStoreDidChange")

    private let storageKey = "vercelStatusPreferences"
    private let userDefaults: UserDefaults

    private(set) var current: Preferences {
        didSet {
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

    func save(_ preferences: Preferences) {
        current = preferences
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(current) {
            userDefaults.set(data, forKey: storageKey)
        }
    }
}

struct Team: Decodable {
    let id: String
    let slug: String
    let name: String
}

struct TeamsResponse: Decodable {
    let teams: [Team]
}

struct Deployment: Decodable {
    enum State: String, Decodable {
        case building = "BUILDING"
        case error = "ERROR"
        case ready = "READY"
        case queued = "QUEUED"
        case canceled = "CANCELED"
        case unknown

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            self = State(rawValue: rawValue) ?? .unknown
        }
    }

    struct Creator: Decodable {
        let username: String?
    }

    struct Meta: Decodable {
        let githubCommitMessage: String?
        let githubCommitRef: String?
    }

    struct GitSource: Decodable {
        let ref: String?
        let type: String?
    }

    let uid: String
    let name: String
    let url: String
    let created: TimeInterval
    let state: State
    let ready: TimeInterval?
    let buildingAt: TimeInterval?
    let target: String?
    let creator: Creator
    let meta: Meta?
    let gitSource: GitSource?

    enum CodingKeys: String, CodingKey {
        case uid
        case name
        case url
        case created
        case state
        case ready
        case buildingAt
        case target
        case creator
        case meta
        case gitSource
    }

    var createdDate: Date {
        Date(timeIntervalSince1970: created / 1000)
    }

    var readyDate: Date? {
        ready.map { Date(timeIntervalSince1970: $0 / 1000) }
    }

    var buildingAtDate: Date {
        let timestamp = buildingAt ?? created
        return Date(timeIntervalSince1970: timestamp / 1000)
    }
}

struct DeploymentsResponse: Decodable {
    let deployments: [Deployment]
}

enum APIError: LocalizedError {
    case missingToken
    case invalidResponse(status: Int, message: String)
    case decodingFailure

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "Vercel token is missing. Please update Preferences."
        case let .invalidResponse(status, message):
            return "Vercel API error (\(status)): \(message)"
        case .decodingFailure:
            return "Failed to decode response from Vercel."
        }
    }
}
