#if os(macOS)
import XCTest
import Darwin
@testable import TrunklineCore

final class ProcessShutdownTests: XCTestCase {
    // Catches leaving a desktop server alive after the companion quits.
    @MainActor
    func testStopsNormalProcessBeforeReturning() async throws {
        let child = Process(); child.executableURL = URL(fileURLWithPath: "/bin/sleep"); child.arguments = ["30"]
        try child.run(); defer { if child.isRunning { kill(child.processIdentifier, SIGKILL) } }
        await ProcessShutdown.finish([child], gracePeriod: .milliseconds(100))
        XCTAssertFalse(child.isRunning)
    }
    // Catches trusting SIGTERM even when a helper is hung or ignores it.
    @MainActor
    func testKillsUnresponsiveProcessAndReapsItWithinDeadline() async throws {
        let child = Process(); let ready = Pipe()
        child.executableURL = URL(fileURLWithPath: "/bin/sh")
        child.arguments = ["-c", "trap '' TERM; echo ready; exec /bin/sleep 30"]
        child.standardOutput = ready
        try child.run(); defer { if child.isRunning { kill(child.processIdentifier, SIGKILL) } }
        XCTAssertTrue(String(decoding: ready.fileHandleForReading.availableData, as: UTF8.self).contains("ready"))
        let start = ContinuousClock.now
        await ProcessShutdown.finish([child], gracePeriod: .milliseconds(50))
        XCTAssertFalse(child.isRunning)
        if !child.isRunning { XCTAssertEqual(child.terminationStatus, SIGKILL) }
        XCTAssertLessThan(start.duration(to: .now), .seconds(2))
    }
}
#endif
