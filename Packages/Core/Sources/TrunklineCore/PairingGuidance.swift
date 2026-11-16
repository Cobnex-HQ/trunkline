import Foundation

public struct PairingGuidance: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let actionTitle: String

    public static func nextStep(hasPasscode: Bool, isRunning: Bool) -> Self {
        if isRunning {
            return Self(
                title: "Scan with your iPhone or iPad",
                detail: "Open Trunkline, tap Scan QR code, then enter your connection passcode.",
                actionTitle: ""
            )
        }

        if hasPasscode {
            return Self(
                title: "Show your pairing QR code",
                detail: "Start access to create a secure pairing link, then scan the QR code with your iPhone or iPad.",
                actionTitle: "Start access & show QR code"
            )
        }

        return Self(
            title: "Secure this Mac",
            detail: "Choose a connection passcode. You’ll enter it once on your iPhone or iPad.",
            actionTitle: ""
        )
    }
}
