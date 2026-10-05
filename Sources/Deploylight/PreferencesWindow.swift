import AppKit
import SwiftUI

@MainActor
final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    static let shared = PreferencesWindowController()

    private let viewModel = PreferencesViewModel(store: PreferencesStore.shared)

    private init() {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        for pane in PreferencesPane.allCases {
            let host = NSHostingController(rootView: pane.view(viewModel: viewModel))
            host.sizingOptions = .preferredContentSize
            host.title = pane.title
            let item = NSTabViewItem(viewController: host)
            item.label = pane.title
            item.image = NSImage(systemSymbolName: pane.symbolName, accessibilityDescription: pane.title)
            tabs.addTabViewItem(item)
        }

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }
        viewModel.reset()
        if !window.isVisible {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        // Otherwise the first token field takes focus with its contents selected.
        window.makeFirstResponder(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        viewModel.save()
    }
}

enum PreferencesPane: CaseIterable {
    case general
    case menu
    case accounts
    case filters

    var title: String {
        switch self {
        case .general: "General"
        case .menu: "Menu"
        case .accounts: "Accounts"
        case .filters: "Filters"
        }
    }

    var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .menu: "filemenu.and.selection"
        case .accounts: "person.crop.circle"
        case .filters: "line.3.horizontal.decrease.circle"
        }
    }

    /// Accounts scrolls once providers list their teams and Workers; the others fit.
    private var height: CGFloat {
        switch self {
        case .general: 350
        case .menu: 545
        case .accounts: 600
        case .filters: 480
        }
    }

    @MainActor
    func view(viewModel: PreferencesViewModel) -> AnyView {
        let content: AnyView = switch self {
        case .general: AnyView(GeneralPane(viewModel: viewModel))
        case .menu: AnyView(MenuPane(viewModel: viewModel))
        case .accounts: AnyView(AccountsPane(viewModel: viewModel))
        case .filters: AnyView(FiltersPane(viewModel: viewModel))
        }
        return AnyView(content.formStyle(.grouped).frame(width: 540, height: height))
    }
}

// MARK: - General

struct GeneralPane: View {
    @ObservedObject var viewModel: PreferencesViewModel

    var body: some View {
        Form {
            Section("Menu Bar") {
                MenuBarPreview(style: viewModel.menuBarStyle, timeFormat: viewModel.timeFormat)

                Picker("Show project and build time", selection: $viewModel.menuBarStyle) {
                    Text("While Building").tag(MenuBarStyle.auto)
                    Text("Always").tag(MenuBarStyle.detailed)
                    Text("Never").tag(MenuBarStyle.compact)
                }

                Picker("Time format", selection: $viewModel.timeFormat) {
                    ForEach(TimeFormat.allCases, id: \.self) { format in
                        Text(Formatting.duration(134, format: format)).tag(format)
                    }
                }
            }

            Section("Refresh") {
                Picker("When idle, check every", selection: $viewModel.refreshIntervalIdle) {
                    ForEach(pickerOptions([15, 30, 60, 300], including: viewModel.refreshIntervalIdle), id: \.self) { seconds in
                        Text(Self.secondsLabel(seconds)).tag(seconds)
                    }
                }

                Picker("While building, check every", selection: $viewModel.refreshIntervalBuilding) {
                    ForEach(pickerOptions([2, 5, 10, 30], including: viewModel.refreshIntervalBuilding), id: \.self) { seconds in
                        Text(Self.secondsLabel(seconds)).tag(seconds)
                    }
                }
            }
        }
    }

    private static func secondsLabel(_ seconds: Int) -> String {
        if seconds >= 60, seconds % 60 == 0 {
            let minutes = seconds / 60
            return minutes == 1 ? "Minute" : "\(minutes) Minutes"
        }
        return "\(seconds) Seconds"
    }
}

/// Preset choices plus the current value, so settings saved outside the presets still show.
private func pickerOptions(_ presets: [Int], including current: Int) -> [Int] {
    current > 0 ? Array(Set(presets + [current])).sorted() : presets
}

/// How the menu bar item looks with the chosen settings, idle and mid-build.
private struct MenuBarPreview: View {
    let style: MenuBarStyle
    let timeFormat: TimeFormat

    var body: some View {
        HStack(spacing: 32) {
            sample("Idle", state: .ready, elapsed: 134)
            sample("Building", state: .building, elapsed: 72)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private func sample(_ caption: String, state: Deployment.State, elapsed: TimeInterval) -> some View {
        let title = StatusTitle.text(projectName: "web", state: state, elapsed: elapsed, style: style, timeFormat: timeFormat)

        return VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: state.symbolName)
                    .foregroundStyle(Color(nsColor: state.color))
                if !title.isEmpty {
                    Text(title)
                        .font(.system(size: 13, weight: .medium).monospacedDigit())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))

            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Menu

struct MenuPane: View {
    @ObservedObject var viewModel: PreferencesViewModel

    var body: some View {
        Form {
            Section {
                MenuRowPreview(
                    providerStyle: viewModel.providerStyle,
                    environmentStyle: viewModel.environmentStyle,
                    timeFormat: viewModel.timeFormat
                )

                Picker("Provider", selection: $viewModel.providerStyle) {
                    Text("Icon").tag(ProviderStyle.icon)
                    Text("Name").tag(ProviderStyle.name)
                    Text("Hidden").tag(ProviderStyle.hidden)
                }

                Picker("Environment", selection: $viewModel.environmentStyle) {
                    Text("Colored Badge").tag(EnvironmentStyle.badge)
                    Text("Text").tag(EnvironmentStyle.text)
                    Text("Hidden").tag(EnvironmentStyle.hidden)
                }
            } header: {
                Text("Rows")
            } footer: {
                Text("The provider shows when both Vercel and Cloudflare are connected. Build times run from the start of the build to the end.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section {
                Picker("Show up to", selection: $viewModel.limitByCount) {
                    ForEach(pickerOptions([3, 5, 10, 20], including: viewModel.limitByCount), id: \.self) { count in
                        Text("\(count) deployments").tag(count)
                    }
                    Divider()
                    Text("No Limit").tag(0)
                }

                Picker("From the last", selection: $viewModel.limitByHours) {
                    Text("Any Time").tag(0)
                    Divider()
                    ForEach(pickerOptions([1, 6, 24, 168], including: viewModel.limitByHours), id: \.self) { hours in
                        Text(Self.hoursLabel(hours)).tag(hours)
                    }
                }
            } header: {
                Text("Recent")
            } footer: {
                Text("Builds in progress always show.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section {
                Toggle("Show Projects section", isOn: $viewModel.showProjects)
            } header: {
                Text("Projects")
            } footer: {
                Text("Lists each project's latest production deployment, with its recent history on hover.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private static func hoursLabel(_ hours: Int) -> String {
        switch hours {
        case 1: "Hour"
        case 24: "Day"
        case 168: "Week"
        default: "\(hours) Hours"
        }
    }
}

/// Sample menu rows drawn the same way as the real menu, with both providers shown.
private struct MenuRowPreview: View {
    let providerStyle: ProviderStyle
    let environmentStyle: EnvironmentStyle
    let timeFormat: TimeFormat

    var body: some View {
        let now = Date()
        var preferences = Preferences.default
        preferences.providerStyle = providerStyle
        preferences.environmentStyle = environmentStyle
        preferences.timeFormat = timeFormat
        let formatter = MenuRowFormatter(preferences: preferences, showsProvider: true, font: .menuFont(ofSize: 0), now: now)

        return VStack(alignment: .leading, spacing: 6) {
            ForEach(Self.samples(now: now), id: \.id) { deployment in
                HStack(spacing: 6) {
                    if let icon = StatusIcon.image(for: deployment.state) {
                        Image(nsImage: icon)
                            .frame(width: 16)
                    }
                    AttributedLabel(text: formatter.title(for: deployment, includeProject: true).attributed)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
    }

    private static func samples(now: Date) -> [Deployment] {
        func sample(_ id: String, _ provider: Deployment.Provider, _ project: String, _ state: Deployment.State, _ target: Deployment.Target, _ branch: String, started: TimeInterval, took: TimeInterval?) -> Deployment {
            let start = now.addingTimeInterval(-started)
            return Deployment(
                id: id,
                provider: provider,
                projectName: project,
                state: state,
                target: target,
                branch: branch,
                commitMessage: nil,
                createdAt: start,
                buildStartedAt: start,
                finishedAt: took.map { start.addingTimeInterval($0) },
                link: nil
            )
        }

        return [
            sample("1", .vercel, "web", .building, .preview, "login-page", started: 72, took: nil),
            sample("2", .cloudflare, "api", .ready, .production, "main", started: 900, took: 134),
        ]
    }
}

/// Shows an attributed string with its icons, which SwiftUI's Text can't draw.
private struct AttributedLabel: NSViewRepresentable {
    let text: NSAttributedString

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(labelWithAttributedString: text)
        field.lineBreakMode = .byTruncatingTail
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        field.attributedStringValue = text
    }
}

// MARK: - Accounts

struct AccountsPane: View {
    @ObservedObject var viewModel: PreferencesViewModel

    var body: some View {
        Form {
            Section {
                TokenRow(
                    token: $viewModel.vercelToken,
                    createLabel: "Create a Vercel token…",
                    createURL: URL(string: "https://vercel.com/account/tokens")!
                )
                if viewModel.hasVercelToken {
                    SelectionRows(
                        title: "Teams",
                        allLabel: "All Teams",
                        specificLabel: "Specific Teams",
                        mode: $viewModel.teamSelectionMode,
                        selection: $viewModel.selectedTeamScopeIDs,
                        options: viewModel.availableTeamScopes,
                        isLoading: viewModel.teamsLoading
                    )
                    SelectionRows(
                        title: "Projects",
                        allLabel: "All Projects",
                        specificLabel: "Specific Projects",
                        mode: $viewModel.projectSelectionMode,
                        selection: $viewModel.selectedProjectNames,
                        options: viewModel.availableProjects,
                        isLoading: viewModel.projectsLoading
                    )
                }
            } header: {
                ProviderHeader(title: "Vercel", status: viewModel.vercelStatus) {
                    viewModel.refreshVercelOptions(reloadTeams: true)
                }
            } footer: {
                switch viewModel.vercelStatus {
                case let .failed(message):
                    Text(message).foregroundStyle(.red)
                case .connected:
                    if let message = viewModel.vercelOptionsErrorMessage {
                        Text("Couldn’t list teams: \(message)").foregroundStyle(.secondary)
                    }
                case .notConnected, .checking:
                    EmptyView()
                }
            }

            Section {
                TokenRow(
                    token: $viewModel.cloudflareToken,
                    createLabel: "Create a Cloudflare user token…",
                    createURL: URL(string: "https://dash.cloudflare.com/profile/api-tokens")!
                )
                if viewModel.hasCloudflareToken {
                    SelectionRows(
                        title: "Accounts",
                        allLabel: "All Accounts",
                        specificLabel: "Specific Accounts",
                        mode: $viewModel.cloudflareAccountMode,
                        selection: $viewModel.selectedCloudflareAccountIDs,
                        options: viewModel.availableCloudflareAccounts,
                        isLoading: viewModel.cloudflareLoading
                    )
                    SelectionRows(
                        title: "Workers",
                        allLabel: "All Workers",
                        specificLabel: "Specific Workers",
                        mode: $viewModel.cloudflareWorkerMode,
                        selection: $viewModel.selectedCloudflareWorkers,
                        options: viewModel.availableCloudflareWorkers,
                        isLoading: viewModel.cloudflareLoading
                    )
                }
            } header: {
                ProviderHeader(title: "Cloudflare", status: viewModel.cloudflareStatus) {
                    viewModel.refreshCloudflareOptions()
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if case let .failed(message) = viewModel.cloudflareStatus {
                        Text(message).foregroundStyle(.red)
                    }
                    Text("Use a user API token with Workers Builds Configuration: Read and Workers Scripts: Read. Shows Workers connected to git with Workers Builds; Workers deployed directly with Wrangler have no builds.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct ProviderHeader: View {
    let title: String
    let status: ConnectionStatus
    let refresh: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
            Spacer()
            StatusBadge(status: status)
            if status != .notConnected {
                Button(action: refresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Check the connection again")
                .disabled(status == .checking)
            }
        }
    }
}

private struct StatusBadge: View {
    let status: ConnectionStatus

    var body: some View {
        switch status {
        case .notConnected:
            label("Not connected", color: .secondary)
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Checking…").foregroundStyle(.secondary)
            }
            .font(.callout)
        case let .connected(summary):
            label("Connected · \(summary)", color: .green)
        case let .failed(message):
            label("Couldn’t connect", color: .red)
                .help(message)
        }
    }

    private func label(_ text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).foregroundStyle(.secondary)
        }
        .font(.callout)
    }
}

private struct TokenRow: View {
    @Binding var token: String
    let createLabel: String
    let createURL: URL
    @State private var isRevealed = false

    var body: some View {
        LabeledContent("API token") {
            HStack(spacing: 6) {
                Group {
                    if isRevealed {
                        TextField("", text: $token, prompt: Text("Paste your token"))
                            .font(.system(.body, design: .monospaced))
                    } else {
                        PasteableSecureField(text: $token, placeholder: "Paste your token")
                    }
                }
                .frame(width: 240)

                Button {
                    isRevealed.toggle()
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .help(isRevealed ? "Hide token" : "Show token")
            }
        }

        if token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Link(createLabel, destination: createURL)
        }
    }
}

/// An "all" / "specific" picker, with a checkbox per option for the specific case.
private struct SelectionRows: View {
    let title: String
    let allLabel: String
    let specificLabel: String
    @Binding var mode: SelectionMode
    @Binding var selection: Set<String>
    let options: [SelectionOption]
    let isLoading: Bool

    var body: some View {
        Picker(title, selection: $mode) {
            Text(allLabel).tag(SelectionMode.all)
            Text(specificLabel).tag(SelectionMode.selected)
        }

        if mode == .selected {
            if isLoading {
                ProgressView().controlSize(.small)
            } else if options.isEmpty {
                Text("Nothing to choose from yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(options) { option in
                    Toggle(isOn: isSelected(option.id)) {
                        Text(option.title)
                        if let subtitle = option.subtitle {
                            Text(subtitle)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
                // An empty selection is saved as "all".
                if selection.isEmpty {
                    Text("Nothing selected, so all are shown.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func isSelected(_ id: String) -> Binding<Bool> {
        Binding(
            get: { selection.contains(id) },
            set: { isSelected in
                if isSelected {
                    selection.insert(id)
                } else {
                    selection.remove(id)
                }
            }
        )
    }
}

// MARK: - Filters

struct FiltersPane: View {
    @ObservedObject var viewModel: PreferencesViewModel

    var body: some View {
        Form {
            Section("Deployment Types") {
                Toggle("Production", isOn: $viewModel.showProduction)
                Toggle("Preview", isOn: $viewModel.showPreview)
            }

            Section("States") {
                Toggle("Ready", isOn: $viewModel.showReady)
                Toggle("Building", isOn: $viewModel.showBuilding)
                Toggle("Queued", isOn: $viewModel.showQueued)
                Toggle("Error", isOn: $viewModel.showError)
                Toggle("Canceled", isOn: $viewModel.showCanceled)
            }

            Section {
                TextField("Only these branches", text: $viewModel.gitBranches, prompt: Text("All branches"))
            } footer: {
                Text("Comma-separated, such as “main, develop”. Filters apply to both the recent list and Projects.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Token field

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
        field.bezelStyle = .roundedBezel
        field.focusRingType = .default
        field.usesSingleLineMode = true
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

/// Menu bar apps have no Edit menu, so the standard paste/select-all shortcuts need forwarding.
private final class PasteEnabledSecureTextField: NSSecureTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard
            event.type == .keyDown,
            event.modifierFlags.contains(.command),
            let characters = event.charactersIgnoringModifiers?.lowercased()
        else {
            return super.performKeyEquivalent(with: event)
        }

        switch characters {
        case "a":
            return NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self)
        case "v":
            return NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self)
        default:
            return super.performKeyEquivalent(with: event)
        }
    }
}

