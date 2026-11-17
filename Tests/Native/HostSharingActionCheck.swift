import Foundation

@main struct HostSharingActionCheck {
    @MainActor static func main() {
        var executions = 0
        var prompts = 0
        let cancelled = HostSharingAction.turnOff.perform(connected: true, runningTerminals: 2, confirm: { prompt in
            prompts += 1
            precondition(prompt.message.contains("disconnect"))
            precondition(prompt.message.contains("2 terminal sessions"))
            precondition(prompt.message.contains("keep running"))
            return false
        }, operation: { executions += 1 })
        precondition(!cancelled && prompts == 1 && executions == 0)
        let approved = HostSharingAction.turnOff.perform(connected: false, runningTerminals: 1, confirm: { prompt in
            precondition(prompt.message.contains("1 terminal session"))
            return true
        }, operation: { executions += 1 })
        precondition(approved && executions == 1)
        _ = HostSharingAction.changePasscode.perform(connected: false, runningTerminals: 0, confirm: { _ in
            preconditionFailure("Initial setup must not show an interruption warning")
        }, operation: { executions += 1 })
        precondition(executions == 2)
        _ = HostSharingAction.changeFolder.perform(connected: true, runningTerminals: 0, confirm: { _ in false }, operation: { executions += 1 })
        precondition(executions == 2)
        _ = HostSharingAction.disconnect.perform(connected: true, runningTerminals: 3, confirm: { prompt in
            precondition(prompt.message.contains("Sharing stays on"))
            return false
        }, operation: { executions += 1 })
        precondition(executions == 2)
        print("PASS: sharing interruption confirmation, cancellation and terminal preservation copy")
    }
}
