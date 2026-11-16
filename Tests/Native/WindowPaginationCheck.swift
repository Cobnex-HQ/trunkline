import Foundation

@main struct WindowPaginationCheck {
    @MainActor static func main() throws {
        let client = ClientControls()
        defer { client.reset() }
        var failures = 0
        func check(_ value: Bool, _ message: String) { if !value { failures += 1; print("FAIL: " + message) } }
        let app = MacApplication(pid: 42, name: "Notes", bundleID: "com.apple.Notes", active: true)
        let cursor = UUID()
        var state = MacControlSnapshot(apps: [app], windows: [MacWindow(id: UUID(), title: "First", minimized: false)],
            displays: [], volume: 0.5, muted: false, accessibility: true, frontmostApp: "Notes",
            windowScope: MacWindowScope(requestedPID: nil, application: app),
            windowPage: MacWindowPage(nextCursor: cursor, totalCount: 29))
        _ = client.handle(.controls(state))
        var requests: [(Int32?, UUID?, UUID?, Bool?)] = []
        client.send = { if case let .requestControls(pid, id, cursor, preserve) = $0 { requests.append((pid, id, cursor, preserve)) } }
        client.loadMoreWindows()
        check(requests.count == 1 && requests[0].2 == cursor && client.isRefreshing, "Load more sends the host continuation and enters a bounded refresh")
        client.loadMoreWindows()
        check(requests.count == 1, "Repeated taps cannot overlap window requests")
        state.requestID = requests.last!.1
        state.windows.append(MacWindow(id: UUID(), title: "Last", minimized: false))
        state.windowPage = MacWindowPage(nextCursor: nil, totalCount: 2)
        _ = client.handle(.controls(state))
        client.refresh(automatically: true)
        check(requests.last!.3 == true && requests.last!.2 == nil, "Automatic controls updates preserve expanded windows")
        state.requestID = requests.last!.1; state.volume = 0.7
        _ = client.handle(.controls(state))
        check(client.snapshot?.windows.count == 2 && client.snapshot?.volume == 0.7, "Sound continues updating without collapsing the window list")
        let count = requests.count
        client.loadMoreWindows()
        check(requests.count == count, "Exhausted lists cannot send another continuation")
        client.refresh(automatically: true)
        state.requestID = requests.last!.1
        let otherApp = MacApplication(pid: 43, name: "Finder", bundleID: "com.apple.finder", active: true)
        state.windowScope = MacWindowScope(requestedPID: nil, application: otherApp)
        state.frontmostApp = "Finder"
        _ = client.handle(.controls(state))
        client.refresh(automatically: true)
        check(requests.last!.3 != true, "Following a newly active app must resume fresh enumeration")
        state.requestID = requests.last!.1
        _ = client.handle(.controls(state))
        client.refresh()
        check(requests.last!.2 == nil && requests.last!.3 != true, "Explicit Refresh requests a fresh window enumeration")
        state.requestID = requests.last!.1; state.windowPage = nil
        _ = client.handle(.controls(state))
        let legacyCount = requests.count
        client.loadMoreWindows()
        check(requests.count == legacyCount, "Old hosts without paging metadata never receive a continuation")
        client.reset()
        _ = client.handle(.controls(state))
        check(client.snapshot == nil, "Disconnect rejects an old page response")
        guard failures == 0 else { exit(1) }
        print("PASS: bounded continuation requests, expanded-list polling, updated sound, explicit refresh, old hosts and disconnect")
    }
}
