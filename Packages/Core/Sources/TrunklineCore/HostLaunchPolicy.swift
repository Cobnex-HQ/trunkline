import Foundation

public enum HostLaunchPolicy {
    public static func shouldStartAccess(hasPasscode: Bool) -> Bool {
        hasPasscode
    }
}
