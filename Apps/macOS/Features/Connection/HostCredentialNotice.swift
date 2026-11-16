#if canImport(TrunklineCore)
import TrunklineCore
#endif
import SwiftUI

/// A route back to explicit setup; displaying this notice never reads Keychain.
struct HostCredentialNotice: View {
    let review: () -> Void
    var body: some View {
        HStack(spacing: 16) {
            Label {
                Text("Saved credentials need approval")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "key.fill").foregroundStyle(.orange)
            }
            Spacer(minLength: 0)
            Button("Review access", action: review).fixedSize()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08))
    }
}
