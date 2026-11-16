import ApplicationServices
import CoreGraphics
import Foundation

// Shadow only the OS request boundary. No privacy prompt or setting is touched.
private var screenRequests = 0
private var accessibilityRequests = 0
private var accessibilityPrompt = false
func CGRequestScreenCaptureAccess() -> Bool { screenRequests += 1; return false }
func AXIsProcessTrustedWithOptions(_ options: CFDictionary?) -> Bool {
    accessibilityRequests += 1
    let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    accessibilityPrompt = (options as? [String: Bool])?[key] == true
    return false
}
@main struct HostPermissionRequestCheck {
    static func main() {
        HostPermissionRequester.request(.screenCapture)
        precondition(screenRequests == 1 && accessibilityRequests == 0, "Screen setup must not request unrelated permissions")
        HostPermissionRequester.request(.accessibility)
        precondition(screenRequests == 1 && accessibilityRequests == 1 && accessibilityPrompt,
                     "Input setup must request only Accessibility on explicit action")
        print("PASS: explicit screen/input setup requests only the chosen permission; no OS prompt opened")
    }
}
