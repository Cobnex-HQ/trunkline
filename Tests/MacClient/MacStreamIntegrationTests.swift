import XCTest
import Foundation
import AppKit
import Security
import TrunklineCore
@testable import TrunklineHost

/// Opt-in hardware integration. Uses an isolated host on different ports and
/// random test credentials. It never reads or changes the user's pairing data.
@MainActor
final class MacStreamIntegrationTests: XCTestCase {
    func testLocalMacStreamPairsAndDisplaysFrames() async throws {
        guard ProcessInfo.processInfo.environment["TRUNKLINE_TEST_LIVE_STREAM"] == "1" else {
            throw XCTSkip("Set TRUNKLINE_TEST_LIVE_STREAM=1 for the local hardware streaming check")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("trunkline-stream-test-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let configuration = try DesktopHostConfiguration(root: root)
        try (configuration.contents + "\nport = 59989\n").write(to: root.appendingPathComponent("host.conf"), atomically: true, encoding: .utf8)
        try configuration.applications.write(to: root.appendingPathComponent("apps.json"))
        let password = UUID().uuidString
        try DesktopHostConfiguration.credentials(username: "fixture", password: password, salt: String(UUID().uuidString.prefix(16))).write(to: root.appendingPathComponent("management.json"))
        let bundle = Bundle.main.bundleURL
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        let process = Process()
        process.executableURL = bundle.appendingPathComponent("Contents/Helpers/TrunklineDesktopSupervisor")
        process.arguments = [bundle.appendingPathComponent("Contents/Helpers/Desktop/\(architecture)/TrunklineDesktop.app/Contents/MacOS/TrunklineDesktop").path, root.appendingPathComponent("host.conf").path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        defer { if process.isRunning { process.terminate() } }
        let certificateURL = root.appendingPathComponent("credentials/cert.pem")
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: certificateURL.path) && process.isRunning {
            try await Task.sleep(for: .milliseconds(100))
        }
        let pem = try String(contentsOf: certificateURL, encoding: .utf8)
        let certificate = try XCTUnwrap(Data(base64Encoded: pem.components(separatedBy: .newlines).filter { !$0.hasPrefix("-----") }.joined()))
        let configurationURL = URLSessionConfiguration.ephemeral
        configurationURL.timeoutIntervalForRequest = 5
        let session = URLSession(configuration: configurationURL, delegate: FixtureTrust(certificate: certificate), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        func request(_ path: String, body: Data? = nil, csrf: String? = nil) async throws -> [String: Any] {
            var request = URLRequest(url: URL(string: "https://127.0.0.1:59990" + path)!)
            request.setValue("Basic " + Data("fixture:\(password)".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
            if let body {
                request.httpMethod = "POST"; request.httpBody = body
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue(csrf, forHTTPHeaderField: "X-CSRF-Token")
            }
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            return try JSONSerialization.jsonObject(with: data) as! [String: Any]
        }
        let engine = MacDesktopEngine()
        defer { engine.stop() }
        var pin: String?
        var failure: String?
        engine.pairingCode = { pin = $0 }
        engine.stateChanged = { _, error in if let error { failure = error } }
        engine.startHost("127.0.0.1:59989", certificate: nil, width: 1280, height: 720, fps: 60, bitrate: 4000, away: false)
        for _ in 0..<80 {
            if failure != nil { break }
            if let pin, let data = try? await request("/api/pin"), let pending = data["pairings"] as? [[String: Any]],
               let pair = pending.first(where: { $0["name"] as? String == "Trunkline-" + engine.pairingToken }), let id = pair["id"] as? String {
                let token = try await request("/api/csrf-token")["csrf_token"] as! String
                let body = try JSONEncoder().encode(DesktopPairApproval(id: id, pin: pin, name: "Local integration fixture"))
                _ = try await request("/api/pin", body: body, csrf: token)
                break
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        for _ in 0..<160 where !engine.displayLayer.isReadyForDisplay && failure == nil {
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertNil(failure)
        XCTAssertTrue(engine.displayLayer.isReadyForDisplay, "The real host must deliver a decodable desktop frame")
        // XCTest hosts cannot reliably become the frontmost application. Verify
        // injection at the OS boundary and consume fixture events before they
        // reach any of the user's applications.
        let lookup = Process(), output = Pipe()
        lookup.executableURL = URL(fileURLWithPath: "/bin/ps")
        lookup.arguments = ["-axo", "pid=,ppid="]
        lookup.standardOutput = output
        try lookup.run()
        let rows = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        lookup.waitUntilExit()
        let child = try XCTUnwrap(rows.split(separator: "\n").compactMap { row -> Int64? in
            let numbers = row.split(whereSeparator: { $0.isWhitespace }).compactMap { Int64($0) }
            return numbers.count == 2 && numbers[1] == Int64(process.processIdentifier) ? numbers[0] : nil
        }.first)
        let events = FixtureEvents(sourcePID: child)
        let types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .keyDown, .keyUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let tap = try XCTUnwrap(CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, pointer in
            guard let pointer else { return Unmanaged.passUnretained(event) }
            let recorder = Unmanaged<FixtureEvents>.fromOpaque(pointer).takeUnretainedValue()
            guard event.getIntegerValueField(.eventSourceUnixProcessID) == recorder.sourcePID else { return Unmanaged.passUnretained(event) }
            recorder.types.append(type)
            return nil
        }, userInfo: Unmanaged.passUnretained(events).toOpaque()), "The input acceptance test requires Mac input permission")
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        defer { CFMachPortInvalidate(tap); CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        engine.moveX(0.5, y: 0.5)
        engine.button(1, down: true)
        try await Task.sleep(for: .milliseconds(80))
        engine.button(1, down: false)
        engine.key(0x41, down: true, modifiers: 0)
        engine.key(0x41, down: false, modifiers: 0)
        for _ in 0..<50 where events.types.count < 4 { try await Task.sleep(for: .milliseconds(100)) }
        // Mouse and keyboard use separate reliable transport channels. The
        // host may also defer left-button release for touch compatibility.
        XCTAssertEqual(events.types.filter { $0 == .leftMouseDown || $0 == .leftMouseUp }.map(\.rawValue), [1, 2])
        XCTAssertEqual(events.types.filter { $0 == .keyDown || $0 == .keyUp }.map(\.rawValue), [10, 11])
        XCTAssertEqual(events.types.count, 4)
        engine.stop()
        await withCheckedContinuation { continuation in MacDesktopEngine.finishStopping { continuation.resume() } }
        await ProcessShutdown.finish([process])
    }
}

private final class FixtureTrust: NSObject, URLSessionDelegate, @unchecked Sendable {
    let certificate: Data
    init(certificate: Data) { self.certificate = certificate }
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust, let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
           let leaf = chain.first, SecCertificateCopyData(leaf) as Data == certificate {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else { completionHandler(.cancelAuthenticationChallenge, nil) }
    }
}

private final class FixtureEvents {
    let sourcePID: Int64
    var types: [CGEventType] = []
    init(sourcePID: Int64) { self.sourcePID = sourcePID }
}
