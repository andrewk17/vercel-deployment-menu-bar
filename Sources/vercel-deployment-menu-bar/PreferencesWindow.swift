import AppKit
import SwiftUI

@MainActor
final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    static let shared = PreferencesWindowController()

    private let viewModel = PreferencesViewModel(store: PreferencesStore.shared)

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 760),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Deployment Status Preferences"
        super.init(window: window)
        window.contentViewController = NSHostingController(rootView: PreferencesView(viewModel: viewModel))
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }
        viewModel.reset()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        viewModel.save()
    }
}

struct PreferencesView: View {
    @ObservedObject var viewModel: PreferencesViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PreferencesSection("Vercel") {
                    TokenField(
                        label: "API Token",
                        token: $viewModel.vercelToken,
                        help: "Create a token at vercel.com/account/tokens. Leave blank to hide Vercel deployments."
                    )

                    HStack {
                        Text("Scope & Project")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Refresh") {
                            viewModel.refreshVercelOptions(reloadTeams: true)
                        }
                        .disabled(!viewModel.hasVercelToken || viewModel.teamsLoading || viewModel.projectsLoading)
                    }

                    SelectionList(
                        title: "Team Scopes",
                        allLabel: "All Accessible Scopes",
                        selectedLabel: "Choose Specific Scopes",
                        loadingLabel: "Loading team scopes…",
                        emptyLabel: "No scopes available for this token.",
                        mode: $viewModel.teamSelectionMode,
                        selection: $viewModel.selectedTeamScopeIDs,
                        options: viewModel.availableTeamScopes,
                        isLoading: viewModel.teamsLoading
                    )

                    SelectionList(
                        title: "Projects",
                        allLabel: "All Projects In Scope",
                        selectedLabel: "Choose Specific Projects",
                        loadingLabel: "Loading projects…",
                        emptyLabel: "No projects found for the selected scope(s).",
                        mode: $viewModel.projectSelectionMode,
                        selection: $viewModel.selectedProjectNames,
                        options: viewModel.availableProjects,
                        isLoading: viewModel.projectsLoading
                    )

                    if let message = viewModel.vercelOptionsErrorMessage {
                        Text("Couldn’t refresh scopes/projects: \(message)")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                PreferencesSection("Cloudflare Workers Builds") {
                    TokenField(
                        label: "User API Token",
                        token: $viewModel.cloudflareToken,
                        help: "Create a user API token at dash.cloudflare.com/profile/api-tokens with Workers Builds Configuration: Read and Workers Scripts: Read. Leave blank to hide Cloudflare builds."
                    )

                    HStack {
                        Text("Accounts & Workers")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Refresh") {
                            viewModel.refreshCloudflareOptions()
                        }
                        .disabled(!viewModel.hasCloudflareToken || viewModel.cloudflareLoading)
                    }

                    SelectionList(
                        title: "Accounts",
                        allLabel: "All Accessible Accounts",
                        selectedLabel: "Choose Specific Accounts",
                        loadingLabel: "Loading accounts…",
                        emptyLabel: "No accounts available for this token.",
                        mode: $viewModel.cloudflareAccountMode,
                        selection: $viewModel.selectedCloudflareAccountIDs,
                        options: viewModel.availableCloudflareAccounts,
                        isLoading: viewModel.cloudflareLoading
                    )

                    SelectionList(
                        title: "Workers",
                        allLabel: "All Workers",
                        selectedLabel: "Choose Specific Workers",
                        loadingLabel: "Loading Workers…",
                        emptyLabel: "No Workers found for the selected account(s).",
                        mode: $viewModel.cloudflareWorkerMode,
                        selection: $viewModel.selectedCloudflareWorkers,
                        options: viewModel.availableCloudflareWorkers,
                        isLoading: viewModel.cloudflareLoading
                    )

                    Footnote("Shows Workers connected to a git repository with Workers Builds. Workers deployed directly with wrangler have no builds to show.")

                    if let message = viewModel.cloudflareOptionsErrorMessage {
                        Text("Couldn’t refresh accounts/Workers: \(message)")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                PreferencesSection("Filters") {
                    LabeledField("Git Branches (optional)") {
                        TextField("", text: $viewModel.gitBranches, prompt: Text("e.g. main, develop"))
                            .textFieldStyle(.roundedBorder)
                            .help("Comma-separated list of branches to filter (e.g. main, develop)")
                    }

                    LabeledField("Deployment Types") {
                        HStack(spacing: 16) {
                            Toggle("Production", isOn: $viewModel.showProduction)
                            Toggle("Preview", isOn: $viewModel.showPreview)
                        }
                    }

                    LabeledField("Deployment States") {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 16) {
                                Toggle("Ready", isOn: $viewModel.showReady)
                                Toggle("Building", isOn: $viewModel.showBuilding)
                            }
                            HStack(spacing: 16) {
                                Toggle("Error", isOn: $viewModel.showError)
                                Toggle("Queued", isOn: $viewModel.showQueued)
                            }
                            Toggle("Canceled", isOn: $viewModel.showCanceled)
                        }
                    }
                }

                PreferencesSection("Limits") {
                    LabeledField("Maximum Deployments (optional)") {
                        NumericTextField(text: $viewModel.limitByCount, placeholder: "e.g. 5")
                            .help("Maximum number of deployments to display (leave blank to ignore)")
                    }

                    LabeledField("Show Only Last X Hours (optional)") {
                        NumericTextField(text: $viewModel.limitByHours, placeholder: "e.g. 24")
                            .help("Only show deployments created within the last X hours (used when Maximum Deployments is empty)")
                    }

                    Footnote("Limit by count OR by time. If both are set, count takes priority.")
                }

                PreferencesSection("Refresh Intervals") {
                    LabeledField("Idle Interval (seconds)") {
                        NumericTextField(text: $viewModel.refreshIntervalIdle, placeholder: "Default: 15")
                            .help("How often to check for new deployments when none are building (in seconds)")
                    }

                    LabeledField("Building Interval (seconds)") {
                        NumericTextField(text: $viewModel.refreshIntervalBuilding, placeholder: "Default: 2")
                            .help("How often to check for updates when deployments are building or queued (in seconds)")
                    }

                    Footnote("Lower values provide faster updates but may use more API requests. Defaults: 15s idle, 2s building.")
                }

                HStack {
                    Text("Changes auto-save.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Close") {
                        PreferencesWindowController.shared.close()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.return)
                }
                .padding(.top, 8)
            }
            .padding()
        }
        .frame(minWidth: 560, minHeight: 760)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct TokenField: View {
    let label: String
    @Binding var token: String
    let help: String
    @State private var isRevealed = false

    var body: some View {
        LabeledField(label) {
            HStack(spacing: 10) {
                if isRevealed {
                    TextField("", text: $token, prompt: Text("Enter your token"))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                } else {
                    PasteableSecureField(text: $token, placeholder: "Enter your token")
                }

                Button(isRevealed ? "Hide" : "Show") {
                    isRevealed.toggle()
                }
                .buttonStyle(.bordered)
            }
            .help(help)
        }
    }
}

private struct PreferencesSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}

private struct LabeledField<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            content
        }
    }
}

private struct Footnote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }
}

/// An "all" / "choose specific" picker with a checkbox list for the specific case.
private struct SelectionList: View {
    let title: String
    let allLabel: String
    let selectedLabel: String
    let loadingLabel: String
    let emptyLabel: String
    @Binding var mode: SelectionMode
    @Binding var selection: Set<String>
    let options: [SelectionOption]
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $mode) {
                    Text(allLabel).tag(SelectionMode.all)
                    Text(selectedLabel).tag(SelectionMode.selected)
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            if isLoading {
                ProgressView(loadingLabel)
                    .controlSize(.small)
            } else if mode == .selected {
                if options.isEmpty {
                    Text(emptyLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(options) { option in
                            Toggle(isOn: isSelected(option.id)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.title)
                                    if let subtitle = option.subtitle {
                                        Text(subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    // An empty selection is saved as "all".
                    if selection.isEmpty {
                        Text("Nothing selected, so all are shown.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
        field.drawsBackground = true
        field.focusRingType = .default
        field.usesSingleLineMode = true
        field.isBordered = true
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

private struct NumericTextField: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder))
            .textFieldStyle(.roundedBorder)
            .onChange(of: text) { newValue in
                let filtered = newValue.filter(\.isNumber)
                if filtered != newValue {
                    text = filtered
                }
            }
    }
}
