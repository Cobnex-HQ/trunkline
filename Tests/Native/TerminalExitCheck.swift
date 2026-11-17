import Foundation

@main struct TerminalExitCheck {
    @MainActor static func main() async throws {
        let sessions = TerminalSessions()
        var states: [TerminalSessionInfo] = []
        var output = Data()
        sessions.send = { message in
            if case let .terminals(value) = message { states = value }
            if case let .terminalOutput(_, bytes, _) = message { output.append(bytes) }
        }
        defer { sessions.closeAll() }
        _ = sessions.handle(.createTerminal(kind: .shell, title: "Exit regression"))
        let id = states[0].id
        _ = sessions.handle(.attachTerminal(id: id))
        _ = sessions.handle(.terminalInput(id: id, bytes: Data("printf '__EXIT_%s__\\n' FINISHED; exit\r".utf8)))
        let deadline = ContinuousClock.now + .seconds(10)
        while states.first?.isRunning == true, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        precondition(states.first?.isRunning == false && sessions.runningCount == 0, "Shell exit must publish ended state")
        precondition(String(decoding: output, as: UTF8.self).contains("__EXIT_FINISHED__"), "Final output must arrive before exit")
        _ = sessions.handle(.createTerminal(kind: .shell, title: "Next shell"))
        precondition(states.count == 2 && states.last?.isRunning == true, "A fresh terminal must work after exit")
        _ = sessions.handle(.closeTerminal(id: id))
        precondition(states.count == 1, "Ended sessions must remain removable")
        print("PASS: real shell exit, final output, ended state, removal and subsequent session creation")
    }
}
