#if canImport(TrunklineCore)
import TrunklineCore
#endif
import SwiftUI

/// Compact native typography without overriding the person's Dynamic Type choice.
struct NativeWorkspaceStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.subheadline)
            .environment(\.defaultMinListRowHeight, 44)
            .listSectionSpacing(16)
            .navigationBarTitleDisplayMode(.inline)
    }
}
extension View {
    func nativeWorkspaceStyle() -> some View { modifier(NativeWorkspaceStyle()) }
}
