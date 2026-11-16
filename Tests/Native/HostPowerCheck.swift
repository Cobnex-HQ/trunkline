import Foundation
import Carbon

/// Exercises production dispatch while intercepting only the OS power-event boundary.
/// No restart, shutdown, logout, or consent prompt is sent to this Mac.
@main struct HostPowerCheck {
    static func main() async throws {
        var events: [AEEventID] = []
        var prompted = false
        let power = HostPower(send: { event, options in
            precondition(event.eventClass == 0x61657674, "Power events must use the core Apple-event class")
            let target = event.attributeDescriptor(forKeyword: AEKeyword(keyAddressAttr))!
            precondition(target.descriptorType == 0x70736e20, "Target must use a process serial number")
            let serial = target.data.withUnsafeBytes { $0.loadUnaligned(as: ProcessSerialNumber.self) }
            precondition(serial.highLongOfPSN == 0 && serial.lowLongOfPSN == 1, "Target must be loginwindow, never an arbitrary app")
            precondition(options.contains(.noReply), "Power transition must not block waiting for a reply after shutdown")
            precondition(options.rawValue & UInt(kAEDoNotPromptForUserConsent) != 0, "Remote requests cannot trigger permission prompts")
            precondition(options.contains(.canInteract), "Normal save dialogs must remain available")
            events.append(event.eventID)
        }, permission: { _, _, allowPrompt in prompted = prompted || allowPrompt; return noErr })
        let controls = MacControls(power: power)
        for action in MacPowerAction.allCases {
            let request = MacControlRequest(action: .power(action))
            let first = await controls.perform(request)
            let replay = await controls.perform(request)
            precondition(first.error == nil && replay == first, "Accepted requests should be acknowledged consistently")
        }
        precondition(events == [0x72657374, 0x73687574, 0x726c676f], "Each requested action must dispatch exactly once with the correct event")
        precondition(!prompted, "Remote power requests must check permission without prompting")

        var rejectedWasSent = false
        let rejected = HostPower(send: { _, _ in rejectedWasSent = true }, permission: { _, _, allowPrompt in
            precondition(!allowPrompt); return OSStatus(errAEEventWouldRequireUserConsent)
        })
        let capability = rejected.capability()
        precondition(capability.actions.isEmpty && capability.authorizationRequired)
        let unavailable = await MacControls(power: rejected).perform(MacControlRequest(action: .power(.restart)))
        precondition(unavailable.error != nil && !rejectedWasSent, "Denied actions must return actionable errors without dispatch")

        let revoked = HostPower(send: { _, _ in throw NSError(domain: NSOSStatusErrorDomain, code: -1743) },
                                permission: { _, _, _ in noErr })
        let deniedAtSend = await MacControls(power: revoked).perform(MacControlRequest(action: .power(.logOut)))
        precondition(deniedAtSend.error != nil, "Permission revoked after preflight must not be reported as success")
        print("PASS: loginwindow targets, exact-once power dispatch, noninteractive consent checks, and permission failure recovery; no OS power action executed")
    }
}
