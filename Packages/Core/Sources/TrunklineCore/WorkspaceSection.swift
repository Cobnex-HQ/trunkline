import Foundation

public enum WorkspaceSection: String, CaseIterable, Identifiable, Sendable {
    case desktop
    case terminal
    case controls
    case files

    public var id: Self { self }

    public var title: String {
        switch self {
        case .desktop: "Desktop"
        case .terminal: "Terminal"
        case .controls: "Controls"
        case .files: "Files"
        }
    }

    public var systemImage: String {
        switch self {
        case .desktop: "display"
        case .terminal: "terminal"
        case .controls: "slider.horizontal.3"
        case .files: "folder"
        }
    }

    public var summary: String {
        switch self {
        case .desktop: "Control your Mac"
        case .terminal: "Keep work running"
        case .controls: "Apps and system"
        case .files: "Browse and transfer"
        }
    }
}
