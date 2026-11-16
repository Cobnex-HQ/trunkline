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

/// A small, compositor-animated fold. No frame timer or parent-state updates.
/// Animation exists only while the loading view is visible and the scene is active.
public struct GlacierLoadingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    private let size: CGFloat
    public init(size: CGFloat = 32) { self.size = size }
    private var mark: some View {
        Image("ElephantMark").resizable().renderingMode(.template).scaledToFit()
            .foregroundStyle(Color("AccentColor")).frame(width: size, height: size)
    }
    public var body: some View {
        Group {
            if reduceMotion || scenePhase != .active { mark }
            else {
                mark.phaseAnimator([0, 1, 2]) { content, phase in
                    content.rotation3DEffect(.degrees(phase == 1 ? -18 : 0), axis: (x: 0, y: 1, z: 0))
                        .rotationEffect(.degrees(phase == 1 ? -4 : 0))
                        .offset(y: phase == 1 ? -2 : 0)
                } animation: { phase in .easeInOut(duration: phase == 2 ? 0.75 : 0.6) }
            }
        }.accessibilityLabel("Loading").accessibilityAddTraits(.updatesFrequently)
    }
}
#endif
