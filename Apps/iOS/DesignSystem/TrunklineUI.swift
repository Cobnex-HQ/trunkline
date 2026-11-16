#if canImport(TrunklineCore)
import TrunklineCore
#endif
import SwiftUI

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
