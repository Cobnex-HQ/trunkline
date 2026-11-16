import Foundation

public enum UnicodeInput {
    /// CoreGraphics Unicode events have a small payload limit. Preserve surrogate pairs,
    /// including inside graphemes longer than a single event's capacity.
    public static func chunks(_ text: String) -> [[UInt16]] {
        let units = Array(text.utf16)
        var result: [[UInt16]] = [], offset = 0
        while offset < units.count {
            var end = min(offset + 20, units.count)
            if end < units.count && (0xd800...0xdbff).contains(units[end - 1]) { end -= 1 }
            result.append(Array(units[offset..<end])); offset = end
        }
        return result
    }
}
public enum ShareDirectory {
    public static func resolve(_ path: String, root: URL) throws -> URL {
        guard !path.hasPrefix("/"), !path.contains("\0"), path.utf8.count < 4096 else { throw ShareError.outsideRoot }
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        var target = root
        // Resolve every existing prefix. Foundation can leave an intermediate symlink
        // unresolved when the final leaf does not exist (the normal upload case).
        for component in path.split(separator: "/") {
            guard component != ".." else { throw ShareError.outsideRoot }
            target = target.appendingPathComponent(String(component)).standardizedFileURL.resolvingSymlinksInPath()
            guard target.path == root.path || target.path.hasPrefix(root.path + "/") else { throw ShareError.outsideRoot }
        }
        return target
    }
    public enum ShareError: LocalizedError {
        case outsideRoot
        public var errorDescription: String? { "File access is limited to the folder shared on your Mac." }
    }
}
public struct RemoteFile: Codable, Equatable, Identifiable, Sendable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let isDirectory: Bool
    public let size: Int64
    public init(name: String, path: String, isDirectory: Bool, size: Int64) {
        self.name = name; self.path = path; self.isDirectory = isDirectory; self.size = size
    }
}
