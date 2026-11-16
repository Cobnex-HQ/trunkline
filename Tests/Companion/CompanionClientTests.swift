#if canImport(TrunklineCore)
import TrunklineCore
#endif
import XCTest
import Network
import SwiftUI
import UIKit
import SwiftTerm
@testable import Trunkline

@MainActor
final class CompanionClientTests: XCTestCase {
    func testPasscodeRevealPreservesFocusSelectionAndSubsequentTyping() throws {
        let type = try XCTUnwrap(NSClassFromString("Trunkline.ConnectionPasscodeTextField") as? UITextField.Type,
                                 "The connection form needs a native, focus-preserving passcode field")
        let field = type.init(frame: CGRect(x: 20, y: 100, width: 300, height: 48))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 768, height: 1024))
        window.rootViewController = UIViewController(); window.makeKeyAndVisible()
        defer { field.resignFirstResponder(); window.isHidden = true }
        window.rootViewController?.view.addSubview(field)
        field.text = "abcd"
        XCTAssertTrue(field.isSecureTextEntry)
        XCTAssertTrue(field.becomeFirstResponder())
        let insertion = try XCTUnwrap(field.position(from: field.beginningOfDocument, offset: 2))
        field.selectedTextRange = field.textRange(from: insertion, to: insertion)
        let reveal = try XCTUnwrap(field.rightView as? UIButton)
        reveal.sendActions(for: .touchUpInside)
        XCTAssertFalse(field.isSecureTextEntry)
        XCTAssertTrue(field.isFirstResponder, "Revealing the password must not dismiss the iPad keyboard")
        field.insertText("x")
        XCTAssertEqual(field.text, "abxcd", "Keep the insertion point when revealing")
        reveal.sendActions(for: .touchUpInside)
        XCTAssertTrue(field.isSecureTextEntry)
        XCTAssertTrue(field.isFirstResponder)
        field.insertText("y")
        XCTAssertEqual(field.text, "abxycd", "Hiding must not clear or replace the passcode on the next key")
        field.resignFirstResponder()
        XCTAssertTrue(field.becomeFirstResponder())
        field.insertText("z")
        XCTAssertEqual(field.text, "abxyzcd", "Returning to a saved draft must preserve the passcode")
    }

    func testConnectionFormKeepsFocusedPasscodeAboveSoftwareKeyboard() async throws {
        let suite = "trunkline-keyboard-form-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = ConnectionModel(defaults: defaults)
        for index in 1...4 {
            let pairing = try PairingDetails(host: "mac-\(index).local", port: 47995,
                                            fingerprint: String(repeating: String(index), count: 64))
            model.receivePairingLink(try XCTUnwrap(URL(string: pairing.link)))
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: ConnectView(model: model))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { host.view.endEditing(true); window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        host.view.layoutIfNeeded()
        func findPasscode(_ view: UIView) -> ConnectionPasscodeTextField? {
            (view as? ConnectionPasscodeTextField) ?? view.subviews.lazy.compactMap(findPasscode).first
        }
        try await terminalEventually { findPasscode(host.view) != nil }
        let field = try XCTUnwrap(findPasscode(host.view))
        XCTAssertTrue(field.becomeFirstResponder(), "Tapping the native input must activate the keyboard")
        try await terminalEventually(timeout: 4) { host.view.keyboardLayoutGuide.layoutFrame.height > 100 }
        try await terminalEventually(timeout: 4) {
            let input = field.convert(field.bounds, to: host.view)
            let keyboard = host.view.keyboardLayoutGuide.layoutFrame
            return input.minY >= host.view.safeAreaInsets.top && input.maxY <= keyboard.minY
        }
        field.insertText("test-passcode")
        try await terminalEventually { model.passcode == "test-passcode" }
        let reveal = try XCTUnwrap(field.rightView as? UIButton)
        reveal.sendActions(for: .touchUpInside)
        XCTAssertFalse(field.isSecureTextEntry)
        XCTAssertTrue(field.isFirstResponder)
        field.resignFirstResponder()
        XCTAssertTrue(field.isSecureTextEntry, "Leaving the input must conceal the passcode")
    }

    func testThreeFingerSwipesRouteSpacesAndMissionControlWithoutTakingTwoFingerPan() throws {
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
        let content = UIView(frame: scroll.bounds); scroll.addSubview(content)
        let viewport = ViewportCoordinator(scroll: scroll, content: content, aspect: 16.0 / 10)
        let swipes = (scroll.gestureRecognizers ?? []).compactMap { $0 as? UISwipeGestureRecognizer }
        XCTAssertEqual(swipes.count, 4, "Install a three-finger shortcut for each direction")
        guard swipes.count == 4 else { return }
        XCTAssertTrue(swipes.allSatisfy { $0.numberOfTouchesRequired == 3 })
        XCTAssertEqual(scroll.panGestureRecognizer.maximumNumberOfTouches, 2)
        var actions: [String] = []
        let callback: @convention(block) (String) -> Void = { actions.append($0) }
        viewport.setValue(callback, forKey: "workspaceAction")
        for (direction, expected) in [(UISwipeGestureRecognizer.Direction.left, "nextSpace"),
                                      (.right, "previousSpace"), (.up, "missionControl"), (.down, "appWindows")] {
            let recognized = RecognizedWorkspaceSwipe(); recognized.direction = direction
            recognized.state = .ended
            _ = viewport.perform(NSSelectorFromString("handleWorkspaceSwipe:"), with: recognized)
            XCTAssertEqual(actions.last, expected)
        }
        let cancelled = RecognizedWorkspaceSwipe(); cancelled.state = .cancelled
        _ = viewport.perform(NSSelectorFromString("handleWorkspaceSwipe:"), with: cancelled)
        XCTAssertEqual(actions.count, 4, "A cancelled gesture must not change the Mac workspace")
    }

    // Cold simulator services can take seconds to create listeners or open files.
    // This bounds fixture startup; heartbeat and protocol deadlines below stay short.
    private let fixtureStartupTimeout: TimeInterval = 10

    func testPairingSeveralMacsPreservesChoicesAndClearsUnsavedPasscode() throws {
        let suite = "trunkline-multi-mac-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let a = try PairingDetails(host: "studio.local", port: 47995, fingerprint: String(repeating: "a", count: 64))
        let b = try PairingDetails(host: "laptop.local", port: 47995, fingerprint: String(repeating: "b", count: 64))
        let model = ConnectionModel(defaults: defaults)
        model.receivePairingLink(try XCTUnwrap(URL(string: a.link)))
        model.passcode = "never-use-on-another-mac"
        model.receivePairingLink(try XCTUnwrap(URL(string: b.link)))
        XCTAssertTrue(model.passcode.isEmpty)
        let saved = SavedMacStore(defaults: defaults)
        XCTAssertEqual(saved.macs.count, 2, "Scanning another Mac must retain the previous Mac")
        XCTAssertEqual(saved.selectedID, b.fingerprint)
        let restored = ConnectionModel(defaults: defaults)
        XCTAssertEqual(restored.pairingText, b.link, "Keep the selected Mac across app launches")
    }

    func testSwitchingMacReleasesConnectionAndRestoresIndependentRoute() throws {
        let suite = "trunkline-switch-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let a = try PairingDetails(host: "studio.local", port: 47995, fingerprint: String(repeating: "d", count: 64))
        let b = try PairingDetails(host: "laptop.local", port: 47995, fingerprint: String(repeating: "e", count: 64))
        let model = ConnectionModel(defaults: defaults)
        model.receivePairingLink(try XCTUnwrap(URL(string: a.link)))
        model.useAwayAccess = true
        model.receivePairingLink(try XCTUnwrap(URL(string: b.link)))
        XCTAssertFalse(model.useAwayAccess)
        model.phase = .connected; model.passcode = "unsaved"
        model.switchMac(a.fingerprint)
        XCTAssertEqual(model.phase, .setup)
        XCTAssertEqual(model.pairingText, a.link)
        XCTAssertTrue(model.useAwayAccess)
        XCTAssertTrue(model.passcode.isEmpty)
        model.forget()
        XCTAssertEqual(model.pairingText, b.link)
        XCTAssertFalse(model.useAwayAccess)
        XCTAssertEqual(model.savedMacs.count, 1)
    }

    func testOtherWiFiOffersAwayButReachableLocalMacDoesNot() async throws {
        let ready = expectation(description: "Route probe fixture")
        let disconnected = expectation(description: "Reachability probe completed without authentication")
        let stopped = expectation(description: "Route listener has closed")
        let server = try TerminalCreationServer(ready: ready, stopped: stopped, disconnected: disconnected, sessions: [])
        defer { server.stop() }
        await fulfillment(of: [ready], timeout: fixtureStartupTimeout)
        let port = try XCTUnwrap(server.listener.port)
        let suite = "trunkline-route-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let ticket = RemoteAccessTicket(config: .init(key: [1,2,3], expected: "12D3KooWfixture"), helper: "/ip4/203.0.113.1/udp/4001/quic-v1/p2p/12D3KooWfixture")
        let pairing = try PairingDetails(host: "192.0.2.1", port: port.rawValue, fingerprint: String(repeating: "f", count: 64), remote: ticket)
        let model = ConnectionModel(defaults: defaults,
            makeChannel: { _ in SecureChannel(connection: NWConnection(host: "127.0.0.1", port: port, using: .tcp)) })
        defer { model.disconnect() }
        model.pairingText = pairing.link
        model.networkChanged(available: true)
        await fulfillment(of: [disconnected], timeout: fixtureStartupTimeout)
        XCTAssertFalse(model.offerAwayAccess, "A reachable paired Mac should stay local")
        XCTAssertEqual(server.authentications, 0, "Reachability must not send credentials or occupy the Mac")
        server.stop()
        await fulfillment(of: [stopped], timeout: fixtureStartupTimeout)
        model.networkChanged(available: true)
        try await terminalEventually(timeout: 5) { model.offerAwayAccess }
        model.chooseAwayAccess()
        XCTAssertTrue(model.useAwayAccess)
        XCTAssertFalse(model.offerAwayAccess)
        model.networkChanged(available: true)
        XCTAssertFalse(model.offerAwayAccess, "Do not interrupt an already selected Away route")
        model.useAwayAccess = false
        model.networkChanged(available: false)
        XCTAssertFalse(model.offerAwayAccess, "Offline is not evidence of an Away route")
    }

    func testBusyRejectionArrivesBeforeChannelCloses() async throws {
        let ready = expectation(description: "Busy host fixture")
        let server = try TerminalCreationServer(ready: ready, sessions: [])
        server.rejection = "This Mac is in use on another device."
        defer { server.stop() }
        await fulfillment(of: [ready], timeout: fixtureStartupTimeout)
        let port = try XCTUnwrap(server.listener.port)
        let suite = "trunkline-busy-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = ConnectionModel(defaults: defaults,
            makeChannel: { _ in SecureChannel(connection: NWConnection(host: "127.0.0.1", port: port, using: .tcp)) })
        defer { model.disconnect() }
        model.pairingText = try PairingDetails(host: "127.0.0.1", port: port.rawValue, fingerprint: String(repeating: "1", count: 64)).link
        model.passcode = "fixture"
        model.connect()
        try await terminalEventually { model.error != nil }
        XCTAssertEqual(model.error, server.rejection)
        XCTAssertEqual(model.phase, .setup)
    }

    func testTerminalCreationWaitsForInitialSessionList() async throws {
        let ready = expectation(description: "Delayed terminal list fixture")
        let original = [TerminalSessionInfo(id: UUID(), title: "Existing session", kind: .shell, isRunning: true)]
        let server = try TerminalCreationServer(ready: ready, sessions: original)
        server.holdLists = true
        defer { server.stop() }
        await fulfillment(of: [ready], timeout: fixtureStartupTimeout)
        let suite = "trunkline-terminal-initial-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let port = try XCTUnwrap(server.listener.port)
        let model = ConnectionModel(defaults: defaults,
            makeChannel: { _ in SecureChannel(connection: NWConnection(host: "127.0.0.1", port: port, using: .tcp)) })
        defer { model.disconnect() }
        model.pairingText = try PairingDetails(host: "127.0.0.1", port: port.rawValue,
            fingerprint: String(repeating: "a", count: 64)).link
        model.passcode = "fixture-passcode"
        model.connect()
        try await terminalEventually { model.phase == .connected }
        model.createTerminal(.shell)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(server.creations, 0, "Load the existing IDs before creating a session")
        server.publish(original)
        try await terminalEventually { model.sessions.count == 1 }
        XCTAssertNil(model.selectedTerminalID, "The initial list must not be mistaken for a newly created session")
    }

    func testCreatingTerminalIgnoresOldListsAndRepeatedTaps() async throws {
        let ready = expectation(description: "Terminal fixture ready")
        let original = [TerminalSessionInfo(id: UUID(), title: "Build", kind: .shell, isRunning: true),
                        TerminalSessionInfo(id: UUID(), title: "Logs", kind: .shell, isRunning: true)]
        let server = try TerminalCreationServer(ready: ready, sessions: original)
        defer { server.stop() }
        await fulfillment(of: [ready], timeout: fixtureStartupTimeout)
        let suite = "trunkline-terminal-create-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let port = try XCTUnwrap(server.listener.port)
        let model = ConnectionModel(defaults: defaults,
            makeChannel: { _ in SecureChannel(connection: NWConnection(host: "127.0.0.1", port: port, using: .tcp)) })
        defer { model.disconnect() }
        model.pairingText = try PairingDetails(host: "127.0.0.1", port: port.rawValue,
            fingerprint: String(repeating: "a", count: 64)).link
        model.passcode = "fixture-passcode"
        model.connect()
        try await terminalEventually { model.sessions.count == 2 }
        model.selectedTerminalID = original[0].id
        model.createTerminal(.shell)
        model.createTerminal(.shell)
        try await terminalEventually { server.creations > 0 }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(server.creations, 1, "Repeated taps must not start duplicate remote shells")
        XCTAssertEqual(model.selectedTerminalID, original[0].id, "An unchanged list is not the new-session acknowledgement")
        let created = TerminalSessionInfo(id: UUID(), title: "Terminal 3", kind: .shell, isRunning: true)
        server.publish([created] + original)
        try await terminalEventually { model.sessions.count == 3 }
        XCTAssertEqual(model.selectedTerminalID, created.id, "Open the new ID regardless of snapshot ordering")
        XCTAssertFalse(model.isCreatingTerminal)
    }

    func testTerminalCreationTimeoutErrorAndDisconnectReleasePendingState() async throws {
        let ready = expectation(description: "Terminal timeout fixture ready")
        let server = try TerminalCreationServer(ready: ready, sessions: [])
        defer { server.stop() }
        await fulfillment(of: [ready], timeout: fixtureStartupTimeout)
        let suite = "trunkline-terminal-timeout-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let port = try XCTUnwrap(server.listener.port)
        let model = ConnectionModel(defaults: defaults, terminalCreationTimeout: 0.15,
            makeChannel: { _ in SecureChannel(connection: NWConnection(host: "127.0.0.1", port: port, using: .tcp)) })
        defer { model.disconnect() }
        model.pairingText = try PairingDetails(host: "127.0.0.1", port: port.rawValue,
            fingerprint: String(repeating: "a", count: 64)).link
        model.passcode = "fixture-passcode"
        model.connect()
        try await terminalEventually { model.hasLoadedTerminals }
        model.createTerminal(.shell)
        XCTAssertTrue(model.isCreatingTerminal)
        try await terminalEventually { !model.isCreatingTerminal }
        XCTAssertNotNil(model.error)
        XCTAssertEqual(model.phase, .connected, "A stalled operation must not discard a healthy connection")
        XCTAssertEqual(server.creations, 1, "Timeout must not automatically create another shell")
        server.publish([TerminalSessionInfo(id: UUID(), title: "Late session", kind: .shell, isRunning: true)])
        try await terminalEventually { model.sessions.count == 1 }
        XCTAssertNil(model.selectedTerminalID, "A late response may update the list but must not navigate after timeout")
        model.createTerminal(.shell)
        try await terminalEventually { server.creations == 2 }
        model.handleOperationError("Session limit reached", context: .init(.terminal))
        XCTAssertFalse(model.isCreatingTerminal)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(model.error, "Session limit reached", "Cancelled deadline must not overwrite the server error")
        model.createTerminal(.shell)
        try await terminalEventually { server.creations == 3 }
        model.disconnect()
        XCTAssertFalse(model.isCreatingTerminal)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNil(model.error, "A deadline from the closed connection must not publish an error")
        model.createTerminal(.shell)
        XCTAssertFalse(model.isCreatingTerminal, "Offline creation must not enter a pending state")
    }

    func testUnfocusedTerminalShortcutsFollowCurrentCursorModeWithoutShowingKeyboard() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let state = TerminalKeyboardFixtureState()
        let host = UIHostingController(rootView: TerminalKeyboardFixture(state: state))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        defer { window.isHidden = true; window.rootViewController = nil }
        func findTerminal(_ view: UIView) -> SessionTerminalView? {
            (view as? SessionTerminalView) ?? view.subviews.lazy.compactMap(findTerminal).first
        }
        let terminal = try XCTUnwrap(findTerminal(host.view))
        let output = TerminalInputRecorder()
        terminal.terminalDelegate = output
        for (mode, prefix) in [(false, UInt8(91)), (true, UInt8(79)), (false, UInt8(91))] {
            terminal.feed(text: mode ? "\u{1b}[?1h" : "\u{1b}[?1l")
            for (key, suffix) in [(TerminalShortcut.up, UInt8(65)), (.down, 66), (.right, 67), (.left, 68)] {
                output.bytes = []
                state.input.send(key)
                XCTAssertEqual(output.bytes, [27, prefix, suffix], "Shortcut \(key) must follow the terminal's current cursor mode")
                XCTAssertFalse(terminal.isFirstResponder, "A shortcut must not summon the keyboard")
            }
        }
        output.bytes = []
        for key in [TerminalShortcut.escape, .tab, .controlC, .controlD] { state.input.send(key) }
        XCTAssertEqual(output.bytes, [27, 9, 3, 4])
        XCTAssertFalse(state.keyboard)
    }

    func testTerminalAccessoryKeepsReadableTouchTargetsAtNarrowAndLargeTextSizes() throws {
        let terminal = SessionTerminalView(frame: CGRect(x: 0, y: 0, width: 320, height: 480), font: nil)
        let accessory = try XCTUnwrap(terminal.inputAccessoryView)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let host = UIViewController()
        window.rootViewController = host
        host.view.addSubview(accessory)
        window.isHidden = false
        defer { window.isHidden = true; accessory.removeFromSuperview(); window.rootViewController = nil }
        func buttons(in view: UIView) -> [UIButton] {
            (view as? UIButton).map { [$0] } ?? view.subviews.flatMap { buttons(in: $0) }
        }
        var normalHeight: CGFloat = 0
        for category in [UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge] {
            accessory.traitOverrides.preferredContentSizeCategory = category
            for width in [CGFloat(320), 430, 744, 1024] {
                let fitted = accessory.systemLayoutSizeFitting(CGSize(width: width, height: 0))
                accessory.frame = CGRect(x: 0, y: 0, width: width, height: max(52, fitted.height))
                accessory.bounds = CGRect(origin: .zero, size: accessory.frame.size)
                accessory.setNeedsLayout(); accessory.layoutIfNeeded()
                let keys = buttons(in: accessory)
                XCTAssertGreaterThan(keys.count, 8)
                if category == .large { normalHeight = keys.first?.bounds.height ?? 0 }
                else { XCTAssertGreaterThan(keys.first?.bounds.height ?? 0, normalHeight, "Large text must grow the keys, not clip or shrink labels") }
                for key in keys {
                    XCTAssertGreaterThanOrEqual(key.bounds.width, 44, "Key \(key.accessibilityLabel ?? key.currentTitle ?? "?") at width \(width)")
                    XCTAssertGreaterThanOrEqual(key.bounds.height, 44)
                }
                let ordered = keys.sorted { $0.convert($0.bounds, to: accessory).minX < $1.convert($1.bounds, to: accessory).minX }
                for pair in zip(ordered, ordered.dropFirst()) where pair.0.superview === pair.1.superview {
                    XCTAssertLessThanOrEqual(pair.0.frame.maxX, pair.1.frame.minX, "Keys must not overlap")
                }
            }
        }
    }

    func testTerminalAccessoryPreservesControlThroughResizeAndUsesApplicationCursorMode() throws {
        let terminal = SessionTerminalView(frame: CGRect(x: 0, y: 0, width: 320, height: 480), font: nil)
        let output = TerminalInputRecorder()
        terminal.terminalDelegate = output
        let accessory = try XCTUnwrap(terminal.inputAccessoryView)
        func find(_ label: String, in view: UIView) -> UIButton? {
            if let button = view as? UIButton, button.accessibilityLabel == label { return button }
            return view.subviews.lazy.compactMap { find(label, in: $0) }.first
        }
        let control = try XCTUnwrap(find("Control", in: accessory))
        control.sendActions(for: .touchUpInside)
        XCTAssertTrue(terminal.controlModifier)
        accessory.frame.size = CGSize(width: 744, height: 52)
        accessory.layoutIfNeeded()
        XCTAssertTrue(control.isSelected, "Rotation must not clear an armed Control key")
        terminal.insertText("c")
        XCTAssertEqual(output.bytes, [3])
        XCTAssertFalse(terminal.controlModifier)
        XCTAssertFalse(control.isSelected)
        terminal.insertText("x")
        XCTAssertEqual(output.bytes, [3, 120], "Control must apply to one key only")
        let left = try XCTUnwrap(find("Left arrow", in: accessory))
        output.bytes = []
        left.sendActions(for: .touchUpInside)
        XCTAssertEqual(output.bytes, [27, 91, 68])
        terminal.feed(text: "\u{1b}[?1h")
        output.bytes = []
        left.sendActions(for: .touchUpInside)
        XCTAssertEqual(output.bytes, [27, 79, 68], "Use application cursor mode requested by terminal programs")
        control.sendActions(for: .touchUpInside)
        _ = terminal.resignFirstResponder()
        XCTAssertFalse(terminal.controlModifier, "Leaving input must not leave a hidden modifier armed")
    }

    func testSilentCompanionStopsPingingAndReturnsToSetupAfterDeadline() async throws {
        let ready = expectation(description: "Companion fixture listening")
        let pongSent = expectation(description: "Initial ping received a real reply")
        let closed = expectation(description: "Stalled channel closed by client")
        let server = try HeartbeatCompanionServer(ready: ready, firstReply: pongSent, closed: closed)
        defer { server.stop() }
        await fulfillment(of: [ready], timeout: fixtureStartupTimeout)
        let suite = "trunkline-heartbeat-test-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let port = try XCTUnwrap(server.listener.port)
        let model = ConnectionModel(defaults: defaults, heartbeatInterval: 0.025, heartbeatTimeout: 0.15,
            makeChannel: { _ in SecureChannel(connection: NWConnection(host: "127.0.0.1", port: port, using: .tcp)) })
        defer { model.disconnect() }
        model.pairingText = try PairingDetails(host: "127.0.0.1", port: port.rawValue,
            fingerprint: String(repeating: "a", count: 64)).link
        model.passcode = "fixture-passcode"
        model.connect()
        await fulfillment(of: [pongSent], timeout: 2)
        try await terminalEventually { model.roundTripMS != nil }
        XCTAssertEqual(model.phase, .connected)
        await fulfillment(of: [closed], timeout: 2)
        XCTAssertEqual(model.phase, .setup)
        XCTAssertNotNil(model.error)
        XCTAssertNil(model.roundTripMS)
        XCTAssertEqual(server.pings, 2, "Do not overwrite the outstanding ping or queue more pings on a stalled link")
        XCTAssertTrue(model.passcode.isEmpty)
        // A fresh authenticated attempt must work after the stale connection closes.
        server.replyEveryPing = true
        model.passcode = "fixture-passcode"
        model.connect()
        try await terminalEventually { model.phase == .connected && model.roundTripMS != nil }
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(model.phase, .connected, "Timely replies must keep the new connection alive across deadlines")
        XCTAssertNil(model.error)
        XCTAssertGreaterThan(server.pings, 3)
    }

    func testClosingTerminalSurfaceReleasesItsConnectionModel() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        var state: TerminalKeyboardFixtureState? = TerminalKeyboardFixtureState()
        let releasedModel = WeakTerminalModel(state!.model)
        var host: UIHostingController<TerminalKeyboardFixture>? = UIHostingController(rootView: TerminalKeyboardFixture(state: state!))
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previousWindow?.makeKey() }
        host?.view.layoutIfNeeded()
        // Let the view's initial attach/layout work finish before releasing its owners.
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNotNil(state?.model.onTerminalData, "The real terminal must be mounted before checking its release")
        window.isHidden = true
        window.rootViewController = nil
        host = nil
        state = nil
        previousWindow?.makeKey()
        try await terminalEventually { releasedModel.value == nil }
    }

    func testTerminalNativeDismissalUpdatesToolbarAndDoesNotReopenOnRedraw() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let state = TerminalKeyboardFixtureState()
        let host = UIHostingController(rootView: TerminalKeyboardFixture(state: state))
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previousWindow?.makeKey() }
        host.view.layoutIfNeeded()
        func findTerminal(_ view: UIView) -> UIView? {
            if view.accessibilityLabel == "Mac terminal session" { return view }
            return view.subviews.lazy.compactMap(findTerminal).first
        }
        let terminal = try XCTUnwrap(findTerminal(host.view))
        state.keyboard = true
        try await terminalEventually { terminal.isFirstResponder }
        XCTAssertTrue(terminal.resignFirstResponder())
        try await terminalEventually { !state.keyboard }
        state.fontSize = 15 // A normal SwiftUI redraw must not undo native dismissal.
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(terminal.isFirstResponder)
        XCTAssertTrue(terminal.becomeFirstResponder()) // Native tap-to-focus path.
        try await terminalEventually { state.keyboard }
        XCTAssertTrue(terminal.resignFirstResponder())
        try await terminalEventually { !state.keyboard }
    }

    private func terminalEventually(timeout: TimeInterval = 2, _ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition(), file: file, line: line)
    }

    func testDesktopDiscoveryStillParsesServerInfoAfterTransportCancellationSupport() async throws {
        let ready = expectation(description: "Desktop listener ready")
        let received = expectation(description: "Discovery received")
        let closed = expectation(description: "Discovery connection closed")
        let loaded = expectation(description: "Desktop discovery completed")
        let xml = #"<?xml version="1.0" encoding="UTF-16"?><root status_code="200"><hostname>Test Mac</hostname><uniqueid>test-desktop</uniqueid><mac>00:00:00:00:00:00</mac><LocalIP>127.0.0.1</LocalIP><state>SUNSHINE_SERVER_FREE</state><PairStatus>0</PairStatus><HttpsPort>47984</HttpsPort></root>"#
        let server = try StalledDesktopServer(ready: ready, received: received, closed: closed, responseXML: xml)
        defer { server.stop() }
        await fulfillment(of: [ready], timeout: fixtureStartupTimeout)
        let engine = TrunklineStream()
        defer { engine.cancel() }
        engine.loadHost("127.0.0.1:\(try XCTUnwrap(server.port))", certificate: nil) { apps, error in
            XCTAssertNil(error)
            XCTAssertEqual(apps?.count, 0, "Unpaired discovery cannot expose authenticated applications")
            loaded.fulfill()
        }
        await fulfillment(of: [received, loaded, closed], timeout: 3)
        XCTAssertNil(engine.configuration(forApp: "1", title: "Desktop", width: 1280, height: 720, fps: 60,
            bitrate: 10000, directTouch: true, framePacing: false, stats: false), "Unpaired HTTP discovery cannot authorize a stream")
    }

    func testDesktopTimeoutReleasesBusyStateAndRejectsLateDiscovery() async throws {
        var engines: [ControlledDesktopEngine] = []
        let desktop = DesktopSession(discoveryTimeout: .milliseconds(40), pairingTimeout: .milliseconds(40), engineFactory: {
            let engine = ControlledDesktopEngine(); engines.append(engine); return engine
        })
        defer { desktop.close() }
        let link = try PairingDetails(host: "127.0.0.1", port: 47995, fingerprint: String(repeating: "f", count: 64)).link
        desktop.open(pairingLink: link) { _ in }
        let old = engines[0]
        XCTAssertTrue(desktop.busy)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(desktop.busy)
        XCTAssertFalse(desktop.hostReady)
        XCTAssertNotNil(desktop.error)
        XCTAssertEqual(old.cancellations, 1)
        desktop.refresh()
        XCTAssertTrue(desktop.busy)
        old.loads[0]([["id": "old", "name": "Stale"]], nil)
        await Task.yield()
        XCTAssertTrue(desktop.busy)
        XCTAssertTrue(desktop.apps.isEmpty)
        engines.last!.loads[0]([["id": "new", "name": "Desktop"]], nil)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(desktop.hostReady)
        XCTAssertEqual(desktop.apps.map(\.id), ["new"])
        XCTAssertNil(desktop.error)
    }

    func testDesktopCancelClearsPairingAndCloseClearsReadiness() async throws {
        var engines: [ControlledDesktopEngine] = []
        let desktop = DesktopSession(engineFactory: { let engine = ControlledDesktopEngine(); engines.append(engine); return engine })
        defer { desktop.close() }
        let link = try PairingDetails(host: "127.0.0.1", port: 47995, fingerprint: String(repeating: "e", count: 64)).link
        desktop.open(pairingLink: link) { _ in }
        engines[0].loads[0]([], nil)
        for _ in 0..<10 { await Task.yield() }
        desktop.pair()
        engines[0].pairingCode?("1234")
        XCTAssertTrue(desktop.busy)
        desktop.cancelPreparation()
        XCTAssertFalse(desktop.busy)
        XCTAssertNil(desktop.pin)
        XCTAssertFalse(desktop.hostReady)
        XCTAssertNil(desktop.error)
        XCTAssertEqual(engines[0].cancellations, 1)
        desktop.refresh()
        let callback = engines.last!.loads[0]
        desktop.close()
        callback([["id": "closed", "name": "Desktop"]], nil)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertFalse(desktop.busy)
        XCTAssertFalse(desktop.hostReady)
        XCTAssertTrue(desktop.apps.isEmpty)
    }

    func testPairingDeadlineRestoresRetryWithoutSavingAnOldResult() async throws {
        var engines: [ControlledDesktopEngine] = []
        let desktop = DesktopSession(pairingTimeout: .milliseconds(40), engineFactory: {
            let engine = ControlledDesktopEngine(); engines.append(engine); return engine
        })
        defer { desktop.close() }
        let link = try PairingDetails(host: "127.0.0.1", port: 47995, fingerprint: String(repeating: "d", count: 64)).link
        desktop.open(pairingLink: link) { _ in }
        engines[0].loads[0]([], nil)
        for _ in 0..<10 { await Task.yield() }
        desktop.pair()
        engines[0].pairingCode?("1234")
        let previousFailure = engines[0].failed
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(desktop.busy)
        XCTAssertNil(desktop.pin)
        XCTAssertFalse(desktop.hostReady)
        XCTAssertNotNil(desktop.error)
        let timeoutMessage = desktop.error
        previousFailure?("Late pairing failure")
        XCTAssertEqual(desktop.error, timeoutMessage)
        desktop.refresh()
        XCTAssertTrue(desktop.busy)
        XCTAssertEqual(engines.last?.loads.count, 1)
    }

    func testDesktopCancellationClosesAnInFlightHTTPRequest() async throws {
        let ready = expectation(description: "Loopback desktop listening")
        let received = expectation(description: "Actual desktop discovery request received")
        let closed = expectation(description: "Cancel closes the stalled HTTP connection")
        let server = try StalledDesktopServer(ready: ready, received: received, closed: closed)
        defer { server.stop() }
        await fulfillment(of: [ready], timeout: fixtureStartupTimeout)
        let port = try XCTUnwrap(server.port)
        let engine = TrunklineStream()
        defer { engine.cancel() }
        engine.loadHost("127.0.0.1:\(port)", certificate: nil) { _, _ in
            XCTFail("A cancelled discovery must not deliver a UI result")
        }
        await fulfillment(of: [received], timeout: 3)
        engine.cancel()
        await fulfillment(of: [closed], timeout: 1)
    }

    func testFileIOYieldsUIAndDisconnectDiscardsPendingRead() async throws {
        let files = ClientFiles()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data(repeating: 41, count: 256 * 1024).write(to: url)
        defer { files.reset(); try? FileManager.default.removeItem(at: url) }
        var replies: [WireMessage] = []
        let opened = expectation(description: "File opened away from the UI")
        files.send = { message in replies.append(message); opened.fulfill() }
        files.upload(url)
        XCTAssertTrue(files.isBusy)
        XCTAssertTrue(replies.isEmpty, "Opening the file must not block this UI turn")
        await fulfillment(of: [opened], timeout: fixtureStartupTimeout)
        XCTAssertEqual(replies, [.beginUpload(name: url.lastPathComponent, size: 262_144)])
        replies.removeAll()
        files.send = { replies.append($0) }
        files.handle(.uploadReady(id: UUID()))
        XCTAssertTrue(replies.isEmpty, "Reading bytes must not block this UI turn")
        files.reset()
        let nextOpened = expectation(description: "Next session can open its file")
        files.send = { message in
            replies.append(message)
            if case .beginUpload = message { nextOpened.fulfill() }
        }
        files.upload(url)
        await fulfillment(of: [nextOpened], timeout: fixtureStartupTimeout)
        XCTAssertEqual(replies, [.beginUpload(name: url.lastPathComponent, size: 262_144)],
                       "The old read must not send data into the reconnected session")
        XCTAssertNil(files.error)
    }

    func testRejectedPairingReleasesBusyStateAndOldEngine() {
        let model = ConnectionModel(), desktop = DesktopSession()
        defer { desktop.close(); model.disconnect() }
        let oldEngine = desktop.engine
        desktop.busy = true; desktop.pin = "1234"; desktop.hostReady = true
        model.onDesktopError = { [weak desktop] message, token in desktop?.receivePairingFailure(message, token: token) }
        model.handleOperationError("Pairing rejected", context: .init(.desktop, requestID: oldEngine.pairingToken))
        XCTAssertEqual(desktop.error, "Pairing rejected")
        XCTAssertFalse(desktop.busy, "Retry must become available immediately")
        XCTAssertNil(desktop.pin)
        XCTAssertFalse(desktop.hostReady, "Retry must rediscover the host")
        XCTAssertFalse(desktop.engine === oldEngine, "A cancelled engine cannot reuse an in-flight pairing request")
        XCTAssertNotEqual(desktop.engine.pairingToken, oldEngine.pairingToken)
        XCTAssertNil(model.error)
    }

    func testStalePairingRejectionCannotInterruptCurrentAttempt() {
        let desktop = DesktopSession()
        defer { desktop.close() }
        desktop.busy = true; desktop.pin = "1234"
        desktop.receivePairingFailure("Previous attempt failed", token: UUID().uuidString)
        XCTAssertTrue(desktop.busy)
        XCTAssertEqual(desktop.pin, "1234")
        XCTAssertNil(desktop.error)
    }

    func testCancelledEngineCallbacksCannotChangeRetryState() {
        let desktop = DesktopSession()
        defer { desktop.close() }
        desktop.busy = true; desktop.pin = "1234"
        desktop.receivePairingFailure("First attempt rejected", token: desktop.engine.pairingToken)
        let previousFailure = desktop.engine.failed
        let previousPIN = desktop.engine.pairingCode
        desktop.busy = true; desktop.pin = "5678"
        desktop.receivePairingFailure("Second attempt rejected", token: desktop.engine.pairingToken)
        desktop.busy = true; desktop.pin = "9012"; desktop.error = nil
        previousFailure?("Late engine failure")
        previousPIN?("0000")
        XCTAssertTrue(desktop.busy)
        XCTAssertEqual(desktop.pin, "9012")
        XCTAssertNil(desktop.error)
    }

    func testTerminalFailureIsVisibleWithoutCancellingUpload() throws {
        let model = ConnectionModel()
        defer { model.disconnect() }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("upload still running".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        model.files.upload(url)
        model.handleOperationError("Session ended", context: .init(.terminal))
        XCTAssertEqual(model.error, "Session ended")
        XCTAssertNotNil(model.files.transferName)
        XCTAssertNil(model.files.cancellation)
        XCTAssertNil(model.files.error)
    }

    func testClipboardFailureStaysInClipboardWithoutCancellingUpload() throws {
        let model = ConnectionModel()
        defer { model.disconnect() }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("upload still running".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        model.files.upload(url)
        model.handleOperationError("Clipboard too large", context: .init(.clipboard))
        XCTAssertEqual(model.files.clipboardError, "Clipboard too large")
        XCTAssertNil(model.error)
        XCTAssertNotNil(model.files.transferName)
        XCTAssertNil(model.files.cancellation)
        XCTAssertNil(model.files.error)
        _ = model.files.handle(.clipboard("recovered"))
        XCTAssertNil(model.files.clipboardError)
    }

    func testClipboardFailureIsLocalWhenFilesAreIdle() {
        let model = ConnectionModel()
        defer { model.disconnect() }
        model.handleOperationError("Clipboard unavailable", context: .init(.clipboard))
        XCTAssertEqual(model.files.clipboardError, "Clipboard unavailable")
        XCTAssertNil(model.error)
    }

    func testFileFailureCancelsOnlyItsTransfer() throws {
        let model = ConnectionModel()
        defer { model.disconnect() }
        model.files.configure(fileFeatures: ["cancellation"])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("upload".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        model.files.upload(url)
        model.handleOperationError("Destination unavailable", context: .init(.files))
        XCTAssertNotNil(model.files.cancellation)
        XCTAssertEqual(model.files.error, "Destination unavailable")
        XCTAssertNil(model.error)
    }

    func testLegacyFileFailurePreservesConnectionUntilExplicitDisconnect() {
        let model = ConnectionModel()
        defer { model.disconnect() }
        model.phase = .connected
        model.files.download(.init(name: "example.txt", path: "example.txt", isDirectory: false, size: 3))
        model.handleOperationError("Destination unavailable", context: .init(.files))
        XCTAssertTrue(model.files.requiresReconnect)
        XCTAssertNil(model.files.cancellation)
        XCTAssertEqual(model.phase, .connected, "A file failure cannot disconnect desktop access")
        XCTAssertNil(model.error)
        model.files.onReconnect?()
        XCTAssertEqual(model.phase, .setup)
        XCTAssertFalse(model.files.requiresReconnect)
    }
}

private final class ControlledDesktopEngine: TrunklineStream {
    var loads: [([[String: String]]?, String?) -> Void] = []
    var cancellations = 0
    override func loadHost(_ address: String, certificate: Data?, completion: @escaping ([[String: String]]?, String?) -> Void) { loads.append(completion) }
    override func pair() {}
    override func cancel() { cancellations += 1; super.cancel() }
}

/// Real loopback HTTP peer: stall by default, or return a bounded server-info fixture.
/// A remote EOF in the stalled mode proves cancellation rather than hiding a callback.
private final class StalledDesktopServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "Trunkline.tests.stalled-desktop")
    private var connections: [NWConnection] = []
    private let received: XCTestExpectation
    private let closed: XCTestExpectation
    private let responseXML: String?
    var port: UInt16? { listener.port?.rawValue }
    init(ready: XCTestExpectation, received: XCTestExpectation, closed: XCTestExpectation, responseXML: String? = nil) throws {
        self.received = received; self.closed = closed
        self.responseXML = responseXML
        listener = try NWListener(using: .tcp, on: .any)
        listener.stateUpdateHandler = { state in if case .ready = state { ready.fulfill() } }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            self.connections.append(connection)
            connection.start(queue: self.queue)
            self.receive(connection, first: true)
        }
        listener.start(queue: queue)
    }
    private func receive(_ connection: NWConnection, first: Bool) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
            guard let self else { return }
            let receivedBytes = data?.isEmpty == false
            if first && receivedBytes { self.received.fulfill() }
            if complete || error != nil { self.closed.fulfill(); return }
            if first && receivedBytes, let xml = self.responseXML {
                let body = Data(xml.utf8)
                let headers = Data("HTTP/1.1 200 OK\r\nContent-Type: application/xml\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
                connection.send(content: headers + body, completion: .contentProcessed { _ in connection.cancel() })
            }
            self.receive(connection, first: first && !receivedBytes)
        }
    }
    func stop() {
        queue.async { [self] in listener.cancel(); connections.forEach { $0.cancel() }; connections.removeAll() }
    }
}

@MainActor private final class TerminalInputRecorder: NSObject, @preconcurrency TerminalViewDelegate {
    var bytes: [UInt8] = []
    func send(source: TerminalView, data: ArraySlice<UInt8>) { bytes.append(contentsOf: data) }
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func scrolled(source: TerminalView, position: Double) {}
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
    func clipboardCopy(source: TerminalView, content: Data) {}
    func bell(source: TerminalView) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}

@MainActor private final class TerminalKeyboardFixtureState: ObservableObject {
    @Published var keyboard = false
    @Published var fontSize: CGFloat = 14
    let model = ConnectionModel()
    let sessionID = UUID()
    let input = TerminalShortcutInput()
}

@MainActor private final class WeakTerminalModel {
    weak var value: ConnectionModel?
    init(_ value: ConnectionModel) { self.value = value }
}

private struct TerminalKeyboardFixture: View {
    @ObservedObject var state: TerminalKeyboardFixtureState
    var body: some View {
        TerminalSurface(model: state.model, sessionID: state.sessionID,
                        showKeyboard: $state.keyboard, fontSize: state.fontSize, input: state.input)
    }
}

@MainActor private final class HeartbeatCompanionServer {
    let listener: NWListener
    private var channel: SecureChannel?
    private(set) var pings = 0
    var replyEveryPing = false
    init(ready: XCTestExpectation, firstReply: XCTestExpectation, closed: XCTestExpectation) throws {
        listener = try NWListener(using: .tcp, on: .any)
        listener.stateUpdateHandler = { state in if case .ready = state { ready.fulfill() } }
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated {
                guard let self else { return }
                let channel = SecureChannel(connection: connection)
                self.channel = channel
                channel.onMessage = { [weak self, weak channel] message in
                    guard let self else { return }
                    switch message {
                    case let .authenticate(passcode):
                        XCTAssertEqual(passcode, "fixture-passcode")
                        channel?.send(.accepted(name: "Fixture Mac", display: .fallback))
                    case .ping:
                        self.pings += 1
                        if self.pings == 1 || self.replyEveryPing { channel?.send(.pong) }
                        if self.pings == 1 { firstReply.fulfill() }
                    default: break
                    }
                }
                channel.onClose = { _ in closed.fulfill() }
                channel.start()
            }
        }
        listener.start(queue: .main)
    }
    func stop() {
        listener.cancel()
        channel?.onClose = nil
        channel?.close()
        channel = nil
    }
}

@MainActor private final class TerminalCreationServer {
    let listener: NWListener
    private var channel: SecureChannel?
    private var sessions: [TerminalSessionInfo]
    var holdLists = false
    var rejection: String?
    private(set) var authentications = 0
    private(set) var creations = 0
    init(ready: XCTestExpectation, stopped: XCTestExpectation? = nil,
         disconnected: XCTestExpectation? = nil, sessions: [TerminalSessionInfo]) throws {
        self.sessions = sessions
        listener = try NWListener(using: .tcp, on: .any)
        listener.stateUpdateHandler = {
            if case .ready = $0 { ready.fulfill() }
            if case .cancelled = $0 { stopped?.fulfill() }
        }
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated {
                guard let self else { return }
                let channel = SecureChannel(connection: connection)
                self.channel = channel
                channel.onClose = { _ in disconnected?.fulfill() }
                channel.onMessage = { [weak self, weak channel] message in
                    guard let self else { return }
                    switch message {
                    case .authenticate:
                        self.authentications += 1
                        if let rejection = self.rejection { channel?.reject(rejection) }
                        else { channel?.send(.accepted(name: "Fixture Mac", display: .fallback)) }
                    case .ping: channel?.send(.pong)
                    case .listTerminals:
                        if !self.holdLists { channel?.send(.terminals(self.sessions)) }
                    case .createTerminal:
                        self.creations += 1
                        channel?.send(.terminals(self.sessions))
                    default: break
                    }
                }
                channel.start()
            }
        }
        listener.start(queue: .main)
    }
    func publish(_ sessions: [TerminalSessionInfo]) {
        self.sessions = sessions
        channel?.send(.terminals(sessions))
    }
    func stop() { listener.cancel(); channel?.onClose = nil; channel?.close(); channel = nil }
}

private final class RecognizedWorkspaceSwipe: UISwipeGestureRecognizer {
    private var reportedState: UIGestureRecognizer.State = .possible
    override var state: UIGestureRecognizer.State {
        get { reportedState }
        set { reportedState = newValue }
    }
}
