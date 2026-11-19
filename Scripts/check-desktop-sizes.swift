// Read-only feasibility probe. Does not switch a display mode or create a display.
import CoreGraphics
import Foundation

let arguments = CommandLine.arguments.dropFirst().compactMap(Double.init)
guard CommandLine.arguments.count == 3, arguments.count == 2, arguments.allSatisfy({ $0.isFinite && $0 > 0 }) else {
    fputs("Usage: swift Scripts/check-desktop-sizes.swift DEVICE_WIDTH DEVICE_HEIGHT\n", stderr)
    exit(2)
}
let ratio = arguments[0] / arguments[1]
var count: UInt32 = 0
guard CGGetActiveDisplayList(0, nil, &count) == .success else { exit(1) }
var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
guard CGGetActiveDisplayList(count, &displays, &count) == .success else { exit(1) }
print("Target aspect ratio: \(ratio). Read-only check, no display changes.")
for display in displays.prefix(Int(count)) {
    let modes = CGDisplayCopyAllDisplayModes(display, nil) as? [CGDisplayMode] ?? []
    let matches = modes.filter { $0.height > 0 && abs(Double($0.width) / Double($0.height) / ratio - 1) < 0.005 }
    print("Display \(display): \(modes.count) advertised modes, \(matches.count) within 0.5% of the target ratio")
    for mode in matches {
        print("  \(mode.width) × \(mode.height) points, \(mode.pixelWidth) × \(mode.pixelHeight) pixels")
    }
}
print("A matching physical mode is not an independent virtual desktop. Capture resizing alone does not resize the Mac workspace.")
