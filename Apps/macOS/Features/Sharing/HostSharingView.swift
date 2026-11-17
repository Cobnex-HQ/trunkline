import SwiftUI
import AppKit
import CoreImage.CIFilterBuiltins
import TrunklineCore

struct HostSharingView: View {
    @ObservedObject var model: HostModel
    @ObservedObject var sessions: TerminalSessions
    @State private var passcode = ""
    @State private var confirmation = ""
    @State private var authorizing = false
    @State private var copied = false
    private var needsCredentials: Bool { model.error?.contains("credentials") == true }
    private var runningSessions: [TerminalSessionInfo] { sessions.summaries.filter(\.isRunning) }
    private var sharingTitle: String {
        model.isStarting ? "Turning sharing on…" : model.isRunning ? "Sharing is on" : "Sharing is off"
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "laptopcomputer").font(.title).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Host.current().localizedName ?? "This Mac").font(.headline)
                        Text(sharingTitle).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 16)
                    if model.isStarting {
                        ProgressView().controlSize(.small)
                        Button("Cancel") { model.stop() }
                    } else {
                        Toggle("Share this Mac", isOn: Binding(get: { model.isRunning }, set: { enabled in
                            if enabled { Task { await model.start() } }
                            else { model.requestTurnOffSharing() }
                        }))
                        .toggleStyle(.switch).labelsHidden()
                        .accessibilityLabel("Share this Mac")
                        .help("Allow paired devices to connect to this Mac")
                        .disabled(!model.hasPasscode || needsCredentials)
                    }
                }.padding(.vertical, 6)
            } footer: {
                Text(model.isRunning ? "Your paired iPhone, iPad or Mac can connect. One device at a time." : "Turn on sharing to connect to this Mac from another device.")
            }

            if needsCredentials {
                Section("Approval needed") {
                    Text("Approve access to this Mac’s saved credentials once.").foregroundStyle(.secondary)
                    Button(authorizing ? "Waiting for approval…" : "Authorize credentials…") {
                        authorizing = true
                        Task { await model.authorizeCredentials(); authorizing = false }
                    }.disabled(authorizing)
                }
            } else if let error = model.error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).textSelection(.enabled)
                    Button("Dismiss") { model.error = nil }
                }
            }

            if !model.hasPasscode {
                Section("Set a connection passcode") {
                    Text("Use this passcode on the device connecting to your Mac.").foregroundStyle(.secondary)
                    passcodeFields(initialSetup: true)
                }
            }

            if model.isConnected || !runningSessions.isEmpty {
                Section("Sessions on this Mac") {
                    if model.isConnected {
                        HStack {
                            Label("A device is connected", systemImage: "checkmark.circle.fill")
                            Spacer()
                            Button("Disconnect device…") { model.requestDisconnectDevice() }
                        }
                    }
                    ForEach(runningSessions) { session in
                        HStack {
                            Label(session.title, systemImage: "terminal")
                            Spacer()
                            Text(session.isStopping == true ? "Ending…" : "Running")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    if !runningSessions.isEmpty {
                        Text("Terminal sessions keep running when sharing is off. Quitting Trunkline ends them.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            if model.isRunning {
                Section("Connect a device") {
                    HStack(alignment: .center, spacing: 24) {
                        pairingInstructions
                        PairingQRCode(link: model.pairingLink)
                    }.padding(.vertical, 8)
                }
                Section {
                    LabeledContent("Local network", value: "Available")
                    Toggle("Away access · Beta", isOn: Binding(get: { model.away.enabled }, set: { enabled in
                        if enabled { model.away.enable() } else { model.requestDisableAway() }
                    }))
                    if model.away.enabled && model.away.ticket == nil && !model.away.busy {
                        Button("Retry Away access") { model.away.start() }
                    }
                } header: { Text("Network") } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.away.status)
                        if model.away.enabled { Text("Use the updated pairing link or QR code. Direct access depends on both networks.") }
                    }
                }
            }

            Section {
                if model.hasPasscode {
                    DisclosureGroup("Connection passcode") {
                        passcodeFields(initialSetup: false).padding(.vertical, 8)
                    }
                }
                LabeledContent("Shared folder") {
                    HStack(spacing: 12) {
                        Text(model.sharedFolderPath.isEmpty ? "None selected" : URL(fileURLWithPath: model.sharedFolderPath).lastPathComponent)
                            .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary).help(model.sharedFolderPath)
                        Button("Choose…") { model.chooseSharedFolder() }.accessibilityLabel("Choose shared folder")
                    }
                }
                DisclosureGroup("Advanced network settings") {
                    TextField("Advertised address", text: $model.address).textFieldStyle(.roundedBorder)
                        .padding(.top, 8)
                    Text("Changes the address in your pairing link.").font(.caption).foregroundStyle(.secondary)
                }
            } header: { Text("Sharing settings") } footer: { Text("File access is limited to the selected folder.") }
        }
        .formStyle(.grouped)
        .onChange(of: model.pairingLink) { _, _ in copied = false }
    }

    private var pairingInstructions: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("From a Mac").font(.headline)
                Text("Choose Saved Macs under Remote Macs, then paste this link.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button(copied ? "Link copied" : "Copy pairing link", systemImage: copied ? "checkmark" : "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.pairingLink, forType: .string)
                    copied = true
                }.buttonStyle(.borderedProminent)
                ShareLink(item: model.pairingLink) { Image(systemName: "square.and.arrow.up") }
                    .help("Share pairing link").accessibilityLabel("Share pairing link")
            }.disabled(model.pairingLink.isEmpty)
            VStack(alignment: .leading, spacing: 4) {
                Text("From iPhone or iPad").font(.headline)
                Text("Scan the QR code in Trunkline.").font(.callout).foregroundStyle(.secondary)
            }
            Text("Enter this Mac’s connection passcode on the connecting device.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)
    }

    private func passcodeFields(initialSetup: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SecureField("New passcode", text: $passcode)
            SecureField("Confirm passcode", text: $confirmation)
            Text(passcode.utf8.count > 64 ? "Use no more than 64 characters." : "Use 8–64 characters.")
                .font(.caption).foregroundStyle(.secondary)
            if !confirmation.isEmpty && confirmation != passcode {
                Text("The passcodes don’t match.").font(.caption).foregroundStyle(.orange)
            }
            Button(initialSetup ? "Save and turn on sharing" : "Change passcode…") {
                if model.savePasscode(passcode) {
                    passcode = ""; confirmation = ""
                    if initialSetup { Task { await model.start() } }
                }
            }
            .disabled(!(8...64).contains(passcode.utf8.count) || passcode != confirmation)
        }.textFieldStyle(.roundedBorder).frame(maxWidth: 360, alignment: .leading)
    }
}

private struct PairingQRCode: View {
    let link: String
    @State private var image: NSImage?
    var body: some View {
        Group {
            if let image { Image(nsImage: image).interpolation(.none).resizable().scaledToFit() }
            else { Image(systemName: "qrcode").font(.largeTitle).foregroundStyle(.black) }
        }
        .frame(width: 132, height: 132).padding(12)
        .background(.white, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityLabel("Pairing QR code. You can also copy the pairing link.")
        .task(id: link) {
            let filter = CIFilter.qrCodeGenerator()
            filter.message = Data(link.utf8); filter.correctionLevel = "M"
            guard let output = filter.outputImage,
                  let raster = CIContext().createCGImage(output.transformed(by: CGAffineTransform(scaleX: 6, y: 6)), from: output.extent.applying(CGAffineTransform(scaleX: 6, y: 6))) else { image = nil; return }
            image = NSImage(cgImage: raster, size: NSSize(width: raster.width, height: raster.height))
        }
    }
}
