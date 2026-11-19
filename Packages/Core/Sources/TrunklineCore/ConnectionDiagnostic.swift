import Foundation
import Network

public enum ConnectionFailureCause: String, Codable, Sendable {
    case networkUnavailable, networkDenied, addressNotFound, notListening, unreachable
    case identityUnverified, authenticationRejected, authenticationTimeout, hostBusy, rateLimited
    case deviceApprovalRequired, deviceRevoked
    case directRouteUnavailable, clientBusy, interrupted, unknown
    public init(from decoder: Decoder) throws {
        self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }
    public static func network(_ error: NWError) -> Self {
        switch error {
        case .tls: return .identityUnverified
        case .dns: return .addressNotFound
        case let .posix(code):
            switch code {
            case .ENETDOWN, .ENETUNREACH: return .networkUnavailable
            case .EACCES, .EPERM: return .networkDenied
            case .ECONNREFUSED: return .notListening
            case .EHOSTUNREACH, .ETIMEDOUT: return .unreachable
            default: return .interrupted
            }
        default: return .unknown
        }
    }
    public var title: String {
        switch self {
        case .networkUnavailable: "Network unavailable"
        case .networkDenied: "Network access denied"
        case .addressNotFound: "Mac address not found"
        case .notListening: "Sharing service unavailable"
        case .unreachable: "Mac not reachable"
        case .identityUnverified: "Secure connection not verified"
        case .authenticationRejected: "Passcode rejected"
        case .authenticationTimeout: "Authentication timed out"
        case .deviceApprovalRequired: "Device approval needed"
        case .deviceRevoked: "Device access revoked"
        case .hostBusy: "Mac already in use"
        case .rateLimited: "Too many attempts"
        case .clientBusy: "Away access already open"
        case .directRouteUnavailable: "Direct route unavailable"
        case .interrupted: "Connection interrupted"
        case .unknown: "Connection failed"
        }
    }
    public var guidance: String {
        switch self {
        case .networkUnavailable: "Connect this device to Wi-Fi or cellular data, then retry."
        case .networkDenied: "Check Trunkline’s Local Network permission and network restrictions on this device."
        case .addressNotFound: "The saved address could not be resolved. Check the network or pair again locally."
        case .notListening: "The address refused the connection. Check that My Mac → Sharing is on and the saved address is current."
        case .unreachable: "No connection was established. The Mac may be asleep, sharing may be off, or the network may block access."
        case .identityUnverified: "The secure connection failed verification. Check the Mac’s identity and pair again on a trusted network."
        case .authenticationRejected: "The Mac responded but rejected the passcode. Use the connection passcode shown in its sharing settings."
        case .authenticationTimeout: "The secure connection opened, but the Mac did not complete authentication. Check its sharing status and retry."
        case .deviceApprovalRequired: "On the Mac, open My Mac → Sharing → Devices and approve this device, then reconnect. Older clients must be updated first."
        case .deviceRevoked: "This Mac revoked the device’s access. Its owner must approve the device again in Sharing → Devices."
        case .hostBusy: "Disconnect the current controlling device before connecting here."
        case .rateLimited: "The Mac temporarily blocked further attempts. Wait one minute, then use the correct connection passcode."
        case .clientBusy: "Close the Away connection in the other window before opening another."
        case .directRouteUnavailable: "A direct route was not established. Check that the Mac is awake, online and sharing with Away enabled. These networks may block a direct connection."
        case .interrupted: "The connection stopped responding. Check both networks and reconnect."
        case .unknown: "The cause could not be confirmed. Check the error shown by the app and the Mac’s sharing status."
        }
    }
}

/// Stores only structured connection evidence. No addresses, tickets, credentials
/// or raw engine logs enter the shareable report.
public struct ConnectionDiagnostic: Equatable, Sendable {
    public enum Route: String, Sendable { case local = "Local Wi-Fi", away = "Away · direct" }
    public enum Stage: String, Sendable {
        case idle = "Not started", discovery = "Finding a route", secureConnection = "Opening secure connection"
        case authentication = "Authenticating", connected = "Connected"
    }
    public private(set) var route: Route = .local
    public private(set) var stage: Stage = .idle
    public private(set) var failure: ConnectionFailureCause?
    public init() {}
    public mutating func begin(route: Route) { self.route = route; stage = .discovery; failure = nil }
    public mutating func advance(_ stage: Stage) { self.stage = stage }
    public mutating func fail(_ cause: ConnectionFailureCause) { failure = cause }
    public var explanation: String { failure?.guidance ?? "No failure recorded for this attempt." }
    public var report: String {
        "Trunkline connection report\nRoute: \(route.rawValue)\nLast stage: \(stage.rawValue)\nLast result: \(failure?.title ?? stage.rawValue)\n\(explanation)"
    }
}
