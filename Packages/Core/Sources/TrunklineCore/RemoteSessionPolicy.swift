import Foundation

public enum RemoteSessionPolicy {
    /// Remote control needs the capture display to stay available for the entire session.
    public static let awakeMode: AwakeMode = .systemAndDisplay
}

public enum TerminalSessionLabel {
    public static func title(kind: TerminalKind, ordinal: Int) -> String {
        "\(kind.title) \(max(1, ordinal))"
    }
}
