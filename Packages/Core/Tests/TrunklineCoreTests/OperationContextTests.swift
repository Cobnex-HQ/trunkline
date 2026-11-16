import XCTest
@testable import TrunklineCore

final class OperationContextTests: XCTestCase {
    private enum LegacyMessage: Codable { case operationError(String) }
    func testScopedErrorRetainsItsDestinationThroughTheWireCodec() throws {
        let data = Data(#"{"operationError":{"_0":"Session ended","context":{"domain":"terminal"}}}"#.utf8)
        let message = try JSONDecoder().decode(WireMessage.self, from: data)
        var parser = PacketParser()
        let decoded = try XCTUnwrap(parser.append(PacketCodec.encode(message)).first)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: [String: Any]])
        let context = try XCTUnwrap(object["operationError"]?["context"] as? [String: Any])
        XCTAssertEqual(context["domain"] as? String, "terminal")
    }
    func testOldClientStillReadsTheHumanMessageFromAScopedError() throws {
        let data = try JSONEncoder().encode(WireMessage.operationError("Session ended", context: .init(.terminal)))
        guard case let .operationError(message) = try JSONDecoder().decode(LegacyMessage.self, from: data) else { return XCTFail() }
        XCTAssertEqual(message, "Session ended")
    }
    func testNewClientReadsLegacyErrorWithoutContext() throws {
        let data = Data(#"{"operationError":{"_0":"Unavailable"}}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(WireMessage.self, from: data), .operationError("Unavailable"))
    }
    func testUnknownDomainDoesNotBreakConnectionDecoding() throws {
        let data = Data(#"{"operationError":{"_0":"Unavailable","context":{"domain":"future-feature"}}}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(WireMessage.self, from: data), .operationError("Unavailable", context: .init(.general)))
    }
    func testDesktopRequestIdentitySurvivesWireCodec() throws {
        let data = Data(#"{"operationError":{"_0":"Pairing rejected","context":{"domain":"desktop","requestID":"previous-attempt"}}}"#.utf8)
        let message = try JSONDecoder().decode(WireMessage.self, from: data)
        var parser = PacketParser()
        XCTAssertEqual(try parser.append(PacketCodec.encode(message)).first,
                       .operationError("Pairing rejected", context: .init(.desktop, requestID: "previous-attempt")))
    }
}
