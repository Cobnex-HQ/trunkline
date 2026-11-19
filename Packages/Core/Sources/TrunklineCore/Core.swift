import Foundation
import CryptoKit
import CommonCrypto
import Security

public enum MacPhoneError: Error, LocalizedError {
    case invalidPacket, invalidPairing, weakPasscode, cryptoFailure
    public var errorDescription: String? {
        switch self {
        case .invalidPacket: "Invalid or oversized network message."
        case .invalidPairing: "Paste the complete pairing link shown on your Mac."
        case .weakPasscode: "Use 8–64 characters for the connection passcode."
        case .cryptoFailure: "Could not create secure credentials."
        }
    }
}
public enum PointerPhase: String, Codable, Sendable { case move, down, up, rightClick }
public struct VideoFrame: Codable, Equatable, Sendable {
    public let bytes: Data
    public let sps: Data
    public let pps: Data
    public let width: Int
    public let height: Int
    public var isKeyframe: Bool {
        let data = Array(bytes)
        var offset = 0
        var found = false
        while offset + 4 <= data.count {
            let size = data[offset..<(offset+4)].reduce(0) { ($0 << 8) | Int($1) }
            offset += 4
            guard size > 0, size <= data.count - offset else { return false }
            if data[offset] & 0x1f == 5 { found = true }
            offset += size
        }
        return offset == data.count && found
    }
    public init(bytes: Data, sps: Data, pps: Data, width: Int, height: Int) {
        self.bytes = bytes; self.sps = sps; self.pps = pps; self.width = width; self.height = height
    }
}
public struct AudioPacket: Codable, Equatable, Sendable {
    /// 48 kHz stereo interleaved signed 16-bit little-endian PCM.
    public let samples: Data
    public let frameCount: Int
    public init(samples: Data, frameCount: Int) { self.samples = samples; self.frameCount = frameCount }
    public var isValid: Bool { (1...4096).contains(frameCount) && samples.count == frameCount * 4 }
}
/// Optional context keeps the original error payload readable by older clients.
public struct OperationContext: Codable, Equatable, Sendable {
    public enum Domain: String, Codable, Sendable {
        case files, clipboard, terminal, desktop, general
        public init(from decoder: Decoder) throws {
            let value = try decoder.singleValueContainer().decode(String.self)
            self = Self(rawValue: value) ?? .general
        }
    }
    public let domain: Domain
    public let requestID: String?
    public init(_ domain: Domain, requestID: String? = nil) {
        self.domain = domain; self.requestID = requestID
    }
}
/// Strings on the wire let future hosts advertise features older clients can ignore.
public enum FileFeature: String, CaseIterable, Sendable {
    case mutations, folderUpload, cancellation, resumableTransfers
}
public enum WireMessage: Codable, Equatable, Sendable {
    case authenticate(passcode: String)
    case accepted(name: String, display: DesktopDisplay, fileFeatures: [String]? = nil)
    case failure(String, cause: ConnectionFailureCause? = nil)
    case startStream(profile: StreamProfile)
    case video(VideoFrame)
    case audio(AudioPacket)
    case setAudioEnabled(Bool)
    case requestKeyframe
    case stopStream
    case pairDesktop(DesktopPairRequest)
    case requestControls(windowAppPID: Int32? = nil, requestID: UUID? = nil, windowCursor: UUID? = nil, preserveWindows: Bool? = nil)
    case controls(MacControlSnapshot)
    case control(MacControlRequest)
    case controlResult(MacControlResult)
    case listTerminals
    case terminals([TerminalSessionInfo])
    case createTerminal(kind: TerminalKind, title: String)
    case attachTerminal(id: UUID)
    case terminalOutput(id: UUID, bytes: Data, reset: Bool)
    case terminalInput(id: UUID, bytes: Data)
    case resizeTerminal(id: UUID, columns: Int, rows: Int)
    case closeTerminal(id: UUID)
    case pointer(x: Double, y: Double, phase: PointerPhase)
    case scroll(dx: Double, dy: Double)
    case text(String)
    case key(code: UInt16, modifiers: UInt64)
    case renameTerminal(id: UUID, title: String)
    case mutateFile(id: UUID, action: FileMutation)
    case fileMutationResult(id: UUID, error: String?)
    case listFiles(path: String)
    case fileList(path: String, entries: [RemoteFile])
    case resumableFile(id: UUID, request: FileTransferRequest)
    case resumableFileReply(id: UUID, reply: FileTransferReply)
    case beginUpload(name: String, size: Int64)
    case beginUploadInFolder(parent: String, name: String, size: Int64)
    case cancelFileTransfer(id: UUID)
    case fileTransferCancelled(id: UUID)
    case uploadReady(id: UUID)
    case uploadChunk(id: UUID, offset: Int64, bytes: Data)
    case transferProgress(id: UUID, received: Int64, total: Int64)
    case uploadComplete(id: UUID)
    case download(path: String)
    case downloadStarted(id: UUID, name: String, size: Int64)
    case requestChunk(id: UUID, offset: Int64)
    case downloadChunk(id: UUID, offset: Int64, bytes: Data, last: Bool)
    case operationError(String, context: OperationContext? = nil)
    case requestClipboard
    case clipboard(String)
    case setClipboard(String)
    case ping
    case pong
    public var isValidInput: Bool {
        switch self {
        case let .pointer(x, y, _): x.isFinite && y.isFinite && (0...1).contains(x) && (0...1).contains(y)
        case let .scroll(dx, dy): dx.isFinite && dy.isFinite && abs(dx) <= 1000 && abs(dy) <= 1000
        case let .text(text): text.utf16.count <= 4096
        case let .key(code, modifiers): code <= 126 && modifiers & ~UInt64(0x1e0000) == 0
        default: false
        }
    }
}
public enum StreamProfile: String, Codable, CaseIterable, Sendable, Identifiable {
    case responsive, balanced, detail, localHigh, dataSaver
    public var id: String { rawValue }
    public var title: String {
        switch self { case .responsive: "Responsive"; case .balanced: "Balanced"; case .detail: "Sharper text"; case .localHigh: "Local high"; case .dataSaver: "Save bandwidth" }
    }
    public var maximumWidth: Int {
        switch self { case .responsive, .dataSaver: 1280; case .balanced: 1600; case .detail, .localHigh: 1920 }
    }
    public var framesPerSecond: Int { self == .dataSaver ? 30 : 60 }
    public var bitrate: Int {
        switch self { case .responsive: 4_000_000; case .balanced: 8_000_000; case .detail: 12_000_000; case .localHigh: 20_000_000; case .dataSaver: 2_000_000 }
    }
}
public enum PacketCodec {
    public static let maximumSize = 4 * 1024 * 1024
    public static func encode(_ message: WireMessage) throws -> Data {
        var body = Data()
        if case let .video(frame) = message {
            guard (1...8192).contains(frame.width), (1...8192).contains(frame.height), !frame.sps.isEmpty, !frame.pps.isEmpty,
                frame.sps.count <= 4096, frame.pps.count <= 4096, !frame.bytes.isEmpty else { throw MacPhoneError.invalidPacket }
            body.append(1)
            for value in [frame.width, frame.height, frame.sps.count, frame.pps.count] {
                var number = UInt16(value).bigEndian
                withUnsafeBytes(of: &number) { body.append(contentsOf: $0) }
            }
            body.append(frame.sps); body.append(frame.pps); body.append(frame.bytes)
        } else if case let .terminalOutput(id, bytes, reset) = message {
            guard bytes.count <= 512 * 1024 else { throw MacPhoneError.invalidPacket }
            body.append(3); body.append(contentsOf: id.uuidString.utf8); body.append(reset ? 1 : 0); body.append(bytes)
        } else if case let .audio(audio) = message {
            guard audio.isValid else { throw MacPhoneError.invalidPacket }
            body.append(2)
            var frames = UInt16(audio.frameCount).bigEndian
            withUnsafeBytes(of: &frames) { body.append(contentsOf: $0) }
            body.append(audio.samples)
        } else {
            body.append(0); body.append(try JSONEncoder().encode(message))
        }
        guard body.count <= maximumSize else { throw MacPhoneError.invalidPacket }
        var length = UInt32(body.count).bigEndian
        return withUnsafeBytes(of: &length) { Data($0) } + body
    }
    static func decode(_ body: Data) throws -> WireMessage {
        guard let type = body.first else { throw MacPhoneError.invalidPacket }
        if type == 0 { return try JSONDecoder().decode(WireMessage.self, from: body.dropFirst()) }
        if type == 3 {
            guard body.count >= 38, body.count <= 512 * 1024 + 38,
                let value = String(data: body.subdata(in: 1..<37), encoding: .utf8), let id = UUID(uuidString: value), body[37] <= 1 else { throw MacPhoneError.invalidPacket }
            return .terminalOutput(id: id, bytes: Data(body.dropFirst(38)), reset: body[37] == 1)
        }
        if type == 2 {
            guard body.count >= 3 else { throw MacPhoneError.invalidPacket }
            let packet = AudioPacket(samples: Data(body.dropFirst(3)), frameCount: Int(body[1]) << 8 | Int(body[2]))
            guard packet.isValid else { throw MacPhoneError.invalidPacket }
            return .audio(packet)
        }
        guard type == 1, body.count >= 9 else { throw MacPhoneError.invalidPacket }
        func number(_ offset: Int) -> Int { Int(body[offset]) << 8 | Int(body[offset + 1]) }
        let width = number(1), height = number(3), spsSize = number(5), ppsSize = number(7)
        let end = 9 + spsSize + ppsSize
        guard (1...8192).contains(width), (1...8192).contains(height), (1...4096).contains(spsSize),
            (1...4096).contains(ppsSize), end < body.count else { throw MacPhoneError.invalidPacket }
        return .video(VideoFrame(bytes: Data(body[end...]), sps: body.subdata(in: 9..<(9+spsSize)), pps: body.subdata(in: (9+spsSize)..<end), width: width, height: height))
    }
}
public struct PacketParser {
    private var buffer = Data()
    public init() {}
    public mutating func append(_ data: Data) throws -> [WireMessage] {
        buffer.append(data)
        var result: [WireMessage] = []
        while buffer.count >= 4 {
            let size = buffer.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
            guard size > 0, size <= PacketCodec.maximumSize else { throw MacPhoneError.invalidPacket }
            guard buffer.count >= size + 4 else { break }
            result.append(try PacketCodec.decode(buffer.subdata(in: 4..<(size + 4))))
            buffer = Data(buffer.dropFirst(size + 4))
        }
        return result
    }
}
public struct PasscodeRecord: Codable, Sendable {
    public let salt: Data
    public let digest: Data
    public init(passcode: String) throws {
        guard (8...64).contains(passcode.utf8.count) else { throw MacPhoneError.weakPasscode }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw MacPhoneError.cryptoFailure }
        salt = Data(bytes)
        digest = Self.derive(passcode, salt: salt)
    }
    public func verify(_ passcode: String) -> Bool {
        guard passcode.utf8.count <= 64 else { return false }
        let candidate = Self.derive(passcode, salt: salt)
        guard candidate.count == digest.count else { return false }
        return zip(candidate, digest).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
    private static func derive(_ passcode: String, salt: Data) -> Data {
        let password = Array(passcode.utf8)
        var output = [UInt8](repeating: 0, count: 32)
        let status = password.withUnsafeBytes { pass in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pass.bindMemory(to: Int8.self).baseAddress, password.count,
                    saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 210_000, &output, output.count)
            }
        }
        precondition(status == kCCSuccess)
        return Data(output)
    }
}
public struct AttemptLimiter: Codable, Sendable {
    private var failures = 0
    private var blockedUntil: Date?
    public init() {}
    public func isAllowed(at now: Date = Date()) -> Bool { blockedUntil.map { now >= $0 } ?? true }
    public mutating func recordFailure(at now: Date = Date()) {
        failures += 1
        if failures >= 5 { blockedUntil = now.addingTimeInterval(60); failures = 0 }
    }
    public mutating func reset() { failures = 0; blockedUntil = nil }
}
public struct PairingDetails: Codable, Equatable, Sendable {
    public let host: String
    public let port: UInt16
    public let fingerprint: String
    public let remote: RemoteAccessTicket?
    public init(host: String, port: UInt16, fingerprint: String, remote: RemoteAccessTicket? = nil) throws {
        let normalized = fingerprint.lowercased().replacingOccurrences(of: ":", with: "")
        guard !host.isEmpty, host.count <= 253, !host.contains(where: { $0.isWhitespace }), port > 0,
              normalized.count == 64, normalized.allSatisfy({ $0.isHexDigit && $0.isASCII }) else { throw MacPhoneError.invalidPairing }
        self.host = host; self.port = port; self.fingerprint = normalized
        if let remote { try remote.validate() }; self.remote = remote
    }
    public var link: String {
        var url = URLComponents()
        url.scheme = "trunkline"; url.host = "pair"
        url.queryItems = [URLQueryItem(name: "host", value: host), URLQueryItem(name: "port", value: String(port)), URLQueryItem(name: "pin", value: fingerprint)]
        if let remote, let data = try? JSONEncoder().encode(remote) {
            url.queryItems?.append(URLQueryItem(name: "remote", value: data.base64EncodedString()))
        }
        return url.string!
    }
    public static func parse(_ link: String) throws -> Self {
        guard let url = URLComponents(string: link.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme == "trunkline", url.host == "pair" else { throw MacPhoneError.invalidPairing }
        func item(_ key: String) -> String { url.queryItems?.first(where: { $0.name == key })?.value ?? "" }
        guard let port = UInt16(item("port")) else { throw MacPhoneError.invalidPairing }
        var remote: RemoteAccessTicket?
        if url.queryItems?.contains(where: { $0.name == "remote" }) == true {
            guard item("remote").count <= 8192, let data = Data(base64Encoded: item("remote")) else { throw MacPhoneError.invalidPairing }
            remote = try JSONDecoder().decode(RemoteAccessTicket.self, from: data)
        }
        return try Self(host: item("host"), port: port, fingerprint: item("pin"), remote: remote)
    }
}
public enum CertificatePin {
    public static func fingerprint(_ certificate: SecCertificate) -> String {
        SHA256.hash(data: SecCertificateCopyData(certificate) as Data).map { String(format: "%02x", $0) }.joined()
    }
}
