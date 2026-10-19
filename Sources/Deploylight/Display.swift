import AppKit

enum Formatting {
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    static func time(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    static func duration(_ seconds: TimeInterval, format: TimeFormat) -> String {
        let total = max(Int(seconds), 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remaining = total % 60

        switch format {
        case .clock:
            return hours > 0
                ? String(format: "%d:%02d:%02d", hours, minutes, remaining)
                : String(format: "%d:%02d", minutes, remaining)
        case .units:
            if hours > 0 { return "\(hours)h \(minutes)m \(remaining)s" }
            if minutes > 0 { return "\(minutes)m \(remaining)s" }
            return "\(remaining)s"
        case .minutes:
            if hours > 0 { return "\(hours)h \(minutes)m" }
            return minutes > 0 ? "\(minutes)m" : "<1m"
        }
    }

    /// What a deployment is doing, with its build time: "Building 1:12", "Built in 2:56",
    /// "Failed after 0:45". Finished times run from the build starting to it finishing.
    static func status(of deployment: Deployment, format: TimeFormat, now: Date = Date()) -> String {
        let duration = deployment.elapsed(now: now).map { duration($0, format: format) }
        switch deployment.state {
        case .building: return duration.map { "Building \($0)" } ?? "Building"
        case .queued: return duration.map { "Queued \($0)" } ?? "Queued"
        case .ready: return duration.map { "Built in \($0)" } ?? "Ready"
        case .error: return duration.map { "Failed after \($0)" } ?? "Failed"
        case .canceled: return "Canceled"
        case .unknown: return "Unknown"
        }
    }

    /// A short relative age: "just now", "20m ago", "3h ago", "2d ago", "3w ago".
    static func age(of date: Date, now: Date = Date()) -> String {
        let seconds = max(Int(now.timeIntervalSince(date)), 0)
        switch seconds {
        case ..<60: return "just now"
        case ..<3600: return "\(seconds / 60)m ago"
        case ..<86_400: return "\(seconds / 3600)h ago"
        case ..<(14 * 86_400): return "\(seconds / 86_400)d ago"
        default: return "\(seconds / (7 * 86_400))w ago"
        }
    }
}

/// The text next to the status icon in the menu bar.
enum StatusTitle {
    static func text(
        projectName: String,
        state: Deployment.State,
        elapsed: TimeInterval?,
        style: MenuBarStyle,
        timeFormat: TimeFormat
    ) -> String {
        switch style {
        case .compact:
            return ""
        case .auto where !state.isActive:
            return ""
        case .auto, .detailed:
            let label = String(projectName.prefix(3)).uppercased()
            guard let elapsed else { return label }
            return "\(label) \(Formatting.duration(elapsed, format: timeFormat))"
        }
    }
}

extension Deployment {
    /// Time spent building so far, or the final build time once finished.
    func elapsed(now: Date = Date()) -> TimeInterval? {
        switch state {
        case .building:
            return now.timeIntervalSince(buildStartedAt)
        case .queued:
            return now.timeIntervalSince(createdAt)
        case .ready, .error:
            return finishedAt.map { max($0.timeIntervalSince(buildStartedAt), 0) }
        case .canceled, .unknown:
            return nil
        }
    }
}

extension Deployment.State {
    var symbolName: String {
        switch self {
        case .ready: "checkmark.circle.fill"
        case .error: "xmark.circle.fill"
        case .building: "hourglass"
        case .queued: "clock.circle.fill"
        case .canceled: "minus.circle.fill"
        case .unknown: "questionmark.circle"
        }
    }

    var color: NSColor {
        switch self {
        case .ready: .systemGreen
        case .error: .systemRed
        case .building: .systemYellow
        case .queued: .systemOrange
        case .canceled, .unknown: .systemGray
        }
    }

    /// Palette colors for the symbol's layers. A single color would paint a filled
    /// symbol's inner glyph the same as its background, leaving a blank disc.
    var symbolColors: [NSColor] {
        switch self {
        case .ready, .error, .queued, .canceled: [.white, color]
        case .building, .unknown: [color]
        }
    }
}

@MainActor
enum StatusIcon {
    private static var cache: [Deployment.State: NSImage] = [:]

    static func image(for state: Deployment.State) -> NSImage? {
        if let cached = cache[state] {
            return cached
        }
        let image = NSImage(systemSymbolName: state.symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: state.symbolColors))
        cache[state] = image
        return image
    }
}
