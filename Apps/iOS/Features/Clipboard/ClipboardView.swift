import SwiftUI
import TrunklineCore

struct ClipboardView: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var files: ClientFiles
    @ObservedObject private var clipboard: ClipboardTransfer
    @State private var outgoing = ""
    init(files: ClientFiles) {
        self.files = files
        self.clipboard = files.clipboard
    }
    var body: some View {
        NavigationStack {
            Form {
                TrunklineSection("From Mac") {
                    Button("Copy from Mac", systemImage: "arrow.down.doc") { clipboard.copyFromMac() }
                        .disabled(clipboard.isBusy || clipboard.requiresReconnect)
                    if !files.clipboardText.isEmpty {
                        Text(files.clipboardText).lineLimit(6).textSelection(.enabled)
                    }
                }
                TrunklineSection("To Mac") {
                    PasteButton(payloadType: String.self) { outgoing = $0.joined(separator: "\n") }
                    TextEditor(text: $outgoing)
                        .frame(minHeight: verticalSizeClass == .compact ? 80 : 120)
                        .accessibilityLabel("Clipboard text")
                        .overlay(alignment: .topLeading) {
                            if outgoing.isEmpty {
                                Text("Type or paste text").foregroundStyle(.tertiary)
                                    .padding(.top, 8).padding(.leading, 5)
                                    .allowsHitTesting(false).accessibilityHidden(true)
                            }
                        }
                    Button("Paste to Mac", systemImage: "arrow.up.doc") { clipboard.pasteToMac(outgoing) }
                        .disabled(outgoing.isEmpty || outgoing.utf16.count > 65536 || clipboard.isBusy || clipboard.requiresReconnect)
                    Text("Copies text to your Mac’s clipboard, ready to paste.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if clipboard.isBusy {
                    TrunklineSection { ProgressView("Transferring text…") }
                } else if let error = clipboard.error {
                    TrunklineSection { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.orange) }
                } else if let feedback = clipboard.feedback {
                    TrunklineSection { Text(feedback).foregroundStyle(.secondary).accessibilityIdentifier("clipboard.feedback") }
                }
                TrunklineSection("Sync with this Mac") {
                    Picker("Text sync", selection: Binding(get: { clipboard.mode }, set: { files.setClipboardSyncMode($0) })) {
                        ForEach(ClipboardSyncMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Text("Syncs text while this window is active. Both directions may ask for paste permission. Text isn’t saved.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .nativeWorkspaceStyle()
            .frame(maxWidth: 780).frame(maxWidth: .infinity)
            .background(Color.workspaceBackground)
            .navigationTitle("Clipboard")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
