#if canImport(TrunklineCore)
import TrunklineCore
#endif
import SwiftUI

/// Shared metrics for SwiftUI actions and UIKit terminal keys.
enum TrunklineControls {
    static let shape = Capsule()
    static let uiKitCornerStyle = UIButton.Configuration.CornerStyle.capsule
    static let minimumHeight: CGFloat = 44
    static let labelMinimumHeight: CGFloat = 32
    static let actionRowInsets = EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20)
    static var buttonShape: ButtonBorderShape { .capsule }
}

private struct TrunklineActionStyle: ViewModifier {
    var prominent: Bool

    func body(content: Content) -> some View {
        Group {
            if prominent {
                content.buttonStyle(.borderedProminent)
                    .tint(Color("ControlSurface")).foregroundStyle(.white)
            } else {
                content.buttonStyle(.bordered).tint(.primary)
            }
        }
        .buttonBorderShape(TrunklineControls.buttonShape)
        .controlSize(.regular)
    }
}

extension View {
    func trunklineActionStyle(prominent: Bool = false) -> some View {
        modifier(TrunklineActionStyle(prominent: prominent))
    }

    func trunklineActionLabel() -> some View {
        self.font(.subheadline).lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minHeight: TrunklineControls.labelMinimumHeight)
    }
}

/// Native sections with one separator edge, regardless of a row's icon or label style.
struct TrunklineSection<Content: View, Header: View, Footer: View>: View {
    let content: Content
    let header: Header
    let footer: Footer

    init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Header,
         @ViewBuilder footer: () -> Footer) {
        self.content = content()
        self.header = header()
        self.footer = footer()
    }

    var body: some View {
        Section {
            Group { content }.trunklineRowSeparators()
        } header: { header } footer: { footer }
    }
}

extension TrunklineSection where Header == EmptyView, Footer == EmptyView {
    init(@ViewBuilder content: () -> Content) {
        self.init(content: content, header: { EmptyView() }, footer: { EmptyView() })
    }
}

extension TrunklineSection where Header == Text, Footer == EmptyView {
    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.init(content: content, header: { Text(title) }, footer: { EmptyView() })
    }
    init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content) {
        self.init(content: content, header: { Text(title) }, footer: { EmptyView() })
    }
}

extension TrunklineSection where Footer == EmptyView {
    init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Header) {
        self.init(content: content, header: header, footer: { EmptyView() })
    }
}

extension TrunklineSection where Header == EmptyView {
    init(@ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.init(content: content, header: { EmptyView() }, footer: footer)
    }
}

extension View {
    func trunklineRowSeparators() -> some View {
        alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }
}

struct TrunklineBrandHeader: View {
    let title: String
    let subtitle: String
    var compact = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: compact ? 12 : 18) { mark; copy }
            VStack(alignment: .leading, spacing: 14) { mark; copy }
        }
        .accessibilityElement(children: .combine)
    }

    private var mark: some View {
        Image("ElephantLogo")
            .resizable()
            .scaledToFit()
            .frame(width: compact ? 52 : 76, height: compact ? 52 : 76)
            .clipShape(RoundedRectangle(cornerRadius: compact ? 15 : 22, style: .continuous))
            .accessibilityHidden(true)
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(compact ? .title2.bold() : .largeTitle.bold())
            Text(subtitle).font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct TrunklineCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct TrunklineStatusPill: View {
    let title: String
    let systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

struct TrunklineActionRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .frame(width: 42, height: 42)
                    .foregroundStyle(.white)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(detail)
    }
}
