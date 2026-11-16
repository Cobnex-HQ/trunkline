import XCTest
@testable import TrunklineCore

final class CompanionTransportTests: XCTestCase {
    // Allowing legacy media or desktop input would reintroduce the custom streaming path.
    func testCompanionRejectsLegacyDesktopTraffic() {
        let messages: [WireMessage] = [
            .startStream(profile: .responsive), .stopStream, .requestKeyframe,
            .setAudioEnabled(true), .audio(AudioPacket(samples: Data(repeating: 0, count: 4), frameCount: 1)),
            .video(VideoFrame(bytes: Data([1]), sps: Data([1]), pps: Data([1]), width: 1, height: 1)),
            .pointer(x: 0.5, y: 0.5, phase: .down), .scroll(dx: 0, dy: 1),
            .text("hello"), .key(code: 36, modifiers: 0)
        ]
        for message in messages { XCTAssertFalse(CompanionTransportPolicy.allows(message), "\(message)") }
    }
    func testCompanionPreservesAuthenticationTerminalAndFileTraffic() {
        let id = UUID()
        let messages: [WireMessage] = [.authenticate(passcode: "passcode"), .accepted(name: "Mac", display: .init(width: 3024, height: 1964)),
            .ping, .pong, .listTerminals, .terminalInput(id: id, bytes: Data([3])),
            .terminalOutput(id: id, bytes: Data([27,91,65]), reset: false),
            .resizeTerminal(id: id, columns: 80, rows: 24), .listFiles(path: ""),
            .requestClipboard, .setClipboard("hello"), .operationError("unavailable")]
        for message in messages { XCTAssertTrue(CompanionTransportPolicy.allows(message), "\(message)") }
    }
}
