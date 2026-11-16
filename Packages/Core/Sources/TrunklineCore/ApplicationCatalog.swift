import Foundation

public struct MacInstalledApplication: Codable, Equatable, Identifiable, Sendable {
    public var id: String { bundleID }
    public let name: String
    public let bundleID: String
    public init(name: String, bundleID: String) { self.name = name; self.bundleID = bundleID }
}

public enum ApplicationCatalog {
    /// Call off the main actor. App packages are leaves, so their bundled helpers
    /// cannot appear as separate user applications.
    public static func discover(in roots: [URL]) -> [MacInstalledApplication] {
        var applications: [String: MacInstalledApplication] = [:]
        let manager = FileManager.default
        for root in roots {
            guard let enumerator = manager.enumerator(at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in enumerator {
                guard !Task.isCancelled else { return [] }
                guard url.pathExtension.lowercased() == "app" else { continue }
                enumerator.skipDescendants()
                let plist = url.appendingPathComponent("Contents/Info.plist")
                guard let data = try? Data(contentsOf: plist),
                      let info = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
                      info["CFBundlePackageType"] as? String == "APPL",
                      let identifier = info["CFBundleIdentifier"] as? String,
                      (try? MacControlAction.launchApp(identifier).validate()) != nil else { continue }
                let name = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                if applications[identifier] == nil {
                    applications[identifier] = MacInstalledApplication(name: String(name.prefix(240)), bundleID: identifier)
                }
            }
        }
        return applications.values.sorted {
            let comparison = $0.name.localizedStandardCompare($1.name)
            return comparison == .orderedSame ? $0.bundleID < $1.bundleID : comparison == .orderedAscending
        }
    }
}
