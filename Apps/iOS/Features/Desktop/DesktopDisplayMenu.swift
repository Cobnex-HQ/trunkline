#if canImport(TrunklineCore)
import TrunklineCore
#endif
import SwiftUI

/// The same native menu is used before opening the desktop and in the viewer toolbar.
struct DesktopDisplayMenu: View {
    @ObservedObject var controls: ClientControls
    var compact = false
    var onSelection: (String) -> Void = { _ in }
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Group {
            if let state = controls.snapshot?.desktopDisplays, state.isAvailable {
                VStack(alignment: .leading, spacing: 6) {
                    Menu {
                        ForEach(state.displays) { display in
                            Button {
                                controls.perform(.desktopDisplay(display.id))
                                if controls.pending != nil { onSelection(display.id) }
                            } label: {
                                if display.id == (state.preferredID ?? state.activeID) {
                                    Label(display.name, systemImage: "checkmark")
                                } else { Text(display.name) }
                                Text("\(display.width) × \(display.height)")
                            }.disabled(display.id == (state.preferredID ?? state.activeID))
                        }
                        if state.displays.isEmpty { Text("No displays available") }
                        if state.switching { Text("Switching display…") }
                        if let error = controls.error ?? state.error { Text(error) }
                        Button("Refresh displays", systemImage: "arrow.clockwise") { controls.refresh() }
                    } label: {
                        if compact {
                            Image(systemName: "display.2").frame(width: 44, height: 44)
                        } else {
                            HStack {
                                Label(state.selectedDisplay?.name ?? "Choose display", systemImage: "display.2")
                                Spacer()
                                if state.switching || controls.pending != nil { ProgressView() }
                                else { Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary) }
                            }.frame(minHeight: 32)
                        }
                    }
                    .disabled(controls.pending != nil)
                    .accessibilityLabel("Choose Mac display")
                    .accessibilityValue(state.switching ? "Switching display" : state.selectedDisplay?.name ?? "No display selected")
                    if !compact, let error = controls.error ?? state.error {
                        Text(error).font(.caption).foregroundStyle(.orange)
                    }
                }
            }
        }
        .task(id: scenePhase) {
            guard compact, scenePhase == .active else { return }
            while !Task.isCancelled {
                controls.refresh(automatically: true)
                do { try await Task.sleep(for: .seconds(5)) } catch { break }
            }
        }
    }
}
