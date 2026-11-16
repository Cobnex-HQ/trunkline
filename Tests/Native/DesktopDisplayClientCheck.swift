import Foundation

@main struct DesktopDisplayClientCheck {
    @MainActor static func main() throws {
        let client = ClientControls()
        defer { client.reset() }
        var sent: [MacControlRequest] = []
        client.send = { if case let .control(request) = $0 { sent.append(request) } }
        var state = MacControlSnapshot(apps: [], windows: [], displays: [], volume: nil, muted: nil,
                                       accessibility: false, frontmostApp: "Mac")
        func require(_ condition: Bool, _ reason: String) {
            if !condition { print("FAIL: \(reason)"); exit(1) }
        }
        _ = client.handle(.controls(state))
        client.perform(.desktopDisplay("74"))
        require(sent.isEmpty && client.pending == nil, "Old hosts never receive an unsupported selector command")
        let display = DesktopCaptureDisplay(id: "74", name: "External", width: 2560, height: 1440)
        state.desktopDisplays = DesktopDisplaySelection(displays: [display])
        _ = client.handle(.controls(state))
        client.perform(.desktopDisplay("1"))
        require(sent.isEmpty && client.error != nil, "A removed monitor cannot be selected")
        client.perform(.desktopDisplay("74"))
        require(sent.count == 1 && client.pending == sent.first?.id && client.error == nil, "Known identity reaches authenticated transport")
        require(client.snapshot?.desktopDisplays?.activeID == nil, "Sending intent does not claim capture is active")
        client.perform(.desktopDisplay("74"))
        require(sent.count == 1, "Repeated taps do not duplicate an in-flight command")
        let request = sent[0]
        _ = client.handle(.controlResult(MacControlResult(id: UUID())))
        require(client.pending == request.id, "Unrelated acknowledgements cannot settle the switch")
        _ = client.handle(.controlResult(MacControlResult(id: request.id, error: "Display disconnected")))
        require(client.pending == nil && client.error != nil, "A rejected switch releases controls and exposes its error")
        client.reset()
        require(client.snapshot == nil && client.pending == nil, "Disconnect discards the previous Mac's displays")
        print("PASS: display capability gating, disconnected monitor, command correlation and reset")
    }
}
