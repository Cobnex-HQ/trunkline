import Foundation

/// Read actual Mac state; output writes select only the already-selected device.
@main struct HostControlsCheck {
    static func main() async throws {
        let controls = MacControls()
        let state = await controls.snapshot()
        guard state.windowScope != nil else { fatalError("Host did not publish window selection capability") }
        let requestID = UUID()
        let missingApp = await controls.snapshot(windowAppPID: -1, requestID: requestID)
        guard missingApp.requestID == requestID, missingApp.windowScope?.requestedPID == -1,
              missingApp.windowScope?.application == nil, missingApp.windowScope?.error != nil, missingApp.windows.isEmpty else {
            fatalError("Missing window app must not fall back to unrelated frontmost windows")
        }
        if let background = state.apps.first(where: { !$0.active }) {
            let selected = await controls.snapshot(windowAppPID: background.pid)
            guard selected.windowScope?.application?.pid == background.pid else { fatalError("Background app selection was not honored") }
            print("PASS: background app selected without activation; Accessibility available: \(selected.accessibility); windows read: \(selected.windows.count)")
        }
        guard let outputs = state.audioOutputs else { fatalError("Host did not publish audio capability") }
        let missing = await controls.perform(MacControlRequest(action: .audioOutput("Trunkline-missing-" + UUID().uuidString)))
        guard missing.error != nil else { fatalError("Disconnected output was accepted") }
        let afterInvalid = await controls.snapshot()
        guard afterInvalid.audioOutputs?.first(where: \.selected)?.id == outputs.first(where: \.selected)?.id else {
            fatalError("An invalid output changed the default device")
        }
        if let current = outputs.first(where: \.selected) {
            let same = await controls.perform(MacControlRequest(action: .audioOutput(current.id)))
            guard same.error == nil else { fatalError("Selecting existing output failed: \(same.error!)") }
            let updated = await controls.snapshot()
            guard updated.audioOutputs?.first(where: \.selected)?.id == current.id else {
                fatalError("Current output selection was not retained")
            }
            print("PASS: enumerated \(outputs.count) usable audio outputs; current selection accepted; disconnected identity rejected without changing output")
        } else {
            print("PASS: disconnected identity rejected; no selected physical output available to exercise the setter")
        }
    }
}
