#if os(macOS)
import Foundation
import Darwin

public enum ProcessShutdown {
    /// Stop app-owned children without blocking the UI, escalating if SIGTERM is ignored.
    @MainActor public static func finish(_ children: [Process], gracePeriod: Duration = .seconds(3)) async {
        for child in children where child.isRunning { child.terminate() }
        let deadline = ContinuousClock.now.advanced(by: gracePeriod)
        while ContinuousClock.now < deadline, children.contains(where: { $0.isRunning }), !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(20))
        }
        for child in children where child.isRunning { kill(child.processIdentifier, SIGKILL) }
        // Foundation must observe the exit before a replacement binds the same ports.
        let reapedDeadline = ContinuousClock.now.advanced(by: .seconds(1))
        while ContinuousClock.now < reapedDeadline, children.contains(where: { $0.isRunning }) {
            await Task.detached { try? await Task.sleep(for: .milliseconds(20)) }.value
        }
    }
}
#endif
