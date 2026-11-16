import Foundation

/// Owns one listener attempt across asynchronous identity creation and callbacks.
public struct AccessStartup: Sendable {
    public private(set) var isStarting = false
    public private(set) var isRunning = false
    private var token: UUID?
    public init() {}

    public mutating func begin() -> UUID? {
        guard token == nil else { return nil }
        let value = UUID()
        token = value
        isStarting = true
        return value
    }

    public func accepts(_ value: UUID) -> Bool { token == value }

    @discardableResult public mutating func ready(_ value: UUID) -> Bool {
        guard accepts(value) else { return false }
        isStarting = false
        isRunning = true
        return true
    }

    @discardableResult public mutating func failed(_ value: UUID) -> Bool {
        guard accepts(value) else { return false }
        stop()
        return true
    }

    @discardableResult public mutating func timedOut(_ value: UUID) -> Bool {
        guard isStarting else { return false }
        return failed(value)
    }

    public mutating func stop() {
        token = nil
        isStarting = false
        isRunning = false
    }
}
