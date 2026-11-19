import SwiftUI
import TrunklineCore

struct ConnectionDiagnosticsView: View {
    let diagnostic: ConnectionDiagnostic
    let snapshot: MacControlSnapshot?
    var refresh: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    private var report: String {
        diagnostic.report + "\nHost input permission: \(status(snapshot?.inputAccess))\nHost screen recording: \(status(snapshot?.screenCaptureAccess))\nHost window controls: \(status(snapshot?.accessibility))"
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Last connection attempt") {
                    LabeledContent("Route", value: diagnostic.route.rawValue)
                    LabeledContent("Last stage", value: diagnostic.stage.rawValue)
                    if let failure = diagnostic.failure {
                        Label(failure.title, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                        Text(diagnostic.explanation).textSelection(.enabled)
                    }
                }
                Section {
                    LabeledContent("Mouse and keyboard", value: status(snapshot?.inputAccess))
                    LabeledContent("Screen recording", value: status(snapshot?.screenCaptureAccess))
                    LabeledContent("Window controls", value: status(snapshot?.accessibility))
                    if let refresh { Button("Refresh Mac checks", action: refresh) }
                } header: { Text("Mac app permissions") } footer: {
                    Text(snapshot == nil ? "Connect to check Mac permissions." : "These checks describe the Mac app. Its desktop helper may need separate macOS approval.")
                }
                Section {
                    ShareLink("Share connection report", item: report)
                } footer: {
                    Text("The report contains connection stages and permission status. It excludes addresses, pairing links, credentials and clipboard text.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Connection details")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 540, minHeight: 440)
        #endif
    }
    private func status(_ value: Bool?) -> String {
        guard let value else { return "Not checked" }
        return value ? "Allowed" : "Not allowed"
    }
}
