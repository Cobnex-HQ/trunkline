#if canImport(TrunklineCore)
import TrunklineCore
#endif
import SwiftUI
import AppKit
import ApplicationServices

struct DesktopSharingView: View {
    @ObservedObject var engine: DesktopHost
    let enabled: Bool
    @State private var revoke = false
    @State private var permissions = false
    @State private var selectingDisplay = false
    @State private var displayError: String?
    @State private var restart = false
    @State private var stop = false
    @State private var inputAllowed = CGPreflightPostEventAccess()

    var body: some View {
        Group {
            Section {
                HStack {
                    if engine.starting { ProgressView().controlSize(.small) }
                    Label(engine.status, systemImage: engine.running ? "checkmark.circle" : "display")
                }
                if inputAllowed {
                    Label("Mouse and keyboard access enabled", systemImage: "checkmark.shield")
                        .foregroundStyle(.secondary)
                }
                if !engine.running && !engine.starting {
                    Button("Prepare desktop") { Task { await engine.restart() } }
                        .disabled(!enabled)
                }
                if let error = engine.error {
                    Text(error).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            if !inputAllowed {
                Section {
                    Label("Mouse and keyboard access is off", systemImage: "hand.raised.fill")
                        .foregroundStyle(.orange)
                    Text("Screen sharing can work while clicks are blocked. Enable Trunkline in System Settings → Privacy & Security → \(HostPermissionRequester.accessibilitySettingsName).")
                        .foregroundStyle(.secondary)
                    Button("Enable mouse and keyboard") {
                        HostPermissionRequester.request(.accessibility)
                        openPrivacy("Privacy_Accessibility")
                    }
                    Button("Check again") { inputAllowed = CGPreflightPostEventAccess() }
                }
            }
            if let selection = engine.displaySelection {
                Section {
                    DesktopDisplayPicker(selection: selection, busy: selectingDisplay) { id in
                        selectingDisplay = true; displayError = nil
                        Task {
                            defer { selectingDisplay = false }
                            do { try await engine.selectDisplay(id) }
                            catch { displayError = error.localizedDescription }
                        }
                    }
                    if let displayError { Text(displayError).foregroundStyle(.secondary) }
                }
            }
            if !engine.pending.isEmpty {
                Section("Pair a device") {
                    ForEach(engine.pending) { pair in
                        DesktopPairApprovalRow(pair: pair) { pin in
                            await engine.approve(pair, pin: pin)
                        }
                    }
                }
            }
            Section {
                DisclosureGroup("Permissions", isExpanded: $permissions) {
                    Text("Enable Trunkline and Trunkline Desktop in Privacy & Security. Restart desktop access after changing permissions.")
                        .foregroundStyle(.secondary)
                    ViewThatFits(in: .horizontal) {
                        HStack { permissionButtons }
                        VStack(alignment: .leading, spacing: 8) { permissionButtons }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Button("Restart desktop access…") { restart = true }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .disabled(!enabled || engine.starting)
                }
            }
            Section {
                DisclosureGroup("Advanced") {
                    Button("Open desktop logs") { engine.showLogs() }.disabled(engine.directory == nil)
                    if engine.running { Button("Stop desktop access…", role: .destructive) { stop = true } }
                    if !engine.clients.isEmpty { Button("Revoke desktop pairings…", role: .destructive) { revoke = true } }
                }
            }
        }
        .onAppear { inputAllowed = CGPreflightPostEventAccess() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            inputAllowed = CGPreflightPostEventAccess()
        }
        .confirmationDialog("Restart desktop access?", isPresented: $restart, titleVisibility: .visible) {
            Button("Restart") { Task { await engine.restart() } }
        } message: { Text("Any active desktop session will disconnect.") }
        .confirmationDialog("Stop desktop access?", isPresented: $stop, titleVisibility: .visible) {
            Button("Stop", role: .destructive) { engine.setEnabled(false) }
        } message: { Text("Any active desktop session will disconnect. Terminal and Files remain available.") }
        .confirmationDialog("Revoke every paired desktop device?", isPresented: $revoke, titleVisibility: .visible) {
            Button("Revoke all", role: .destructive) { Task { await engine.revokeAll() } }
        }
    }

    @ViewBuilder private var permissionButtons: some View {
        Button("Screen Recording") { HostPermissionRequester.request(.screenCapture); openPrivacy("Privacy_ScreenCapture") }
        Button(HostPermissionRequester.accessibilitySettingsName) { HostPermissionRequester.request(.accessibility); openPrivacy("Privacy_Accessibility") }
    }
    private func openPrivacy(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?" + pane) { NSWorkspace.shared.open(url) }
    }
}

/// A read/selection surface shared by the live host and inert layout previews.
/// Preferred display is intent; switching status comes from the capture engine.
struct DesktopDisplayPicker: View {
    let selection: DesktopDisplaySelection
    let busy: Bool
    let select: (String) -> Void

    var body: some View {
        if selection.displays.isEmpty {
            Text("No display available").foregroundStyle(.secondary)
        } else {
            if selection.displays.count == 1, let display = selection.displays.first {
                LabeledContent("Display", value: display.name)
            } else {
                Picker("Display", selection: Binding(get: { selection.selectedDisplay?.id ?? "" }, set: select)) {
                    if selection.selectedDisplay == nil { Text("Automatic").tag("").disabled(true) }
                    ForEach(selection.displays) { display in Text(display.name).tag(display.id) }
                }
                .pickerStyle(.menu)
                .disabled(busy || selection.switching)
                .accessibilityLabel("Desktop display")
            }
            if let display = selection.selectedDisplay ?? (selection.displays.count == 1 ? selection.displays.first : nil) {
                LabeledContent("Size", value: "\(display.width) × \(display.height)")
                    .foregroundStyle(.secondary)
            }
            if busy || selection.switching {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Switching display…").foregroundStyle(.secondary)
                }
            }
            if let error = selection.error { Text(error).foregroundStyle(.secondary) }
        }
    }
}

private struct DesktopPairApprovalRow: View {
    let pair: DesktopPendingPair
    let approve: (String) async -> Void
    @State private var pin = ""
    @State private var approving = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(pair.name.isEmpty ? "Trunkline device" : pair.name)
            HStack {
                TextField("Pairing code", text: $pin, prompt: Text("4-digit code"))
                    .textFieldStyle(.roundedBorder).labelsHidden().disabled(approving)
                    .frame(width: 110)
                    .accessibilityLabel("Pairing code for \(pair.name.isEmpty ? "Trunkline device" : pair.name)")
                Button(approving ? "Approving…" : "Approve") {
                    approving = true
                    Task { await approve(pin); pin = ""; approving = false }
                }.disabled(pin.count != 4 || !pin.allSatisfy({ $0.isASCII && $0.isNumber }) || approving)
            }
        }
    }
}
