#if canImport(TrunklineCore)
import TrunklineCore
#endif
import SwiftUI
import VisionKit
import AVFoundation

struct PairingScanner: View {
    let onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var authorized = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Group {
                if authorized && scenePhase == .active {
                    ScannerCamera { link in onScan(link); dismiss() } onError: { message = $0; authorized = false }
                        .ignoresSafeArea(edges: .bottom)
                        .safeAreaInset(edge: .bottom) {
                            Text("Point at the QR code in the Mac app.")
                                .font(.body).multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding().frame(maxWidth: .infinity)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                                .padding()
                        }
                } else {
                    ContentUnavailableView {
                        Label("Scan your Mac’s code", systemImage: "qrcode.viewfinder")
                    } description: {
                        Text(message ?? "Allow camera access to scan the QR code on your Mac.")
                    } actions: {
                        if AVCaptureDevice.authorizationStatus(for: .video) == .denied {
                            Button("Open Settings") { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
                        }
                    }
                }
            }
            .navigationTitle("Scan QR code").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task { await prepare() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await prepare() } } }
        }
    }
    private func prepare() async {
        guard DataScannerViewController.isSupported else {
            message = "Scanning isn’t supported on this device. Close this screen and paste the Mac’s pairing link instead."
            return
        }
        let granted: Bool
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            granted = await AVCaptureDevice.requestAccess(for: .video)
        } else { granted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized }
        authorized = granted && DataScannerViewController.isAvailable
        message = authorized ? nil : "Camera access is unavailable. Allow Camera in Settings, or paste the pairing link instead."
    }
}

private struct ScannerCamera: UIViewControllerRepresentable {
    let onScan: (String) -> Void
    let onError: (String) -> Void
    func makeUIViewController(context: Context) -> ScannerController { ScannerController(onScan: onScan, onError: onError) }
    func updateUIViewController(_ controller: ScannerController, context: Context) {}
}

private final class ScannerController: UIViewController, DataScannerViewControllerDelegate {
    private let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
        qualityLevel: .balanced, recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false,
        isGuidanceEnabled: true, isHighlightingEnabled: true)
    private var scan = PairingScan()
    private let onScan: (String) -> Void
    private let onError: (String) -> Void
    init(onScan: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
        self.onScan = onScan; self.onError = onError
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad()
        scanner.delegate = self
        addChild(scanner); view.addSubview(scanner.view)
        scanner.view.frame = view.bounds
        scanner.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scanner.didMove(toParent: self)
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        do { try scanner.startScanning() }
        catch { onError("The camera couldn’t start. Close the scanner and try again, or paste the pairing link.") }
    }
    override func viewWillDisappear(_ animated: Bool) { scanner.stopScanning(); super.viewWillDisappear(animated) }
    func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) { accept(addedItems) }
    func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) { accept(updatedItems) }
    func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) { accept([item]) }
    func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
        onError("The camera became unavailable. Close the scanner and try again.")
    }
    private func accept(_ items: [RecognizedItem]) {
        for case let .barcode(code) in items {
            if let payload = code.payloadStringValue, let pairing = scan.accept(payload) {
                scanner.stopScanning(); onScan(pairing.link); return
            }
        }
    }
}
