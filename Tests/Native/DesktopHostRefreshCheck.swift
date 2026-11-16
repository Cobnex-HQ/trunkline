import AppKit
import Combine

// Exercise the real HTTP decoding/publication path without launching the engine,
// reading credentials, or making network requests.
private final class RefreshResponseState: @unchecked Sendable {
    let lock = NSLock()
    var name = "Fixture"
    var displayStatus = 200
    var requests = 0
}
private final class RefreshResponseProtocol: URLProtocol, @unchecked Sendable {
    static let state = RefreshResponseState()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (name, displayStatus) = Self.state.lock.withLock {
            Self.state.requests += 1
            return (Self.state.name, Self.state.displayStatus)
        }
        let path = request.url!.path
        let payload: [String: Any]
        switch path {
        case "/api/pin": payload = ["pairings": [["id": "fixture-pair", "name": name, "address": "127.0.0.1"]]]
        case "/api/clients/list": payload = ["named_certs": [["uuid": "fixture-client", "name": name]]]
        case "/api/trunkline/displays":
            payload = ["status": true, "supported": true, "switching": false,
                "active_id": "7777777", "preferred_id": "7777777",
                "displays": [["id": "7777777", "name": name, "width": 1920, "height": 1080]]]
        default: preconditionFailure("Unexpected request: \(path)")
        }
        let code = path == "/api/trunkline/displays" ? displayStatus : 200
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: payload))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct DesktopHostRefreshCheck {
    @MainActor static func main() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RefreshResponseProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let host = DesktopHost(session: session)
        var notifications = 0
        let observation = host.objectWillChange.sink { notifications += 1 }
        defer { observation.cancel() }
        try await host.refresh()
        precondition(host.pending.count == 1 && host.clients.count == 1 && host.displaySelection?.isAvailable == true)
        notifications = 0
        let requestsBefore = RefreshResponseProtocol.state.lock.withLock { RefreshResponseProtocol.state.requests }
        for _ in 0..<10 { try await host.refresh() }
        let requestsAfter = RefreshResponseProtocol.state.lock.withLock { RefreshResponseProtocol.state.requests }
        precondition(requestsAfter - requestsBefore == 30, "Status polling must continue unchanged")
        guard notifications == 0 else {
            print("FAIL: Ten unchanged refreshes emitted \(notifications) UI invalidations")
            exit(1)
        }
        RefreshResponseProtocol.state.lock.withLock { RefreshResponseProtocol.state.name = "Changed" }
        try await host.refresh()
        precondition(notifications > 0, "Real state changes must notify observers")
        precondition(host.pending.first?.name == "Changed" && host.clients.first?.name == "Changed" && host.displaySelection?.displays.first?.name == "Changed")
        RefreshResponseProtocol.state.lock.withLock { RefreshResponseProtocol.state.displayStatus = 503 }
        notifications = 0
        try await host.refresh()
        precondition(host.displaySelection == nil && notifications > 0, "Unavailable displays must clear stale UI state")
        notifications = 0
        try await host.refresh()
        precondition(notifications == 0, "Repeated unavailability must not invalidate an unchanged view")
        RefreshResponseProtocol.state.lock.withLock { RefreshResponseProtocol.state.displayStatus = 200 }
        try await host.refresh()
        precondition(host.displaySelection?.isAvailable == true && notifications > 0, "Recovery must remain visible")
        print("PASS: 10 unchanged refreshes, 30 HTTP requests, zero UI invalidations; changes, unavailability and recovery still publish")
    }
}
