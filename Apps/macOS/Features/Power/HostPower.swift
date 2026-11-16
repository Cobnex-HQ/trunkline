#if canImport(TrunklineCore)
import TrunklineCore
#endif
import Foundation
import CoreServices
import Carbon

/// Login-window requests, with noninteractive permission checks for remote use.
/// The sender boundary is injectable so regression checks never power off the test Mac.
struct HostPower {
    typealias Sender = (NSAppleEventDescriptor, NSAppleEventDescriptor.SendOptions) throws -> Void
    typealias Permission = (NSAppleEventDescriptor, AEEventID, Bool) -> OSStatus
    private let send: Sender
    private let permission: Permission
    init(send: @escaping Sender = HostPower.sendEvent,
         permission: @escaping Permission = HostPower.checkPermission) {
        self.send = send; self.permission = permission
    }
    func capability(allowPrompt: Bool = false) -> MacPowerCapability {
        guard let target = try? Self.target() else { return .init(actions: [], authorizationRequired: false) }
        var actions: [String] = []; var needsAuthorization = false
        for action in MacPowerAction.allCases {
            let status = permission(target, Self.eventID(action), allowPrompt)
            if status == noErr { actions.append(action.rawValue) }
            else if status == errAEEventNotPermitted || status == errAEEventWouldRequireUserConsent { needsAuthorization = true }
        }
        return .init(actions: actions, authorizationRequired: needsAuthorization)
    }
    func perform(_ action: MacPowerAction) throws {
        let target = try Self.target()
        let status = permission(target, Self.eventID(action), false)
        guard status == noErr else { throw PowerError(status: status) }
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass), eventID: Self.eventID(action),
            targetDescriptor: target, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        // Permission can be revoked between preflight and dispatch. Never produce
        // a new consent prompt on an unattended Mac. Normal app save dialogs remain allowed.
        let options = NSAppleEventDescriptor.SendOptions(rawValue: UInt(kAENoReply | kAECanInteract | kAEDoNotPromptForUserConsent))
        do { try send(event, options) }
        catch { throw PowerError(status: OSStatus((error as NSError).code)) }
    }
    private static func eventID(_ action: MacPowerAction) -> AEEventID {
        switch action { case .restart: AEEventID(kAERestart); case .shutDown: AEEventID(kAEShutDown); case .logOut: AEEventID(kAEReallyLogOut) }
    }
    private static func target() throws -> NSAppleEventDescriptor {
        var serial = ProcessSerialNumber(highLongOfPSN: 0, lowLongOfPSN: UInt32(kSystemProcess))
        let bytes = withUnsafeBytes(of: &serial) { Data($0) }
        guard let target = NSAppleEventDescriptor(descriptorType: DescType(typeProcessSerialNumber), data: bytes) else {
            throw PowerError(status: OSStatus(paramErr))
        }
        return target
    }
    private static func checkPermission(_ target: NSAppleEventDescriptor, event: AEEventID, allowPrompt: Bool) -> OSStatus {
        AEDeterminePermissionToAutomateTarget(target.aeDesc, AEEventClass(kCoreEventClass), event, allowPrompt)
    }
    private static func sendEvent(_ event: NSAppleEventDescriptor, options: NSAppleEventDescriptor.SendOptions) throws {
        _ = try event.sendEvent(options: options, timeout: 5)
    }
    struct PowerError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            switch status {
            case OSStatus(errAEEventNotPermitted), OSStatus(errAEEventWouldRequireUserConsent):
                "Allow power controls in Trunkline’s Power settings on the Mac, then try again."
            case OSStatus(userCanceledErr): "The power request was cancelled on the Mac."
            default: "macOS couldn’t accept the power request (\(status)). Your Mac may still be running."
            }
        }
    }
}
