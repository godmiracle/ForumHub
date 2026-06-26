import SwiftUI

enum PaperTheme {
    static let paper = Color(red: 0.94, green: 0.91, blue: 0.84)
    static let paperDeep = Color(red: 0.88, green: 0.84, blue: 0.74)
    static let ink = Color(red: 0.16, green: 0.13, blue: 0.1)
    static let secondaryInk = Color(red: 0.39, green: 0.34, blue: 0.27)
    static let mutedText = Color(red: 0.54, green: 0.48, blue: 0.39)
    static let hairline = Color(red: 0.42, green: 0.34, blue: 0.24).opacity(0.16)
    static let accent = Color(red: 0.72, green: 0.2, blue: 0.12)
    // Keep content containers opaque so scroll bounce and cell reuse never reveal stale content underneath.
    static let card = Color(red: 0.98, green: 0.95, blue: 0.88)
}

struct PaperBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    PaperTheme.paper,
                    Color(red: 0.91, green: 0.88, blue: 0.79),
                    Color(red: 0.95, green: 0.93, blue: 0.86)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            PaperFibers()
                .stroke(PaperTheme.ink.opacity(0.035), lineWidth: 0.45)
                .blendMode(.multiply)

            LinearGradient(
                colors: [
                    Color.white.opacity(0.28),
                    Color.clear,
                    Color.black.opacity(0.045)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

private struct PaperFibers: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step: CGFloat = 14
        var y: CGFloat = 0

        while y <= rect.height {
            path.move(to: CGPoint(x: 0, y: y))
            path.addCurve(
                to: CGPoint(x: rect.width, y: y + 4),
                control1: CGPoint(x: rect.width * 0.28, y: y - 3),
                control2: CGPoint(x: rect.width * 0.7, y: y + 7)
            )
            y += step
        }

        return path
    }
}
