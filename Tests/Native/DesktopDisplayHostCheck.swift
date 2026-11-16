import Foundation

actor SelectionRecorder {
    var identities: [String] = []
    func select(_ id: String) { identities.append(id) }
}
@main struct DesktopDisplayHostCheck {
    static func main() async {
        let controls = MacControls()
        let recorder = SelectionRecorder()
        let request = MacControlRequest(action: .desktopDisplay("74"))
        let first = await controls.perform(request, selectDesktopDisplay: { await recorder.select($0) })
        let duplicate = await controls.perform(request, selectDesktopDisplay: { await recorder.select($0) })
        let identities = await recorder.identities
        guard first.error == nil, duplicate == first, identities == ["74"] else { fatalError("Selection must execute once per command identity") }
        let invalid = await controls.perform(MacControlRequest(action: .desktopDisplay("0")), selectDesktopDisplay: { await recorder.select($0) })
        guard invalid.error != nil, await recorder.identities == ["74"] else { fatalError("Invalid identity reached the engine") }
        let unsupported = await controls.perform(MacControlRequest(action: .desktopDisplay("74")))
        guard unsupported.error != nil else { fatalError("Missing engine selector reported success") }
        let rejected = await controls.perform(MacControlRequest(action: .desktopDisplay("74")), selectDesktopDisplay: { _ in throw MacControlError.missingDisplay })
        guard rejected.error == MacControlError.missingDisplay.localizedDescription else { fatalError("Engine rejection was discarded") }
        print("PASS: host display dispatch, validation, duplicate command suppression and failure reporting")
    }
}
