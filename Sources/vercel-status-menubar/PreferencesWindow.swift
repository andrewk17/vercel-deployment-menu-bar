import AppKit
import SwiftUI

final class PreferencesWindowController: NSWindowController {
    static let shared = PreferencesWindowController()

    private let viewModel: PreferencesViewModel

    private init() {
        let viewModel = PreferencesViewModel(store: PreferencesStore.shared)
        self.viewModel = viewModel
        let view = PreferencesView(viewModel: viewModel)
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 680),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Vercel Status Preferences"
        window.contentViewController = hostingController
        super.init(window: window)
        self.window?.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }
        // Refresh the view model with latest stored preferences when opening.
        viewModel.reset()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension PreferencesWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        viewModel.saveAndClose()
    }
}

final class PreferencesViewModel: ObservableObject {
    @Published var vercelToken: String
    @Published var teamId: String
    @Published var projectName: String
    @Published var gitBranches: String
    @Published var showProduction: Bool
    @Published var showPreview: Bool
    @Published var showReady: Bool
    @Published var showBuilding: Bool
    @Published var showError: Bool
    @Published var showQueued: Bool
    @Published var showCanceled: Bool
    @Published var limitByCount: String
    @Published var limitByHours: String
    @Published var refreshIntervalIdle: String
    @Published var refreshIntervalBuilding: String

    private let store: PreferencesStore

    init(store: PreferencesStore) {
        self.store = store
        let current = store.current

        vercelToken = current.vercelToken
        teamId = current.teamId
        projectName = current.projectName
        gitBranches = current.gitBranches
        showProduction = current.showProduction
        showPreview = current.showPreview
        showReady = current.showReady
        showBuilding = current.showBuilding
        showError = current.showError
        showQueued = current.showQueued
        showCanceled = current.showCanceled
        limitByCount = current.limitByCount.map(String.init) ?? ""
        limitByHours = current.limitByHours.map(String.init) ?? ""
        refreshIntervalIdle = current.refreshIntervalIdle.map(String.init) ?? ""
        refreshIntervalBuilding = current.refreshIntervalBuilding.map(String.init) ?? ""
    }

    func reset() {
        let current = store.current
        vercelToken = current.vercelToken
        teamId = current.teamId
        projectName = current.projectName
        gitBranches = current.gitBranches
        showProduction = current.showProduction
        showPreview = current.showPreview
        showReady = current.showReady
        showBuilding = current.showBuilding
        showError = current.showError
        showQueued = current.showQueued
        showCanceled = current.showCanceled
        limitByCount = current.limitByCount.map(String.init) ?? ""
        limitByHours = current.limitByHours.map(String.init) ?? ""
        refreshIntervalIdle = current.refreshIntervalIdle.map(String.init) ?? ""
        refreshIntervalBuilding = current.refreshIntervalBuilding.map(String.init) ?? ""
    }

    func saveAndClose() {
        store.update { preferences in
            preferences.vercelToken = vercelToken
            preferences.teamId = teamId
            preferences.projectName = projectName
            preferences.gitBranches = gitBranches
            preferences.showProduction = showProduction
            preferences.showPreview = showPreview
            preferences.showReady = showReady
            preferences.showBuilding = showBuilding
            preferences.showError = showError
            preferences.showQueued = showQueued
            preferences.showCanceled = showCanceled
            preferences.limitByCount = Int(limitByCount)
            preferences.limitByHours = Int(limitByHours)
            preferences.refreshIntervalIdle = Int(refreshIntervalIdle)
            preferences.refreshIntervalBuilding = Int(refreshIntervalBuilding)
        }
    }
}

struct PreferencesView: View {
    @ObservedObject var viewModel: PreferencesViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Authentication Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Authentication")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Vercel API Token")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        PasteableSecureField(text: $viewModel.vercelToken, placeholder: "Enter your token")
                            .help("Required. Create a token at vercel.com/account/tokens with 'Read Deployments' permission.")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Team ID (optional)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField("", text: $viewModel.teamId, prompt: Text("Leave blank to fetch all teams"))
                            .textFieldStyle(.roundedBorder)
                            .help("Required if using a team-scoped token. Optional otherwise - leave blank to show deployments across all teams.")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Project Name (optional)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField("", text: $viewModel.projectName, prompt: Text("Filter by project"))
                            .textFieldStyle(.roundedBorder)
                            .help("Optional. Filter deployments to a specific project.")
                    }

                    Text("If you get a 403 error with a team-scoped token, make sure to provide the Team ID above.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)

                // Filters Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Filters")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Git Branches (optional)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField("", text: $viewModel.gitBranches, prompt: Text("e.g. main, develop"))
                            .textFieldStyle(.roundedBorder)
                            .help("Comma-separated list of branches to filter (e.g. main, develop)")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Deployment Types")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 16) {
                            Toggle("Production", isOn: $viewModel.showProduction)
                            Toggle("Preview", isOn: $viewModel.showPreview)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Deployment States")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
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
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)

                // Limits Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Limits")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Maximum Deployments (optional)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        NumericTextField(text: $viewModel.limitByCount, placeholder: "e.g. 5")
                            .help("Maximum number of deployments to display (leave blank to ignore)")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Show Only Last X Hours (optional)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        NumericTextField(text: $viewModel.limitByHours, placeholder: "e.g. 24")
                            .help("Only show deployments created within the last X hours (used when Maximum Deployments is empty)")
                    }

                    Text("Limit by count (max deployments) OR by time (recent hours). If both are set, count takes priority.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)

                // Refresh Intervals Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Refresh Intervals")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Idle Interval (seconds)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        NumericTextField(text: $viewModel.refreshIntervalIdle, placeholder: "Default: 15")
                            .help("How often to check for new deployments when none are building (in seconds)")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Building Interval (seconds)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        NumericTextField(text: $viewModel.refreshIntervalBuilding, placeholder: "Default: 2")
                            .help("How often to check for updates when deployments are building or queued (in seconds)")
                    }

                    Text("Lower values provide faster updates but may use more API requests. Defaults: 15s idle, 2s building.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)

                // Close button
                HStack {
                    Spacer()
                    Button("Close") {
                        viewModel.saveAndClose()
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
        .frame(minWidth: 500, minHeight: 680)
        .background(Color(nsColor: .windowBackgroundColor))
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

private final class PasteEnabledSecureTextField: NSSecureTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        if event.modifierFlags.contains(.command),
           let characters = event.charactersIgnoringModifiers?.lowercased() {
            switch characters {
            case "v":
                NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self)
                return true
            default:
                break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

private struct NumericTextField: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder))
            .textFieldStyle(.roundedBorder)
            .onChange(of: text) { newValue in
                // Only allow digits
                let filtered = newValue.filter { $0.isNumber }
                if filtered != newValue {
                    text = filtered
                }
            }
    }
}
