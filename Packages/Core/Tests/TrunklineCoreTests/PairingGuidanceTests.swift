import XCTest
@testable import TrunklineCore

final class PairingGuidanceTests: XCTestCase {
    func testSavedPasscodeDirectsTheMacOwnerToStartAccessBeforeScanning() {
        let guidance = PairingGuidance.nextStep(hasPasscode: true, isRunning: false)

        XCTAssertEqual(guidance.title, "Show your pairing QR code")
        XCTAssertEqual(guidance.actionTitle, "Start access & show QR code")
        XCTAssertEqual(guidance.detail, "Start access to create a secure pairing link, then scan the QR code with your iPhone or iPad.")
    }

    func testRunningAccessDirectsTheMacOwnerToScanTheShownCode() {
        let guidance = PairingGuidance.nextStep(hasPasscode: true, isRunning: true)

        XCTAssertEqual(guidance.title, "Scan with your iPhone or iPad")
        XCTAssertEqual(guidance.actionTitle, "")
    }
}
