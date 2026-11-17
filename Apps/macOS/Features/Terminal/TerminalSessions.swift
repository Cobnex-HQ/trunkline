import Foundation
import Combine
import Darwin
#if canImport(TrunklineCore)
import TrunklineCore
#endif

@MainActor
final class TerminalSession {
    let id = UUID()
    var title: String
    let kind: TerminalKind
    private(set) var isRunning = true
    private(set) var history = Data()
    var onOutput: ((Data) -> Void)?
    var onInputError: ((String) -> Void)?
    var onExit: (() -> Void)?
    var onStateChange: (() -> Void)?
    private let fd: Int32
    private let pid: pid_t
    private let reader: DispatchSourceRead
    private let process: DispatchSourceProcess
    private var killTimeout: DispatchWorkItem?
    private var writer: DispatchSourceWrite?
    private var writerSuspended = true
    private var pendingInput = Data()
    private var closing = false
    private var leaderExited = false
    private var forceAfter: ContinuousClock.Instant?
    var info: TerminalSessionInfo { TerminalSessionInfo(id: id, title: title, kind: kind, isRunning: isRunning, isStopping: closing && isRunning) }
    init(kind: TerminalKind, title: String) throws {
        self.kind = kind; self.title = title
        var descriptor: Int32 = -1
        let spawned = NSHomeDirectory().withCString { MPStartTerminal($0, &descriptor) }
        guard spawned > 0 else { throw SessionError.spawnFailed }
        fd = descriptor; pid = spawned
        reader = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: .main)
        process = DispatchSource.makeProcessSource(identifier: spawned, eventMask: .exit, queue: .main)
        let writer = DispatchSource.makeWriteSource(fileDescriptor: descriptor, queue: .main)
        self.writer = writer
        writer.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.flushInput() } }
        reader.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.readAvailable() } }
        reader.setCancelHandler { Darwin.close(descriptor) }
        // Retain until the child exits so closed sessions are reaped even after removal.
        process.setEventHandler { [self] in
            MainActor.assumeIsolated {
                self.leaderExited = true
                self.readAvailable()
                self.close()
                self.pollShutdown()
            }
        }
        reader.resume(); process.resume()
        if let command = kind.launchCommand { input(Data((command + "\r").utf8)) }
    }
    func input(_ data: Data) {
        guard isRunning, !closing, TerminalLimits.validInput(data), !data.isEmpty else { return }
        guard pendingInput.count + data.count <= 256 * 1024 else {
            onInputError?("Terminal input is backed up. Wait for the Mac to consume input before pasting again."); return
        }
        pendingInput.append(data); flushInput()
    }
    private func flushInput() {
        guard isRunning, !closing else { return }
        while !pendingInput.isEmpty {
            let snapshot = pendingInput
            let sent = snapshot.withUnsafeBytes { Darwin.write(fd, $0.baseAddress!, $0.count) }
            if sent > 0 { pendingInput = Data(pendingInput.dropFirst(sent)) }
            else if errno == EINTR { continue }
            else if errno == EAGAIN {
                if writerSuspended { writerSuspended = false; writer?.resume() }
                return
            } else {
                pendingInput = Data(); onInputError?("Terminal input could not be delivered. The session may have ended."); break
            }
        }
        if !writerSuspended { writer?.suspend(); writerSuspended = true }
    }
    private func stopWriter() {
        if let writer {
            writer.cancel()
            if writerSuspended { writer.resume() }
            self.writer = nil
        }
        pendingInput = Data()
    }
    func resize(columns: Int, rows: Int) {
        guard isRunning, TerminalLimits.validSize(columns: columns, rows: rows) else { return }
        _ = MPResizeTerminal(fd, UInt16(columns), UInt16(rows))
    }
    func close() {
        guard isRunning, !closing else { return }
        closing = true; stopWriter()
        forceAfter = .now + .seconds(2)
        _ = MPSignalTerminalMembers(pid, SIGHUP)
        onStateChange?()
        pollShutdown()
    }
    private func pollShutdown() {
        guard isRunning, closing else { return }
        killTimeout?.cancel()
        let force = forceAfter.map { ContinuousClock.now >= $0 } ?? false
        let remaining = MPSignalTerminalMembers(pid, force ? SIGKILL : 0)
        if leaderExited && remaining == 0 {
            readAvailable()
            isRunning = false
            reader.cancel()
            // Reap only after the session is empty. Its ID cannot be reused
            // while a delayed shutdown check could still send a signal.
            waitpid(pid, nil, 0)
            process.setEventHandler {}; process.cancel()
            killTimeout = nil
            onExit?()
            return
        }
        let task = DispatchWorkItem { [weak self] in self?.pollShutdown() }
        killTimeout = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: task)
    }
    private func readAvailable() {
        var buffer = [UInt8](repeating: 0, count: 32 * 1024)
        var total = 0
        while total < 256 * 1024 {
            let count = Darwin.read(fd, &buffer, buffer.count)
            guard count > 0 else { break }
            let data = Data(buffer.prefix(count)); total += count
            history.append(data)
            if history.count > 512 * 1024 { history = Data(history.suffix(512 * 1024)) }
            onOutput?(data)
        }
    }
    enum SessionError: LocalizedError {
        case spawnFailed
        var errorDescription: String? { "Could not create a Mac terminal session." }
    }
}

@MainActor
final class TerminalSessions: ObservableObject {
    @Published private(set) var summaries: [TerminalSessionInfo] = []
    private var sessions: [TerminalSession] = []
    private var attached: UUID?
    private var removals: Set<UUID> = []
    var send: ((WireMessage) -> Void)?
    var runningCount: Int { sessions.filter(\.isRunning).count }
    func detach() { attached = nil; send = nil }
    func closeAll() { sessions.forEach { $0.close() } }
    func shutdown() async -> Bool {
        closeAll()
        let deadline = ContinuousClock.now + .seconds(6)
        while runningCount > 0, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        return runningCount == 0
    }
    func handle(_ message: WireMessage) -> Bool {
        switch message {
        case .listTerminals: publish()
        case let .renameTerminal(id, title):
            let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, title.count <= 80, !title.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
                  let session = sessions.first(where: { $0.id == id }) else {
                send?(.operationError("Use a session name of 1–80 characters.", context: .init(.terminal))); return true
            }
            session.title = title; publish()
        case let .createTerminal(kind, title):
            guard sessions.count < 8, title.count <= 80 else { send?(.operationError("Up to 8 terminal sessions are supported. Close an old session first.", context: .init(.terminal))); return true }
            do {
                var ordinal = 1
                while sessions.contains(where: { $0.title == TerminalSessionLabel.title(kind: kind, ordinal: ordinal) }) { ordinal += 1 }
                let session = try TerminalSession(kind: kind, title: title.isEmpty ? TerminalSessionLabel.title(kind: kind, ordinal: ordinal) : title)
                session.onOutput = { [weak self, weak session] bytes in
                    guard let self, let session, self.attached == session.id else { return }
                    self.send?(.terminalOutput(id: session.id, bytes: bytes, reset: false))
                }
                session.onInputError = { [weak self] in self?.send?(.operationError($0, context: .init(.terminal))) }
                session.onStateChange = { [weak self] in self?.publish() }
                session.onExit = { [weak self, weak session] in
                    guard let self, let session else { return }
                    if self.removals.remove(session.id) != nil { self.remove(session.id) }
                    self.publish()
                }
                sessions.append(session); publish()
            } catch { send?(.operationError(error.localizedDescription, context: .init(.terminal))) }
        case let .attachTerminal(id):
            guard let session = sessions.first(where: { $0.id == id }) else { send?(.operationError("This session no longer exists.", context: .init(.terminal))); return true }
            attached = id; send?(.terminalOutput(id: id, bytes: session.history, reset: true))
        case let .terminalInput(id, bytes):
            guard TerminalLimits.validInput(bytes) else { return true }
            sessions.first(where: { $0.id == id })?.input(bytes)
        case let .resizeTerminal(id, columns, rows): sessions.first(where: { $0.id == id })?.resize(columns: columns, rows: rows)
        case let .closeTerminal(id):
            if let session = sessions.first(where: { $0.id == id }), session.isRunning {
                removals.insert(id)
                session.close()
            } else { remove(id) }
            publish()
        default: return false
        }
        return true
    }
    private func publish() {
        summaries = sessions.map(\.info)
        send?(.terminals(summaries))
    }
    private func remove(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        removals.remove(id)
        if attached == id { attached = nil }
    }
}
