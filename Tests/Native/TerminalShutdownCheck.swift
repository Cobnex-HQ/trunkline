import Foundation
import Darwin

@main struct TerminalShutdownCheck {
    @MainActor static func main() async throws {
        let manager = TerminalSessions()
        var states: [TerminalSessionInfo] = []
        var output = ""
        manager.send = { message in
            if case let .terminals(value) = message { states = value }
            if case let .terminalOutput(_, bytes, _) = message { output += String(decoding: bytes, as: UTF8.self) }
        }
        _ = manager.handle(.createTerminal(kind: .shell, title: "Stubborn command"))
        let ending = states[0].id
        _ = manager.handle(.createTerminal(kind: .shell, title: "Protected session"))
        let protected = states[1].id
        _ = manager.handle(.attachTerminal(id: ending))
        let command = "/bin/sh -c 'trap \"\" HUP TERM; printf \"__LIVE_%d__\\n\" $$; while :; do /bin/sleep 1; done'\r"
        _ = manager.handle(.terminalInput(id: ending, bytes: Data(command.utf8)))
        let regex = try NSRegularExpression(pattern: "__LIVE_([0-9]+)__")
        var child: pid_t?
        let readyDeadline = ContinuousClock.now + .seconds(10)
        while child == nil, ContinuousClock.now < readyDeadline {
            if let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
               let range = Range(match.range(at: 1), in: output) { child = pid_t(output[range]) }
            try await Task.sleep(for: .milliseconds(20))
        }
        guard let child else { manager.closeAll(); throw NSError(domain: "Fixture command did not start", code: 1) }
        defer { kill(child, SIGKILL); manager.closeAll() }
        _ = manager.handle(.closeTerminal(id: ending))
        let retainedUntilExit = states.contains { $0.id == ending && $0.isRunning }
        // A duplicate request must not remove or restart the pending shutdown.
        _ = manager.handle(.closeTerminal(id: ending))
        let deadline = ContinuousClock.now + .seconds(5)
        while (kill(child, 0) == 0 || states.contains { $0.id == ending }), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }
        let childStopped = kill(child, 0) != 0
        let removedAfterExit = !states.contains { $0.id == ending }
        output = ""
        _ = manager.handle(.attachTerminal(id: protected))
        _ = manager.handle(.terminalInput(id: protected, bytes: Data("printf '__PROTECTED_%s__\\n' ALIVE\r".utf8)))
        let responseDeadline = ContinuousClock.now + .seconds(3)
        while !output.contains("__PROTECTED_ALIVE__"), ContinuousClock.now < responseDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        guard retainedUntilExit, childStopped, removedAfterExit, output.contains("__PROTECTED_ALIVE__") else {
            print("FAIL: retained until exit=\(retainedUntilExit), stubborn child stopped=\(childStopped), removed=\(removedAfterExit), other session responds=\(output.contains("__PROTECTED_ALIVE__"))")
            kill(child, SIGKILL); manager.closeAll()
            exit(1)
        }
        output = ""
        _ = manager.handle(.terminalInput(id: protected, bytes: Data(command.utf8)))
        var secondChild: pid_t?
        let secondDeadline = ContinuousClock.now + .seconds(5)
        while secondChild == nil, ContinuousClock.now < secondDeadline {
            if let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
               let range = Range(match.range(at: 1), in: output) { secondChild = pid_t(output[range]) }
            try await Task.sleep(for: .milliseconds(20))
        }
        guard let secondChild else { throw NSError(domain: "Second fixture did not start", code: 2) }
        defer { kill(secondChild, SIGKILL) }
        let stopped = await manager.shutdown()
        precondition(stopped && manager.runningCount == 0, "Quit must await complete terminal cleanup")
        print("PASS: confirmed shutdown, stubborn foreground cleanup, duplicate close, isolated session survival and awaited quit")
    }
}
