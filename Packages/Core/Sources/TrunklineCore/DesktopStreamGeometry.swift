import Foundation

public struct DesktopDisplay: Codable, Equatable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public static let fallback = DesktopDisplay(width: 16, height: 9)
}

public enum DesktopStreamGeometry {
    public struct Size: Equatable, Sendable {
        public let width: Int
        public let height: Int

        public init(width: Int, height: Int) {
            self.width = width
            self.height = height
        }
    }

    public static func size(maximumWidth: Int, displayWidth: Int, displayHeight: Int) -> Size {
        guard maximumWidth > 1, displayWidth > 0, displayHeight > 0 else {
            return Size(width: maximumWidth, height: maximumWidth * 9 / 16)
        }
        let width = maximumWidth - maximumWidth % 2
        let scaledHeight = Int((Double(width) * Double(displayHeight) / Double(displayWidth)).rounded())
        let height = max(2, scaledHeight - scaledHeight % 2)
        return Size(width: width, height: height)
    }
}
