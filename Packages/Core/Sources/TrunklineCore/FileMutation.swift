import Foundation

public enum FileMutation: Codable, Equatable, Sendable {
    case createFolder(parent: String, name: String)
    case rename(path: String, name: String)
    case trash(path: String)
    public struct Plan: Sendable {
        public let source: URL?
        public let destination: URL?
    }
    public func resolve(root: URL) throws -> Plan {
        func child(_ name: String, parent: String) throws -> URL {
            guard !name.isEmpty, name.utf8.count <= 255, name != ".", name != "..",
                  !name.contains("/"), !name.contains("\\"), !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw ShareDirectory.ShareError.outsideRoot }
            return try ShareDirectory.resolve(parent.isEmpty ? name : parent + "/" + name, root: root)
        }
        func existing(_ path: String) throws -> URL {
            let url = try ShareDirectory.resolve(path, root: root)
            guard url != root.standardizedFileURL.resolvingSymlinksInPath() else { throw ShareDirectory.ShareError.outsideRoot }
            return url
        }
        switch self {
        case let .createFolder(parent, name): return Plan(source: nil, destination: try child(name, parent: parent))
        case let .rename(path, name):
            return Plan(source: try existing(path), destination: try child(name, parent: path.split(separator: "/").dropLast().joined(separator: "/")))
        case let .trash(path): return Plan(source: try existing(path), destination: nil)
        }
    }
}
