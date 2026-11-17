import SwiftUI
import AppKit
import TrunklineCore

struct MacClientView: View {
    @ObservedObject var model: MacClientModel
    @ObservedObject var localHost: HostModel
    @State private var showPasscode = false
    private var connected: Bool { model.connection.phase == .connected }
    private var busy: Bool { model.preparing || (model.connection.phase != .disconnected && !connected) }
    var body: some View {
        Form {
            if connected {
                Section {
                    LabeledContent("Connected to", value: model.connection.name)
                    LabeledContent("Route", value: model.away ? "Direct · Away" : "Local network")
                    HStack {
                        Button(model.streaming ? "Show desktop" : "Open desktop", systemImage: "display") { model.openDesktop() }
                            .buttonStyle(.borderedProminent)
                        Button("Disconnect…") {
                            let prompt = HostSharingPrompt(title: "Disconnect from \(model.connection.name)?", message: "The remote desktop will close. Terminal jobs on that Mac keep running.", button: "Disconnect")
                            if HostSharingAction.show(prompt) { model.disconnect() }
                        }
                    }
                    if !model.status.isEmpty { Text(model.status).foregroundStyle(.secondary) }
                }
                Section("Desktop") {
                    Picker("Quality", selection: $model.profile) {
                        ForEach(StreamProfile.allCases) { Text($0.title).tag($0) }
                    }.disabled(model.streaming)
                    Text("Click the desktop to control it. Control–Option–Escape releases keyboard control. Use the green window button for full screen.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                MacClientControls(model: model, controls: model.controls)
            } else {
                Section {
                    Group {
                        if !model.savedMacs.isEmpty {
                            Picker("Saved Mac", selection: Binding(get: { model.savedMacs.first(where: { $0.link == model.pairingText })?.id ?? "" }, set: { id in
                                if let saved = model.savedMacs.first(where: { $0.id == id }) { model.select(saved) }
                                else { model.pairingText = ""; model.passcode = "" }
                            })) {
                                Text("Add a Mac…").tag("")
                                ForEach(model.savedMacs) { Text($0.name).tag($0.id) }
                            }
                        }
                        TextField("Pairing link", text: $model.pairingText, prompt: Text("trunkline://pair…"))
                            .textContentType(.URL).textFieldStyle(.roundedBorder)
                        HStack {
                            if showPasscode { TextField("Connection passcode", text: $model.passcode) }
                            else { SecureField("Connection passcode", text: $model.passcode) }
                            Button(showPasscode ? "Hide passcode" : "Show passcode", systemImage: showPasscode ? "eye.slash" : "eye") { showPasscode.toggle() }
                                .labelStyle(.iconOnly).buttonStyle(.borderless)
                        }.textFieldStyle(.roundedBorder).onSubmit { if !busy { model.connect(localHost: localHost) } }
                        Picker("Network", selection: $model.away) {
                            Text("Local network").tag(false)
                            Text("Away").tag(true)
                        }.pickerStyle(.segmented)
                    }.disabled(busy)
                    if busy {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text(model.preparing ? model.status : "Connecting…")
                            Spacer()
                            Button("Cancel") { model.disconnect() }
                        }
                    } else {
                        Button("Connect") { model.connect(localHost: localHost) }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.pairingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.passcode.isEmpty)
                    }
                } header: { Text("Connect to a Mac") } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("On the remote Mac, open My Mac → Sharing, turn sharing on and copy its pairing link.")
                        if model.away {
                            Text("Requires Away access on the other Mac. Direct connections depend on both networks. Turn off sharing on this Mac before connecting away.")
                        }
                    }
                }
            }
            if let error = model.error ?? model.connection.error {
                Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).textSelection(.enabled) }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: connected ? 800 : 620).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct MacClientControls: View {
    @ObservedObject var model: MacClientModel
    @ObservedObject var controls: ClientControls
    var body: some View {
        Section("Remote controls") {
            if let selection = controls.snapshot?.desktopDisplays, selection.isAvailable {
                Picker("Display", selection: Binding(get: { selection.selectedDisplay?.id ?? "" }, set: { id in
                    model.stopDesktop()
                    controls.perform(.desktopDisplay(id))
                })) {
                    ForEach(selection.displays) { display in Text("\(display.name) · \(display.width) × \(display.height)").tag(display.id) }
                }.disabled(controls.pending != nil || selection.switching == true)
                Text("After switching displays, open the desktop again.").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Mission Control") { controls.perform(.system(.missionControl)) }
                Button("Show desktop") { controls.perform(.system(.showDesktop)) }
                Button("Switch app") { controls.perform(.system(.switchApp)) }
            }.disabled(controls.pending != nil)
            if let awake = controls.snapshot?.keepAwake, !awake.requiresLocalChange {
                Toggle("Keep remote Mac awake", isOn: Binding(get: { awake.mode != .off }, set: { value in controls.perform(.keepAwake(value ? .system : .off)) }))
                    .disabled(controls.pending != nil)
            }
            Button("Refresh controls", systemImage: "arrow.clockwise") { controls.refresh() }.disabled(controls.isRefreshing)
            if let error = controls.error ?? controls.refreshError { Text(error).foregroundStyle(.orange) }
        }
    }
}
