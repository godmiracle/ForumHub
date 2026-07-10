import SwiftUI

enum ForumRadius {
    static let card: CGFloat = 18
    static let control: CGFloat = 18
    static let floatingBar: CGFloat = 24
}

struct ForumGlassContainer<Content: View>: View {
    private let cornerRadius: CGFloat
    private let padding: CGFloat
    private let isElevated: Bool
    @ViewBuilder private let content: () -> Content

    init(
        cornerRadius: CGFloat = ForumRadius.card,
        padding: CGFloat = 12,
        isElevated: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.isElevated = isElevated
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding)
            .forumGlass(
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
                isElevated: isElevated
            )
    }
}

struct ForumFloatingBar<Content: View>: View {
    private let padding: CGFloat
    @ViewBuilder private let content: () -> Content

    init(
        padding: CGFloat = 12,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.padding = padding
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding)
            .forumGlass(in: Capsule(), isElevated: true)
    }
}

struct ForumGlassButtonStyle: ButtonStyle {
    var isActive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                ForumGlassSurface(
                    shape: RoundedRectangle(cornerRadius: ForumRadius.control, style: .continuous),
                    isElevated: false,
                    accentOpacity: isActive ? 0.16 : 0
                )
            }
            .opacity(configuration.isPressed ? 0.86 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct ForumGlassNavigationBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbarBackground(.regularMaterial, for: .navigationBar)
    }
}

extension View {
    func forumGlass<Surface: InsettableShape>(
        in shape: Surface,
        isElevated: Bool = false,
        accentOpacity: Double = 0
    ) -> some View {
        background(
            ForumGlassSurface(
                shape: shape,
                isElevated: isElevated,
                accentOpacity: accentOpacity
            )
        )
    }

    func forumGlassNavigationBackground() -> some View {
        modifier(ForumGlassNavigationBackground())
    }
}

private struct ForumGlassSurface<Surface: InsettableShape>: View {
    let shape: Surface
    let isElevated: Bool
    let accentOpacity: Double

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                shape
                    .fill(.clear)
                    .glassEffect(
                        accentOpacity > 0
                            ? .regular.tint(PaperTheme.accent.opacity(accentOpacity))
                            : .regular,
                        in: shape
                    )
            } else {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay {
                        shape.stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.24),
                                    Color.white.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                    }
                    .overlay {
                        if accentOpacity > 0 {
                            shape.fill(PaperTheme.accent.opacity(accentOpacity))
                        }
                    }
            }
        }
        .shadow(
            color: Color.black.opacity(isElevated ? 0.1 : 0.07),
            radius: isElevated ? 16 : 12,
            y: isElevated ? 8 : 6
        )
    }
}
