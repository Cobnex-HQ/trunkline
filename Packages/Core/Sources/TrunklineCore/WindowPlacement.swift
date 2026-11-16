import Foundation

/// Window/display rectangles use Accessibility's top-left, logical-point coordinates.
public enum WindowPlacement {
    public static func move(window: CGRect, from source: CGRect, to destination: CGRect) throws -> CGRect {
        for rect in [window, source, destination] {
            guard !rect.isNull, !rect.isInfinite,
                  [rect.origin.x, rect.origin.y, rect.width, rect.height].allSatisfy(\.isFinite),
                  rect.width > 0, rect.height > 0 else { throw MacControlError.invalid }
        }
        let width = min(window.width, destination.width), height = min(window.height, destination.height)
        let relativeX = min(1, max(0, (window.midX - source.minX) / source.width))
        let relativeY = min(1, max(0, (window.midY - source.minY) / source.height))
        let x = destination.minX + relativeX * destination.width - width / 2
        let y = destination.minY + relativeY * destination.height - height / 2
        return CGRect(x: min(max(x, destination.minX), destination.maxX - width),
                      y: min(max(y, destination.minY), destination.maxY - height),
                      width: width, height: height)
    }
}
