import AppKit

struct HostSharingPrompt {
    let title: String
    let message: String
    let button: String
}

enum HostSharingAction {
    case turnOff, disconnect, changePasscode, changeFolder, disableAway

    @MainActor @discardableResult
    func perform(connected: Bool, runningTerminals: Int,
                 confirm: @MainActor (HostSharingPrompt) -> Bool = HostSharingAction.show,
                 operation: () -> Void) -> Bool {
        let mustConfirm = self == .turnOff || self == .disconnect || connected || runningTerminals > 0
        if mustConfirm && !confirm(prompt(connected: connected, runningTerminals: runningTerminals)) { return false }
        operation()
        return true
    }

    func prompt(connected: Bool, runningTerminals: Int) -> HostSharingPrompt {
        let title: String, button: String, effect: String
        switch self {
        case .turnOff:
            title = "Turn off sharing?"; button = "Turn off sharing"
            effect = "Devices cannot connect until you turn sharing on again."
        case .disconnect:
            title = "Disconnect this device?"; button = "Disconnect device"
            effect = "Sharing stays on so another device can connect."
        case .changePasscode:
            title = "Change the connection passcode?"; button = "Change passcode"
            effect = "Sharing will turn off. Devices will need the new passcode when you turn it on again."
        case .changeFolder:
            title = "Change the shared folder?"; button = "Change folder"
            effect = "Sharing will turn off. Turn it on again to share the new folder."
        case .disableAway:
            title = "Turn off Away access?"; button = "Turn off Away access"
            effect = "Devices outside your local network will lose their connection. Local sharing stays on."
        }
        var parts = [effect]
        if connected && self != .disableAway { parts.append("The connected device will disconnect. Desktop viewing and file transfers will stop.") }
        if runningTerminals > 0 {
            let noun = runningTerminals == 1 ? "terminal session" : "terminal sessions"
            parts.append("\(runningTerminals) \(noun) will keep running on this Mac. Reconnect to resume them.")
        }
        return HostSharingPrompt(title: title, message: parts.joined(separator: "\n\n"), button: button)
    }

    @MainActor static func show(_ prompt: HostSharingPrompt) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = prompt.title
        alert.informativeText = prompt.message
        alert.addButton(withTitle: prompt.button)
        alert.addButton(withTitle: "Cancel")
        alert.buttons[0].keyEquivalent = ""
        alert.buttons[1].keyEquivalent = "\r"
        return alert.runModal() == .alertFirstButtonReturn
    }
}
