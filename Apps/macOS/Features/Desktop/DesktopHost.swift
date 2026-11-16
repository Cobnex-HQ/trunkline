import AppKit
import Combine
import CryptoKit
import Security
#if canImport(TrunklineCore)
import TrunklineCore
#endif

private final class DesktopTrustDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    let certificate: Data
    init(certificate: Data) { self.certificate = certificate }
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host == "127.0.0.1", let trust = challenge.protectionSpace.serverTrust,
              let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = chain.first,
              SecCertificateCopyData(leaf) as Data == certificate else { completionHandler(.cancelAuthenticationChallenge, nil); return }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

struct DesktopPendingPair: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let address: String
}
struct DesktopClient: Decodable, Identifiable, Equatable {
    let uuid: String
    let name: String?
    var id: String { uuid }
}

@MainActor
final class DesktopHost: ObservableObject {
    @Published private(set) var desktopEnabled = UserDefaults.standard.bool(forKey: "sunshine-enabled")
    @Published private(set) var running = false
    @Published private(set) var starting = false
    @Published private(set) var status = "Desktop is off"
    @Published private(set) var pending: [DesktopPendingPair] = []
    @Published private(set) var clients: [DesktopClient] = []
    @Published var error: String?
    @Published private(set) var displaySelection: DesktopDisplaySelection?
    private var displaySelectionUnsupported = false
    private var selectingDisplay = false
    private var displaySelectionRevision = UUID()
    private struct HTTPStatusError: LocalizedError {
        let code: Int
        var errorDescription: String? { "The desktop engine rejected the request (\(code))." }
    }
    private var process: Process?
    private var retiring: [Process] = []
    private var monitor: Task<Void, Never>?
    private var generation = UUID()
    private var password = ""
    private var session: URLSession?
    private var refreshing = false
    private let username = "elephant"
    private(set) var directory: URL?

    init(session: URLSession? = nil) { self.session = session }

    func setEnabled(_ value: Bool) {
        desktopEnabled = value; UserDefaults.standard.set(value, forKey: "sunshine-enabled")
        if !value { stop() }
    }
    func prepareCredentials() throws {
        guard password.isEmpty else { return }
            if let saved = try SecretStore.readHostSecret("sunshine-management-password"), let value = String(data: saved, encoding: .utf8) { password = value }
            else {
                var random = [UInt8](repeating: 0, count: 32)
                guard SecRandomCopyBytes(kSecRandomDefault, random.count, &random) == errSecSuccess else { throw MacPhoneError.cryptoFailure }
                password = Data(random).base64EncodedString()
                try SecretStore.write(Data(password.utf8), key: "sunshine-management-password")
            }
    }
    func start() async {
        guard process == nil, !starting else { return }
        starting = true; error = nil; status = "Preparing desktop…"
        let token = UUID(); generation = token
        displaySelection = nil; displaySelectionUnsupported = false; selectingDisplay = false; displaySelectionRevision = UUID()
        do {
            await waitForRetiring()
            guard generation == token else { return }
            #if arch(arm64)
            let architecture = "arm64"
            #else
            let architecture = "x86_64"
            #endif
            let app = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/Desktop/\(architecture)/TrunklineDesktop.app")
            let executable = app.appendingPathComponent("Contents/MacOS/TrunklineDesktop")
            guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw CocoaError(.fileNoSuchFile) }
            let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("Trunkline/Sunshine", isDirectory: true)
            directory = root
            try FileManager.default.createDirectory(at: root.appendingPathComponent("credentials"), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
            let config = try DesktopHostConfiguration(root: root)
            try write(Data(config.contents.utf8), to: root.appendingPathComponent("sunshine.conf"))
            try write(config.applications, to: root.appendingPathComponent("apps.json"))
            try prepareCredentials()
            try write(DesktopHostConfiguration.credentials(username: username, password: password, salt: String(UUID().uuidString.prefix(16))), to: root.appendingPathComponent("management.json"))
            let supervisor = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/TrunklineDesktopSupervisor")
            guard FileManager.default.isExecutableFile(atPath: supervisor.path) else { throw CocoaError(.fileNoSuchFile) }
            let child = Process(); child.executableURL = supervisor
            child.arguments = [executable.path, root.appendingPathComponent("sunshine.conf").path]
            child.currentDirectoryURL = root
            // Stream logs directly to a bounded-on-start private file instead of retaining a Pipe backlog.
            let launchLog = root.appendingPathComponent("launcher.log")
            try write(Data(), to: launchLog)
            let output = try FileHandle(forWritingTo: launchLog)
            child.standardOutput = output; child.standardError = output; child.standardInput = FileHandle.nullDevice
            child.terminationHandler = { [weak self] child in
                try? output.close()
                Task { @MainActor in
                    guard let self, self.generation == token else { return }
                    self.process = nil; self.running = false; self.starting = false
                    self.displaySelection = nil; self.displaySelectionRevision = UUID()
                    self.status = "Desktop stopped (\(child.terminationStatus)). Check Screen Recording and input permissions, then start again."
                    self.monitor?.cancel(); self.monitor = nil
                    self.session?.invalidateAndCancel(); self.session = nil
                }
            }
            process = child
            do { try child.run() } catch { process = nil; try? output.close(); throw error }
            monitor = Task { [weak self] in
                guard let self else { return }
                var attempts = 0
                while !Task.isCancelled, self.generation == token, self.process?.isRunning == true {
                    do {
                        if self.session == nil { try self.prepareSession(root: root) }
                        try await self.refresh()
                        guard self.generation == token else { return }
                        if !self.running { self.running = true }
                        if self.starting { self.starting = false }
                        if self.status != "Desktop ready" { self.status = "Desktop ready" }
                    } catch {
                        attempts += 1
                        if attempts >= 15, self.starting { self.starting = false; self.status = "Trunkline Desktop has not become ready. Check permissions and the desktop log." }
                    }
                    try? await Task.sleep(for: .seconds(2))
                }
            }
        } catch { guard generation == token else { return }; starting = false; status = "Desktop could not start"; self.error = error.localizedDescription }
    }
    private func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    private func prepareSession(root: URL) throws {
        let pem = try String(contentsOf: root.appendingPathComponent("credentials/cert.pem"), encoding: .utf8)
        let base64 = pem.components(separatedBy: .newlines).filter { !$0.hasPrefix("-----") }.joined()
        guard let der = Data(base64Encoded: base64), SecCertificateCreateWithData(nil, der as CFData) != nil else { throw MacPhoneError.cryptoFailure }
        let config = URLSessionConfiguration.ephemeral; config.timeoutIntervalForRequest = 12; config.timeoutIntervalForResource = 20
        config.httpCookieStorage = nil; config.urlCache = nil
        session = URLSession(configuration: config, delegate: DesktopTrustDelegate(certificate: der), delegateQueue: nil)
    }
    private func request(_ path: String, body: Data? = nil, token: String? = nil) async throws -> Data {
        guard let session else { throw URLError(.cannotConnectToHost) }
        var request = URLRequest(url: URL(string: "https://127.0.0.1:47990" + path)!)
        request.setValue("Basic " + Data("\(username):\(password)".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        if let body {
            request.httpMethod = "POST"; request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(token, forHTTPHeaderField: "X-CSRF-Token")
        }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard response.statusCode == 200 else { throw HTTPStatusError(code: response.statusCode) }
        return data
    }
    private func csrf() async throws -> String {
        struct Token: Decodable { let csrf_token: String }
        return try JSONDecoder().decode(Token.self, from: await request("/api/csrf-token")).csrf_token
    }
    func refresh() async throws {
        guard !refreshing else { return }; refreshing = true; defer { refreshing = false }
        struct Pairs: Decodable { let pairings: [DesktopPendingPair] }
        struct Clients: Decodable { let named_certs: [DesktopClient]? }
        let pairs = try JSONDecoder().decode(Pairs.self, from: await request("/api/pin"))
        if pending != pairs.pairings { pending = pairs.pairings }
        let data = try await request("/api/clients/list")
        let latestClients = (try? JSONDecoder().decode(Clients.self, from: data).named_certs) ?? []
        if clients != latestClients { clients = latestClients }
        await refreshDisplaySelection()

    }
    private func refreshDisplaySelection() async {
        guard !displaySelectionUnsupported, !selectingDisplay else { return }
        let revision = displaySelectionRevision
        do {
            let data = try await request("/api/trunkline/displays")
            let state = nativeDisplayNames(try JSONDecoder().decode(DesktopDisplaySelection.self, from: data))
            guard revision == displaySelectionRevision, !Task.isCancelled else { return }
            let latestSelection = state.isAvailable ? state : nil
            if displaySelection != latestSelection { displaySelection = latestSelection }
            displaySelectionUnsupported = !state.supported
        } catch {
            guard revision == displaySelectionRevision, !Task.isCancelled else { return }
            if displaySelection != nil { displaySelection = nil }
            if let error = error as? HTTPStatusError, error.code == 404 { displaySelectionUnsupported = true }
        }
    }
    func selectDisplay(_ id: String) async throws {
        try MacControlAction.desktopDisplay(id).validate()
        guard running, let state = displaySelection, state.isAvailable else { throw MacControlError.unavailable }
        guard state.displays.contains(where: { $0.id == id }) else { throw MacControlError.missingDisplay }
        // A read already in flight must not replace this newer selection acknowledgement.
        let revision = UUID(); displaySelectionRevision = revision
        selectingDisplay = true
        defer { if displaySelectionRevision == revision { selectingDisplay = false } }
        let token = try await csrf()
        try Task.checkCancellation()
        guard displaySelectionRevision == revision else { throw CancellationError() }
        let data = try await request("/api/trunkline/displays", body: JSONEncoder().encode(["id": id]), token: token)
        try Task.checkCancellation()
        guard displaySelectionRevision == revision else { throw CancellationError() }
        let selected = nativeDisplayNames(try JSONDecoder().decode(DesktopDisplaySelection.self, from: data))
        guard selected.isAvailable, selected.preferredID == id else { throw MacControlError.missingDisplay }
        displaySelection = selected
    }
    private func nativeDisplayNames(_ selection: DesktopDisplaySelection) -> DesktopDisplaySelection {
        var names: [String: String] = [:]
        for screen in NSScreen.screens {
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
            names[String(id.uint32Value)] = screen.localizedName
        }
        return selection.withDisplayNames(names)
    }
    private func approveID(_ id: String, pin: String, name: String) async throws {
        let token = try await csrf()
        let approval = try DesktopPairApproval(id: id, pin: pin, name: name)
        struct Result: Decodable { let status: Bool }
        let data = try await request("/api/pin", body: JSONEncoder().encode(approval), token: token)
        guard try JSONDecoder().decode(Result.self, from: data).status else { throw URLError(.userAuthenticationRequired) }
        try await refresh()
    }
    func approve(_ pair: DesktopPendingPair, pin: String) async {
        do { try await approveID(pair.id, pin: pin, name: pair.name.isEmpty ? "Trunkline device" : pair.name) }
        catch { self.error = "Pairing failed. " + error.localizedDescription }
    }
    func approveFromCompanion(_ approval: DesktopPairRequest, isCurrent: () -> Bool) async throws {
        try approval.validate()
        for _ in 0..<30 {
            try Task.checkCancellation()
            guard isCurrent() else { throw CancellationError() }
            try await refresh()
            let names = pending.reduce(into: [String: String]()) { $0[$1.id] = $1.name }
            if let id = try approval.matchingID(in: names) {
                guard isCurrent(), !Task.isCancelled else { throw CancellationError() }
                try await approveID(id, pin: approval.pin, name: "Trunkline device")
                return
            }
            try await Task.sleep(for: .milliseconds(500))
        }
        throw URLError(.timedOut)
    }
    func revokeAll() async {
        do { let token = try await csrf(); _ = try await request("/api/clients/unpair-all", body: Data("{}".utf8), token: token); try await refresh() }
        catch { self.error = error.localizedDescription }
    }
    func restart() async {
        await shutdown()
        setEnabled(true)
        await start()
    }
    func stop() {
        generation = UUID(); monitor?.cancel(); monitor = nil
        displaySelection = nil; displaySelectionUnsupported = false; selectingDisplay = false; displaySelectionRevision = UUID()
        session?.invalidateAndCancel(); session = nil
        if let process, process.isRunning {
            retiring.append(process)
            process.terminate()
            Task { await ProcessShutdown.finish([process]) }
        }
        process = nil; running = false; starting = false; pending = []; clients = []; status = "Desktop is off"
    }
    private func waitForRetiring() async {
        await ProcessShutdown.finish(retiring)
        retiring.removeAll(where: { !$0.isRunning })
    }
    func shutdown() async { stop(); await waitForRetiring() }
    func showLogs() { if let directory { NSWorkspace.shared.open(directory) } }
}
