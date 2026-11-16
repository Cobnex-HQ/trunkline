import Foundation
import Combine

@main struct WindowControlsCheck {
    @MainActor static func main() throws {
        let client = ClientControls()
        defer { client.reset() }
        var failures = 0
        func check(_ value: Bool, _ message: String) { if !value { failures += 1; print("FAIL: " + message) } }
        let finder = MacApplication(pid: 10, name: "Finder", bundleID: "com.apple.finder", active: true)
        let safari = MacApplication(pid: 11, name: "Safari", bundleID: "com.apple.Safari", active: false)
        var state = MacControlSnapshot(apps: [finder, safari], windows: [], displays: [], volume: nil,
            muted: nil, accessibility: true, frontmostApp: "Finder",
            windowScope: MacWindowScope(requestedPID: nil, application: finder))
        _ = client.handle(.controls(state))
        var requests: [(Int32?, UUID?)] = []
        client.send = { if case let .requestControls(pid, id, _, _) = $0 { requests.append((pid, id)) } }
        client.refresh()
        check(requests.first?.1 != nil, "Refresh requests must have an identity")
        state.frontmostApp = "Stale app"; state.requestID = UUID()
        _ = client.handle(.controls(state))
        check(client.snapshot?.frontmostApp == "Finder" && client.isRefreshing,
              "Unrelated snapshots cannot replace the active view or finish its refresh")
        guard let firstID = requests.first?.1 else { exit(1) }
        client.selectWindowApplication(11)
        check(requests.count == 1 && !client.hasCurrentWindowList,
              "Selecting an app coalesces behind the current refresh and hides old windows")
        state.frontmostApp = "Finder"; state.requestID = firstID
        _ = client.handle(.controls(state))
        check(requests.count == 2 && requests.last?.0 == 11 && client.isRefreshing,
              "The selected app is requested as soon as the outstanding refresh finishes")
        _ = client.handle(.controls(state))
        check(client.isRefreshing && requests.count == 2, "A duplicate reply cannot consume the new refresh")
        let safariID = requests.last!.1!
        state.requestID = safariID
        state.windowScope = MacWindowScope(requestedPID: 11, application: safari)
        state.windows = [MacWindow(id: UUID(), title: "Project notes", minimized: false)]
        var parser = PacketParser()
        for message in try parser.append(PacketCodec.encode(.controls(state))) { _ = client.handle(message) }
        check(client.hasCurrentWindowList && !client.isRefreshing && client.snapshot?.windows.first?.title == "Project notes",
              "Correlated window results are shown for the selected app")
        client.selectWindowApplication(999)
        check(requests.count == 2 && client.selectedWindowAppPID == 11, "Closed apps cannot be selected from stale UI")

        client.selectWindowApplication(10)
        let finderID = requests.last!.1!
        client.selectWindowApplication(11); client.selectWindowApplication(nil)
        check(requests.count == 3, "Rapid selections do not create overlapping requests")
        state.requestID = finderID; state.windowScope = MacWindowScope(requestedPID: 10, application: finder)
        _ = client.handle(.controls(state))
        check(requests.count == 4 && requests.last!.0 == nil, "Only the most recent queued selection is requested")
        state.requestID = requests.last!.1; state.windowScope = MacWindowScope(requestedPID: nil, application: finder)
        _ = client.handle(.controls(state))
        var updates = 0
        let observation = client.$snapshot.dropFirst().sink { _ in updates += 1 }
        client.refresh(); state.requestID = requests.last!.1
        _ = client.handle(.controls(state))
        check(updates == 0, "Changing request IDs must not redraw unchanged control content")
        observation.cancel()
        client.reset()
        _ = client.handle(.controls(state))
        check(client.snapshot == nil && client.selectedWindowAppPID == nil, "Disconnect ignores in-flight replies and resets window selection")
        var actions: [MacControlAction] = []
        client.send = { if case let .control(request) = $0 { actions.append(request.action) } }
        let windowID = UUID()
        state.requestID = nil; state.windowScope = nil
        state.windows = [MacWindow(id: windowID, title: "Legacy window", minimized: false)]
        state.displays = [MacDisplayInfo(id: 74, name: "External", width: 1920, height: 1080)]
        _ = client.handle(.controls(state))
        client.perform(.moveWindow(windowID, displayID: 74))
        check(actions.isEmpty && client.pending == nil && client.error != nil, "Old hosts never receive unsupported display-move requests")
        state.windows = [MacWindow(id: windowID, title: "Movable", minimized: false, canMoveToDisplay: true)]
        _ = client.handle(.controls(state))
        client.perform(.moveWindow(windowID, displayID: 99))
        check(actions.isEmpty && client.pending == nil, "Disconnected displays are rejected before sending")
        client.perform(.moveWindow(UUID(), displayID: 74))
        check(actions.isEmpty && client.pending == nil, "Stale windows cannot be moved")
        client.perform(.moveWindow(windowID, displayID: 74))
        check(actions == [.moveWindow(windowID, displayID: 74)] && client.pending != nil,
              "Advertised window capability sends the exact destination display identity")
        guard failures == 0 else { exit(1) }
        print("PASS: window correlation, app selection, refresh coalescing, stale replies, disconnect and display-move capability gating")
    }
}
