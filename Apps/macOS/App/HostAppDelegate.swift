#if canImport(TrunklineCore)
import TrunklineCore
#endif
import AppKit

@MainActor
final class HostAppDelegate: NSObject, NSApplicationDelegate {
    let model = HostModel()
    let client = MacClientModel()
    private var launchTask: Task<Void, Never>?
    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        #endif
        guard launchTask == nil else { return }
        launchTask = Task { await model.startOnLaunchIfReady() }
    }
    private var quitting = false
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if quitting { return .terminateLater }
        if model.terminals.runningCount > 0 {
            let alert = NSAlert()
            alert.messageText = "End terminal sessions and quit?"
            alert.informativeText = "Quitting stops all terminal sessions created in Trunkline. Disconnect the phone instead to keep them running."
            alert.addButton(withTitle: "End sessions and quit"); alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        }
        guard model.keepAwake.prepareToQuit() else { return .terminateCancel }
        launchTask?.cancel()
        model.terminals.closeAll()
        model.stop()
        quitting = true
        Task { @MainActor in
            await client.shutdown()
            guard await model.terminals.shutdown() else {
                model.error = "Some terminal processes have not stopped. Trunkline will stay open so you can retry."
                quitting = false
                NSApplication.shared.reply(toApplicationShouldTerminate: false)
                return
            }
            await model.sunshine.shutdown()
            NSApplication.shared.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

