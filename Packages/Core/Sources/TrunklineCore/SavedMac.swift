import Foundation

public struct SavedMac: Codable, Identifiable, Equatable {
    public let id: String
    public var name: String
    public var link: String
    public var away: Bool
    public static func credentialKey(_ fingerprint: String) -> String { "client-passcode.\(fingerprint)" }
}

/// Pairing identity and presentation only; passcodes and Away tickets remain in Keychain.
public struct SavedMacStore {
    public private(set) var macs: [SavedMac]
    public private(set) var selectedID: String?
    private let defaults: UserDefaults
    public init(defaults: UserDefaults) {
        self.defaults = defaults
        macs = defaults.data(forKey: "saved-macs.v1").flatMap { try? JSONDecoder().decode([SavedMac].self, from: $0) } ?? []
        selectedID = defaults.string(forKey: "selected-mac.v1")
        if macs.isEmpty, let link = defaults.string(forKey: "pairing-link"), let pairing = try? PairingDetails.parse(link) {
            save(pairing, away: defaults.bool(forKey: "use-away-access"))
        }
        if !macs.contains(where: { $0.id == selectedID }) { selectedID = macs.first?.id }
    }
    public mutating func refresh() {
        macs = defaults.data(forKey: "saved-macs.v1").flatMap { try? JSONDecoder().decode([SavedMac].self, from: $0) } ?? []
        selectedID = defaults.string(forKey: "selected-mac.v1")
    }
    public mutating func save(_ pairing: PairingDetails, name: String? = nil, away: Bool? = nil) {
        refresh()
        // Never persist the bearer ticket in UserDefaults.
        guard let local = try? PairingDetails(host: pairing.host, port: pairing.port, fingerprint: pairing.fingerprint) else { return }
        if let index = macs.firstIndex(where: { $0.id == pairing.fingerprint }) {
            macs[index].link = local.link
            if let name { macs[index].name = name }
            if let away { macs[index].away = away }
        } else {
            macs.append(SavedMac(id: pairing.fingerprint, name: name ?? pairing.host, link: local.link, away: away ?? false))
        }
        selectedID = pairing.fingerprint
        persist()
    }
    public mutating func select(_ id: String) {
        refresh()
        guard macs.contains(where: { $0.id == id }) else { return }
        selectedID = id; persist()
    }
    public mutating func remove(_ id: String) {
        refresh()
        macs.removeAll { $0.id == id }
        if selectedID == id { selectedID = macs.first?.id }
        persist()
    }
    private func persist() {
        defaults.set(try? JSONEncoder().encode(macs), forKey: "saved-macs.v1")
        defaults.set(selectedID, forKey: "selected-mac.v1")
    }
}
