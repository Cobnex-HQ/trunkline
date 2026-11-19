#if canImport(TrunklineCore)
import TrunklineCore
#endif
import SwiftUI

/// Switching is explicit: release this Mac before authenticating to another.
struct MacSwitchMenu: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var model: ConnectionModel
    @State private var pending: SavedMac?
    @State private var addMac = false
    @State private var showHelp = false
    var body: some View {
        Menu {
            ForEach(model.savedMacs) { mac in
                Button { pending = mac } label: {
                    Label(mac.name, systemImage: mac.id == model.selectedMacID ? "checkmark" : "desktopcomputer")
                }.disabled(mac.id == model.selectedMacID)
            }
            if UIDevice.current.userInterfaceIdiom == .pad {
                Menu("Open in new window", systemImage: "macwindow.badge.plus") {
                    ForEach(model.savedMacs) { mac in
                        Button(mac.name) { openWindow(id: "mac", value: mac.id) }
                    }
                    Button("Add Mac") { openWindow(id: "workspace") }
                }
            }
            Divider()
            Button("Add Mac", systemImage: "plus") { addMac = true }
            Button("Help and privacy", systemImage: "questionmark.circle") { showHelp = true }
        } label: { Label("Macs", systemImage: "desktopcomputer") }
        .sheet(isPresented: $showHelp) { AppHelpView() }
        .confirmationDialog("Switch to \(pending?.name ?? "another Mac")?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
            if let mac = pending { Button("Disconnect and switch") { model.switchMac(mac.id); pending = nil } }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: { Text("This disconnects \(model.name). Terminal sessions keep running on that Mac.") }
        .confirmationDialog("Add another Mac?", isPresented: $addMac, titleVisibility: .visible) {
            Button("Disconnect and add Mac") { model.openPairingScanner = true; model.disconnect() }
        } message: { Text("This disconnects the current Mac and opens the QR scanner.") }
    }
}
