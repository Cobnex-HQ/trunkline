#if canImport(TrunklineCore)
import TrunklineCore
#endif
import SwiftUI

/// Compact native typography without overriding the person's Dynamic Type choice.
struct NativeWorkspaceStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.subheadline)
            .listStyle(.insetGrouped)
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Color.workspaceBackground)
            .environment(\.defaultMinListRowHeight, TrunklineControls.minimumHeight)
            .buttonBorderShape(TrunklineControls.buttonShape)
            .listSectionSpacing(16)
            .navigationBarTitleDisplayMode(.inline)
    }
}
extension View {
    func nativeWorkspaceStyle() -> some View { modifier(NativeWorkspaceStyle()) }
}

extension UIColor {
    static var workspaceBackground: UIColor {
        UIColor(named: "WorkspaceBackground") ?? .systemGroupedBackground
    }
}

extension Color {
    static var workspaceBackground: Color { Color(uiColor: .workspaceBackground) }
}

/// Keep the native toolbar button and its footprint stable while a request runs.
struct RefreshButton: View {
    var isRefreshing: Bool
    var isDisabled = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .opacity(isRefreshing ? 0 : 1)
                .overlay {
                    if isRefreshing { ProgressView().controlSize(.small).accessibilityHidden(true) }
                }
                .frame(width: 22, height: 22)
        }
        .tint(.primary)
        .accessibilityLabel("Refresh")
        .accessibilityValue(isRefreshing ? "Refreshing" : "")
        .disabled(isRefreshing || isDisabled)
    }
}

/// Equal action sizes derived from the complete labels, with rows fitted to available space.
struct ContentSizedActionLayout: Layout {
    private let spacing: CGFloat = 8

    private func metrics(_ proposal: ProposedViewSize, _ subviews: Subviews) -> (columns: Int, size: CGSize) {
        let idealWidth = subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let available = max(1, proposal.width ?? idealWidth * 3 + spacing * 2)
        let width = min(idealWidth, available)
        let columns = min(3, max(1, Int(((available + spacing) / (width + spacing) + 0.001).rounded(.down))))
        let height = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }.max() ?? 0
        return (columns, CGSize(width: width, height: max(TrunklineControls.minimumHeight, height)))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let (columns, cell) = metrics(proposal, subviews)
        let rows = (subviews.count + columns - 1) / columns
        return CGSize(width: cell.width * CGFloat(columns) + spacing * CGFloat(columns - 1),
                      height: cell.height * CGFloat(rows) + spacing * CGFloat(rows - 1))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (columns, cell) = metrics(ProposedViewSize(width: bounds.width, height: nil), subviews)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + CGFloat(index % columns) * (cell.width + spacing),
                                     y: bounds.minY + CGFloat(index / columns) * (cell.height + spacing)),
                          anchor: .topLeading, proposal: ProposedViewSize(cell))
        }
    }
}
