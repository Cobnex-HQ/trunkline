// Adapted from macowl's IOKit/pmset implementation.
// Copyright (c) 2026 rgcsekaraa. MIT license: Resources/macowl-LICENSE.txt.
// Adds original-policy restoration, atomic recovery markers, and session assertions.
import AppKit
import Combine
import IOKit.pwr_mgt
import ServiceManagement
#if canImport(TrunklineCore)
import TrunklineCore
#endif

@MainActor
final class KeepAwakeManager: ObservableObject {
    @Published private(set) var mode: AwakeMode = .off
    @Published var error: String?
    @Published private(set) var needsRecovery = false
    @Published private(set) var loginStatus: SMAppService.Status
    var startsAtLogin: Bool { loginStatus == .enabled }
    var loginRequested: Bool { loginStatus == .enabled || loginStatus == .requiresApproval }
    private let readLoginStatus: () -> SMAppService.Status
    private let registerLogin: () throws -> Void
    private let unregisterLogin: () throws -> Void
    private var activationObservation: AnyCancellable?
    private var assertion: IOPMAssertionID = 0
    private var sessionAssertion: IOPMAssertionID = 0
    private var awayAssertion: IOPMAssertionID = 0
    var remoteState: MacAwakeState {
        MacAwakeState(mode: mode, sessionActive: sessionAssertion != 0,
                      awayAccessActive: awayAssertion != 0,
                      requiresLocalChange: mode == .lidClosed || needsRecovery)
    }
    /// Remote controls never run pmset or ask for local administrator approval.
    func applyRemotely(_ newMode: AwakeMode) throws {
        guard newMode != .lidClosed, mode != .lidClosed, !needsRecovery, try loadRecovery() == nil else {
            throw PowerError.failed("Change closed-lid or recovery settings on the Mac first.")
        }
        let replacement = try createAssertion(for: newMode)
        if assertion != 0 { IOPMAssertionRelease(assertion) }
        assertion = replacement
        mode = newMode
        error = nil
    }
    private var marker: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Trunkline", isDirectory: true).appendingPathComponent("sleep-policy.json")
    }
    private struct Recovery: Codable { let originallyDisabled: Bool }
    init(loginStatus: @escaping () -> SMAppService.Status = { SMAppService.mainApp.status },
         registerLogin: @escaping () throws -> Void = { try SMAppService.mainApp.register() },
         unregisterLogin: @escaping () throws -> Void = { try SMAppService.mainApp.unregister() },
         notificationCenter: NotificationCenter = .default) {
        readLoginStatus = loginStatus
        self.registerLogin = registerLogin
        self.unregisterLogin = unregisterLogin
        self.loginStatus = loginStatus()
        needsRecovery = FileManager.default.fileExists(atPath: marker.path)
        activationObservation = notificationCenter.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.refreshLoginStatus() }
            }
    }
    @discardableResult func apply(_ newMode: AwakeMode) -> Bool {
        do {
            let original = try loadRecovery()?.originallyDisabled
            let current = try readDisabled()
            let plan = PowerTransition(mode: newMode, systemDisabled: current, originalDisabled: original)
            // Persist before invoking the privileged operation: a crash during or after
            // authorization must still leave enough information to restore the setting.
            if newMode == .lidClosed, original == nil {
                try FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(Recovery(originallyDisabled: current)).write(to: marker, options: .atomic)
            }
            if let change = plan.changeDisabled {
                do { try setDisabledWithAuthorization(change) }
                catch {
                    if original == nil { try? FileManager.default.removeItem(at: marker) }
                    throw error
                }
            }
            if newMode != .lidClosed { try? FileManager.default.removeItem(at: marker) }
            let newAssertion = try createAssertion(for: newMode)
            if assertion != 0 { IOPMAssertionRelease(assertion) }
            assertion = newAssertion; mode = newMode; needsRecovery = false
            return true
        } catch PowerError.cancelled { return false }
        catch { self.error = error.localizedDescription; needsRecovery = FileManager.default.fileExists(atPath: marker.path); return false }
    }
    func recover() { _ = apply(.off) }
    func continueRecoveredSession() {
        guard (try? loadRecovery()) != nil else { return }
        if (try? readDisabled()) == true {
            mode = .lidClosed; needsRecovery = false
        } else { recover() }
    }
    func setSessionActive(_ active: Bool) {
        if sessionAssertion != 0 { IOPMAssertionRelease(sessionAssertion); sessionAssertion = 0 }
        if active {
            do { sessionAssertion = try createAssertion(for: RemoteSessionPolicy.awakeMode) }
            catch { self.error = error.localizedDescription }
        }
    }
    /// Keep the host reachable before a phone connects. This per-process IOKit
    /// assertion needs no administrator prompt and does not alter pmset policy.
    func setAwayAccessActive(_ active: Bool) {
        if active == (awayAssertion != 0) { return }
        if awayAssertion != 0 { IOPMAssertionRelease(awayAssertion); awayAssertion = 0 }
        if active {
            do { awayAssertion = try createAssertion(for: .system) }
            catch { self.error = error.localizedDescription }
        }
    }
    func refreshLoginStatus() { loginStatus = readLoginStatus() }
    func setStartsAtLogin(_ enabled: Bool) {
        refreshLoginStatus()
        error = nil
        guard enabled != loginRequested else { return }
        defer { refreshLoginStatus() }
        do {
            if enabled { try registerLogin() } else { try unregisterLogin() }
        } catch { self.error = error.localizedDescription }
    }
    func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }
    @discardableResult func prepareToQuit() -> Bool {
        // Declining restoration cancels Quit, keeping the application and its recovery
        // state available rather than silently leaving a global sleep override behind.
        guard apply(.off) else { return false }
        setSessionActive(false); setAwayAccessActive(false); return true
    }
    private func loadRecovery() throws -> Recovery? {
        guard FileManager.default.fileExists(atPath: marker.path) else { return nil }
        return try JSONDecoder().decode(Recovery.self, from: Data(contentsOf: marker))
    }
    private func readDisabled() throws -> Bool {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset"); process.arguments = ["-g"]
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        guard process.terminationStatus == 0, let output = String(data: data, encoding: .utf8) else { throw PowerError.failed("Could not read the Mac’s sleep settings.") }
        for line in output.split(separator: "\n") {
            let fields = line.split(whereSeparator: { $0.isWhitespace })
            if fields.first == "SleepDisabled", fields.count >= 2 { return fields[1] == "1" }
        }
        return false
    }
    private func setDisabledWithAuthorization(_ disabled: Bool) throws {
        // Only a fixed boolean reaches the command. No hostnames, paths, passcodes,
        // or client-supplied strings are interpolated into privileged shell code.
        let source = "do shell script \"/usr/bin/pmset -a disablesleep \(disabled ? 1 : 0)\" with administrator privileges"
        guard let script = NSAppleScript(source: source) else { throw PowerError.failed("Could not prepare administrator authorization.") }
        var details: NSDictionary?
        script.executeAndReturnError(&details)
        if let details {
            if details["NSAppleScriptErrorNumber"] as? Int == -128 { throw PowerError.cancelled }
            throw PowerError.failed(details["NSAppleScriptErrorMessage"] as? String ?? "macOS refused to change the sleep setting.")
        }
        guard try readDisabled() == disabled else { throw PowerError.failed("macOS did not apply the requested sleep setting.") }
    }
    private func createAssertion(for mode: AwakeMode) throws -> IOPMAssertionID {
        guard mode != .off else { return 0 }
        var id: IOPMAssertionID = 0
        let type = mode == .systemAndDisplay ? kIOPMAssertionTypePreventUserIdleDisplaySleep : kIOPMAssertionTypePreventUserIdleSystemSleep
        let status = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "Trunkline: \(mode.title)" as CFString, &id)
        guard status == kIOReturnSuccess else { throw PowerError.failed("Could not hold the keep-awake assertion (\(status)).") }
        return id
    }
    enum PowerError: LocalizedError {
        case cancelled, failed(String)
        var errorDescription: String? { switch self { case .cancelled: "Authorization cancelled."; case let .failed(message): message } }
    }
}
