import Foundation
public enum TerminalKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case shell, claude, codex, opencode
    public var id: String { rawValue }
    public var title: String {
        switch self { case .shell: "Terminal"; case .claude: "Claude Code"; case .codex: "Codex"; case .opencode: "OpenCode" }
    }
    public var launchCommand: String? { self == .shell ? nil : rawValue }
}
public struct TerminalSessionInfo: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let kind: TerminalKind
    public let isRunning: Bool
    /// Missing on older hosts. Running remains true until process cleanup finishes.
    public let isStopping: Bool?
    public var statusTitle: String { !isRunning ? "Ended" : isStopping == true ? "Ending…" : "Running" }
    public init(id: UUID, title: String, kind: TerminalKind, isRunning: Bool, isStopping: Bool? = nil) {
        self.id = id; self.title = title; self.kind = kind; self.isRunning = isRunning; self.isStopping = isStopping
    }
}
public enum TerminalLimits {
    public static func validInput(_ data: Data) -> Bool { data.count <= 16384 }
    public static func validSize(columns: Int, rows: Int) -> Bool { (2...500).contains(columns) && (2...250).contains(rows) }
}
