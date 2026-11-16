import Foundation

/// Uses the established streaming keyboard channel; no new host protocol is needed.
enum DesktopWorkspaceAction: String, CaseIterable, Identifiable {
    case missionControl, appWindows, previousSpace, nextSpace
    var id: Self { self }
    var title: String {
        switch self {
        case .missionControl: "Mission Control"
        case .appWindows: "App windows"
        case .previousSpace: "Previous Space"
        case .nextSpace: "Next Space"
        }
    }
    var symbol: String {
        switch self {
        case .missionControl: "rectangle.3.group"
        case .appWindows: "macwindow.on.rectangle"
        case .previousSpace: "arrow.left.to.line"
        case .nextSpace: "arrow.right.to.line"
        }
    }
    func perform(on engine: TrunklineStream) {
        let key: UInt16
        switch self {
        case .missionControl: key = 0x26 // Control–Up
        case .appWindows: key = 0x28     // Control–Down
        case .previousSpace: key = 0x25 // Control–Left
        case .nextSpace: key = 0x27     // Control–Right
        }
        engine.sendKey(key, modifiers: 0x02)
    }
}
