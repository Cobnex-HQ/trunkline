import Foundation
import Security
#if canImport(TrunklineCore)
import TrunklineCore
#endif

struct HostIdentity {
    let identity: SecIdentity
    let fingerprint: String
    static func load() throws -> HostIdentity {
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Trunkline", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let archive = directory.appendingPathComponent("identity.p12")
        let password: String
        if let data = try SecretStore.readHostSecret("identity-password"), let saved = String(data: data, encoding: .utf8) { password = saved }
        else {
            password = UUID().uuidString + UUID().uuidString
            try SecretStore.write(Data(password.utf8), key: "identity-password")
        }
        if !FileManager.default.fileExists(atPath: archive.path) {
            let key = directory.appendingPathComponent("temporary-key.pem")
            let certificate = directory.appendingPathComponent("temporary-cert.pem")
            defer { try? FileManager.default.removeItem(at: key); try? FileManager.default.removeItem(at: certificate) }
            try run(["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", key.path, "-out", certificate.path, "-days", "3650", "-subj", "/CN=Trunkline Host"])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: key.path)
            try run(["pkcs12", "-export", "-inkey", key.path, "-in", certificate.path, "-out", archive.path,
                "-keypbe", "PBE-SHA1-3DES", "-certpbe", "PBE-SHA1-3DES", "-macalg", "sha1", "-passout", "env:TRUNKLINE_IDENTITY_PASSWORD"], password: password)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: archive.path)
        }
        var items: CFArray?
        // Never import the TLS private key into the login Keychain on startup.
        // The host requires macOS 15, where memory-only import is supported.
        let options: [String: Any] = [kSecImportExportPassphrase as String: password,
                                      kSecImportToMemoryOnly as String: true]
        let status = SecPKCS12Import(try Data(contentsOf: archive) as CFData,
            options as CFDictionary, &items)
        guard status == errSecSuccess, let imported = items as? [[String: Any]],
              let value = imported.first?[kSecImportItemIdentity as String] else { throw MacPhoneError.cryptoFailure }
        let identity = value as! SecIdentity
        var certificate: SecCertificate?
        guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess, let certificate else { throw MacPhoneError.cryptoFailure }
        return HostIdentity(identity: identity, fingerprint: CertificatePin.fingerprint(certificate))
    }
    private static func run(_ arguments: [String], password: String? = nil) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl"); process.arguments = arguments
        if let password { var env = ProcessInfo.processInfo.environment; env["TRUNKLINE_IDENTITY_PASSWORD"] = password; process.environment = env }
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw MacPhoneError.cryptoFailure }
    }
}
