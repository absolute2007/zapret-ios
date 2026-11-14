import SwiftUI

// Liquid Glass on iOS 26+, materials on iOS 18–25.

extension View {
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat = 26, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            let glass = (tint.map { Glass.regular.tint($0) } ?? Glass.regular).interactive(interactive)
            self.glassEffect(glass, in: .rect(cornerRadius: cornerRadius))
        } else {
            self
                .background(.regularMaterial, in: .rect(cornerRadius: cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                }
        }
    }

    @ViewBuilder
    func glassCircle(tint: Color? = nil) -> some View {
        if #available(iOS 26.0, *) {
            let glass = (tint.map { Glass.regular.tint($0) } ?? Glass.regular).interactive()
            self.glassEffect(glass, in: .circle)
        } else {
            self
                .background(.ultraThinMaterial, in: .circle)
                .overlay { Circle().strokeBorder((tint ?? .white).opacity(0.35), lineWidth: 1) }
        }
    }

    @ViewBuilder
    func prominentButton() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    func secondaryButton() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    func modernTabBar<Accessory: View>(@ViewBuilder accessory: () -> Accessory) -> some View {
        if #available(iOS 26.0, *) {
            self
                .tabBarMinimizeBehavior(.onScrollDown)
                .tabViewBottomAccessory(content: accessory)
        } else {
            self
        }
    }
}

/// Groups glass shapes so they blend and morph together on iOS 26.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

/// Soft animated mesh behind the home screen, tinted by the current state.
struct StatusBackground: View {
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let s = Float(sin(t / 3) * 0.08)
            let c = Float(cos(t / 4) * 0.08)
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [0.5 + s, 0.45 + c], [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1],
                ],
                colors: [
                    color.opacity(0.55), .indigo.opacity(0.35), color.opacity(0.25),
                    .teal.opacity(0.25), color.opacity(0.45), .blue.opacity(0.25),
                    Color(.systemBackground), color.opacity(0.15), Color(.systemBackground),
                ]
            )
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.8), value: color)
    }
}

struct StatusDot: View {
    let color: Color
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .shadow(color: color.opacity(0.8), radius: 4)
    }
}

/// Section header used inside scrolling card layouts.
struct CardHeader: View {
    let title: String
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}
