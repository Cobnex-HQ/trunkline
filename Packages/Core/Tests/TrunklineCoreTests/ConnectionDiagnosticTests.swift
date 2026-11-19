import XCTest
import Network
@testable import TrunklineCore

final class ConnectionDiagnosticTests: XCTestCase {
    func testAttemptResetsPreviousFailureAndKeepsOnlyBoundedSafeEvidence() {
        var state = ConnectionDiagnostic()
        state.begin(route: .away)
        state.advance(.secureConnection)
        state.fail(.directRouteUnavailable)
        XCTAssertTrue(state.report.contains("Direct route unavailable"))
        XCTAssertFalse(state.explanation.contains("Mac is offline"), "A route failure cannot prove the Mac is offline")
        state.begin(route: .local)
        XCTAssertNil(state.failure)
        state.advance(.authentication)
        state.advance(.connected)
        XCTAssertEqual(state.stage, .connected)
        XCTAssertFalse(state.report.contains("Direct route unavailable"))
    }
    func testNetworkErrorsUseCodesInsteadOfLocalizedText() {
        XCTAssertEqual(ConnectionFailureCause.network(.posix(.ECONNREFUSED)), .notListening)
        XCTAssertEqual(ConnectionFailureCause.network(.posix(.ENETDOWN)), .networkUnavailable)
        XCTAssertEqual(ConnectionFailureCause.network(.posix(.EACCES)), .networkDenied)
        XCTAssertEqual(ConnectionFailureCause.network(.tls(-9807)), .identityUnverified)
    }
    func testNewAndOldAdmissionFailuresRemainCompatible() throws {
        enum OldMessage: Codable { case failure(String) }
        let old = try PacketCodec.decode(Data([0]) + JSONEncoder().encode(OldMessage.failure("Old host")))
        XCTAssertEqual(old, .failure("Old host", cause: nil))
        let packet = try PacketCodec.encode(.failure("Mac in use", cause: .hostBusy))
        let decoded = try JSONDecoder().decode(OldMessage.self, from: packet.dropFirst(5))
        guard case let .failure(message) = decoded else { return XCTFail("Older clients must still receive the explanation") }
        XCTAssertEqual(message, "Mac in use")
    }
}
