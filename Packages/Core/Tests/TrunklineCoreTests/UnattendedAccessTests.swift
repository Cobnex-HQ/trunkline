import XCTest
@testable import TrunklineCore
final class UnattendedAccessTests: XCTestCase {
    func testDesktopApprovalTargetsOnlyItsOwnPendingRequest() throws {
        let request = try DesktopPairRequest(pin: "1234", token: "D97FAEA6-4238-4C63-AC36-D2F5DDF1BCEF") // gitleaks:allow -- synthetic UUID fixture, no real pairing
        XCTAssertNil(try request.matchingID(in: ["other": "Some other phone"]))
        XCTAssertEqual(try request.matchingID(in: ["other": "Some other phone", "ours": "Trunkline-D97FAEA6-4238-4C63-AC36-D2F5DDF1BCEF"]), "ours")
        XCTAssertThrowsError(try request.matchingID(in: ["one": request.clientName, "two": request.clientName]))
        XCTAssertThrowsError(try DesktopPairRequest(pin: "１２３４", token: request.token))
        XCTAssertThrowsError(try DesktopPairRequest(pin: "1234", token: "guessable"))
        let message = WireMessage.pairDesktop(request)
        XCTAssertTrue(CompanionTransportPolicy.allows(message))
        XCTAssertEqual(try PacketParser().decodedForTest(PacketCodec.encode(message)), message)
    }
    func testPreparedAuthenticationWorksWithoutReadingCredentialsAgain() throws {
        var saved = try JSONEncoder().encode(PasscodeRecord(passcode: "valid-passcode"))
        let authentication = try PreparedHostAuthentication(record: saved)
        saved.removeAll()
        XCTAssertTrue(authentication.verify("valid-passcode"))
        XCTAssertFalse(authentication.verify("wrong-passcode"))
        XCTAssertThrowsError(try PreparedHostAuthentication(record: Data("corrupt".utf8)))
    }
}
private extension PacketParser {
    func decodedForTest(_ data: Data) throws -> WireMessage? { var parser = self; return try parser.append(data).first }
}
