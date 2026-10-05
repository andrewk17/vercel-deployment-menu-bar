import AppKit

/// Builds the text of the menu's deployment and project rows, such as
/// "web (main) — Preview • Built in 2:03 • 5:04 PM", with the provider drawn as a
/// leading icon and the environment as a badge when those styles are chosen.
@MainActor
struct MenuRowFormatter {
    /// False when only one provider is in use, since marking it would add nothing.
    var showsProvider: Bool
    var providerStyle: ProviderStyle
    var environmentStyle: EnvironmentStyle
    var timeFormat: TimeFormat
    var font: NSFont
    var now = Date()

    init(preferences: Preferences, showsProvider: Bool, font: NSFont, now: Date = Date()) {
        self.showsProvider = showsProvider
        providerStyle = preferences.providerStyle
        environmentStyle = preferences.environmentStyle
        timeFormat = preferences.timeFormat
        self.font = font
        self.now = now
    }

    fileprivate enum Part {
        case provider(Deployment.Provider)
        case environment(Deployment.Target)
        case text(String)
    }

    func title(for deployment: Deployment, includeProject: Bool) -> MenuRowTitle {
        let name: String
        switch (includeProject, deployment.branch) {
        case let (true, branch?): name = "\(deployment.projectName) (\(branch))"
        case (true, nil): name = deployment.projectName
        case let (false, branch?): name = branch
        case (false, nil): name = "No branch"
        }

        var parts: [Part] = []
        if includeProject {
            parts += providerParts(deployment.provider)
        }
        if let target = deployment.target, environmentStyle != .hidden {
            parts.append(.environment(target))
        }
        parts.append(.text(Formatting.status(of: deployment, format: timeFormat, now: now)))
        parts.append(.text(Formatting.time(deployment.buildStartedAt)))
        return MenuRowTitle(name: name, parts: parts, formatter: self)
    }

    /// A project's headline deployment. It's production unless the project has none, so
    /// only preview headlines are marked.
    func title(for project: ProjectSummary) -> MenuRowTitle {
        let headline = project.headline
        var parts = providerParts(project.provider)
        if headline.target == .preview, environmentStyle != .hidden {
            parts.append(.environment(.preview))
        }
        parts.append(.text(headline.state.isActive
            ? Formatting.status(of: headline, format: timeFormat, now: now)
            : Formatting.age(of: headline.createdAt, now: now)))
        return MenuRowTitle(name: project.name, parts: parts, formatter: self)
    }

    private func providerParts(_ provider: Deployment.Provider) -> [Part] {
        showsProvider && providerStyle != .hidden ? [.provider(provider)] : []
    }

    /// Lays out a row. The plain version spells out icons and badges, for comparing rows
    /// and for type-to-select.
    fileprivate func render(name: String, parts: [Part], rich: Bool) -> NSAttributedString {
        let result = NSMutableAttributedString()
        func append(_ text: String) {
            result.append(NSAttributedString(string: text, attributes: [.font: font]))
        }

        var details = parts
        if rich, providerStyle == .icon, case let .provider(provider)? = details.first {
            result.append(attachment(MenuGlyphs.providerIcon(provider, font: font)))
            append(" ")
            details.removeFirst()
        }
        append(name)

        var previousWasBadge = false
        for (index, part) in details.enumerated() {
            append(index == 0 ? " — " : previousWasBadge ? " " : " • ")
            previousWasBadge = false
            switch part {
            case let .provider(provider):
                append(provider.rawValue)
            case let .environment(target) where rich && environmentStyle == .badge:
                result.append(attachment(MenuGlyphs.environmentBadge(target, font: font)))
                previousWasBadge = true
            case let .environment(target):
                append(target.rawValue)
            case let .text(text):
                append(text)
            }
        }
        return result
    }

    /// Centers an icon on the text's capital letters.
    private func attachment(_ image: NSImage) -> NSAttributedString {
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = CGRect(
            x: 0,
            y: ((font.capHeight - image.size.height) / 2).rounded(),
            width: image.size.width,
            height: image.size.height
        )
        return NSAttributedString(attachment: attachment)
    }
}

/// A menu row's text, ready to show and to compare with what's already showing.
@MainActor
struct MenuRowTitle {
    let plain: String
    let attributed: NSAttributedString

    fileprivate init(name: String, parts: [MenuRowFormatter.Part], formatter: MenuRowFormatter) {
        plain = formatter.render(name: name, parts: parts, rich: false).string
        attributed = formatter.render(name: name, parts: parts, rich: true)
    }
}

@MainActor
enum MenuGlyphs {
    private struct Key: Hashable {
        let name: String
        let size: CGFloat
    }

    private static var cache: [Key: NSImage] = [:]

    /// A generic shape for each provider rather than its logo: a triangle for Vercel and
    /// an orange cloud for Cloudflare.
    static func providerIcon(_ provider: Deployment.Provider, font: NSFont) -> NSImage {
        cached(Key(name: provider.rawValue, size: font.pointSize)) {
            let (symbol, color): (String, NSColor) = switch provider {
            case .vercel: ("triangle.fill", .labelColor)
            case .cloudflare: ("cloud.fill", NSColor(srgbRed: 0.96, green: 0.51, blue: 0.13, alpha: 1))
            }
            let configuration = NSImage.SymbolConfiguration(pointSize: (font.pointSize * 0.8).rounded(), weight: .medium)
                .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
            guard let symbolImage = NSImage(systemSymbolName: symbol, accessibilityDescription: provider.rawValue)?
                .withSymbolConfiguration(configuration) else { return NSImage() }

            // A fixed-width box, so names line up whichever provider a row has.
            let box = NSSize(width: font.pointSize, height: symbolImage.size.height)
            let image = NSImage(size: box, flipped: false) { rect in
                let origin = NSPoint(x: (rect.width - symbolImage.size.width) / 2, y: 0)
                symbolImage.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
                return true
            }
            image.accessibilityDescription = provider.rawValue
            return image
        }
    }

    /// Production is filled in so it stands out; preview is outlined.
    static func environmentBadge(_ target: Deployment.Target, font: NSFont) -> NSImage {
        cached(Key(name: target.rawValue, size: font.pointSize)) {
            let text = target.rawValue as NSString
            let badgeFont = NSFont.systemFont(ofSize: (font.pointSize * 0.78).rounded(), weight: .semibold)
            let textSize = text.size(withAttributes: [.font: badgeFont])
            let size = NSSize(width: ceil(textSize.width) + 10, height: ceil(textSize.height) + 1)
            let isProduction = target == .production

            // Drawn on demand so the colors follow light and dark mode.
            let image = NSImage(size: size, flipped: false) { rect in
                let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
                let textColor: NSColor
                if isProduction {
                    NSColor.systemBlue.setFill()
                    path.fill()
                    textColor = .white
                } else {
                    NSColor.secondaryLabelColor.setStroke()
                    path.stroke()
                    textColor = .secondaryLabelColor
                }
                text.draw(
                    at: NSPoint(x: (rect.width - textSize.width) / 2, y: (rect.height - textSize.height) / 2),
                    withAttributes: [.font: badgeFont, .foregroundColor: textColor]
                )
                return true
            }
            image.accessibilityDescription = target.rawValue
            return image
        }
    }

    private static func cached(_ key: Key, make: () -> NSImage) -> NSImage {
        if let image = cache[key] {
            return image
        }
        let image = make()
        cache[key] = image
        return image
    }
}
