import ApplicationServices
import CoreGraphics
#if canImport(TrunklineCore)
import TrunklineCore
#endif

/// Permission prompts belong to explicit setup actions, never automatic login startup.
enum HostPermissionRequester {
    static func request(_ permission: HostPermission) {
        switch permission {
        case .screenCapture:
            _ = CGRequestScreenCaptureAccess()
        case .accessibility:
            let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
        }
    }
}
