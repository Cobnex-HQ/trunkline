import XCTest
@testable import TrunklineCore

final class TerminalSessionStateTests: XCTestCase {
    func testOlderHostSessionListRemainsDecodable() throws {
        let data = Data("""
        {"id":"00000000-0000-4000-8000-000000000001","title":"Build","kind":"shell","isRunning":true}
        """.utf8)
        let session = try JSONDecoder().decode(TerminalSessionInfo.self, from: data)
        XCTAssertTrue(session.isRunning)
        XCTAssertNil(session.isStopping)
        XCTAssertEqual(session.statusTitle, "Running")
    }
    func testStoppingRemainsLiveAcrossProtocolRoundTripUntilConfirmedExit() throws {
        let session = TerminalSessionInfo(id: UUID(), title: "Build", kind: .shell, isRunning: true, isStopping: true)
        var parser = PacketParser()
        let messages = try parser.append(PacketCodec.encode(.terminals([session])))
        guard case let .terminals(sessions) = messages.first else { return XCTFail("Missing session list") }
        XCTAssertEqual(sessions, [session])
        XCTAssertTrue(sessions[0].isRunning)
        XCTAssertEqual(sessions[0].statusTitle, "Ending…")
        let ended = TerminalSessionInfo(id: session.id, title: "Build", kind: .shell, isRunning: false, isStopping: true)
        XCTAssertEqual(ended.statusTitle, "Ended", "Confirmed exit takes precedence over stale pending metadata")
    }
}
