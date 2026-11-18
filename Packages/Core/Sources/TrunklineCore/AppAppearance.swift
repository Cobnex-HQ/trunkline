#if canImport(SwiftUI)
import SwiftUI

public enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    public var id: Self { self }
    public var title: String {
        switch self { case .system: "System"; case .light: "Light"; case .dark: "Dark" }
    }
    public var colorScheme: ColorScheme? {
        switch self { case .system: nil; case .light: .light; case .dark: .dark }
    }
}

public struct AppearancePicker: View {
    @AppStorage("trunkline.appearance") private var appearance: AppAppearance = .system
    public init() {}
    public var body: some View {
        Picker("Appearance", selection: $appearance) {
            ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
        }
    }
}

/// Native indeterminate progress with a stable footprint for existing callers.
public struct GlacierLoadingIndicator: View {
    private let size: CGFloat
    public init(size: CGFloat = 32) { self.size = size }
    public var body: some View {
        ProgressView()
            .progressViewStyle(.circular)
            .controlSize(.regular)
            .tint(.secondary)
            .frame(width: size, height: size)
            .accessibilityLabel("Loading")
    }
}
#endif
