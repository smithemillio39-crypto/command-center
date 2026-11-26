import SwiftUI
import UIKit

enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func failure() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}

extension Color {
    static let ccBlue = Color(red: 0.20, green: 0.52, blue: 1.00)
    static let ccMint = Color(red: 0.36, green: 0.86, blue: 0.72)
    static let ccPink = Color(red: 1.00, green: 0.42, blue: 0.60)
    static let ccAmber = Color(red: 1.00, green: 0.76, blue: 0.32)
    static let ccViolet = Color(red: 0.62, green: 0.50, blue: 1.00)
}

// MARK: - Backdrop

/// Lyra's own portrait, graded violet, sits behind everything so the glass has
/// real light to refract instead of flat black.
struct LyraBackdrop: View {
    var body: some View {
        ZStack {
            Image("Backdrop")
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .overlay {
                    LinearGradient(
                        stops: [
                            .init(color: Color(red: 0.04, green: 0.03, blue: 0.07).opacity(0.20), location: 0.00),
                            .init(color: Color(red: 0.03, green: 0.02, blue: 0.05).opacity(0.50), location: 0.52),
                            .init(color: Color(red: 0.02, green: 0.01, blue: 0.04).opacity(0.86), location: 1.00)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }

            Circle()
                .fill(Color.ccViolet.opacity(0.20))
                .frame(width: 340)
                .blur(radius: 100)
                .offset(x: 150, y: 250)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Glass

private struct GlassCard: ViewModifier {
    var tint: Color
    var strength: Double
    var radius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay { shape.fill(tint.opacity(strength)) }
                    .overlay {
                        shape.fill(
                            LinearGradient(
                                stops: [
                                    .init(color: Color.white.opacity(0.20), location: 0.00),
                                    .init(color: Color.white.opacity(0.05), location: 0.30),
                                    .init(color: Color.white.opacity(0.01), location: 1.00)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    }
            }
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.46), location: 0.00),
                            .init(color: Color.white.opacity(0.07), location: 0.45),
                            .init(color: Color.white.opacity(0.16), location: 1.00)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            }
            .shadow(color: Color.black.opacity(0.38), radius: 24, x: 0, y: 16)
    }
}

private struct GlassSurface<S: Shape>: ViewModifier {
    var shape: S
    var tint: Color
    var strength: Double
    var gloss: Double

    func body(content: Content) -> some View {
        content
            .background {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay { shape.fill(tint.opacity(strength)) }
                    .overlay {
                        shape.fill(
                            LinearGradient(
                                stops: [
                                    .init(color: Color.white.opacity(gloss), location: 0.00),
                                    .init(color: Color.white.opacity(gloss * 0.25), location: 0.45),
                                    .init(color: .clear, location: 1.00)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.40),
                            Color.white.opacity(0.06),
                            Color.white.opacity(0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            }
            .shadow(color: Color.black.opacity(0.26), radius: 10, x: 0, y: 6)
    }
}

extension View {
    func glassCard(tint: Color = .white, strength: Double = 0.06, radius: CGFloat = 28) -> some View {
        modifier(GlassCard(tint: tint, strength: strength, radius: radius))
    }

    /// A glossy glass chip: buttons, pills, list rows.
    func glassSurface<S: Shape>(
        _ shape: S,
        tint: Color = .white,
        strength: Double = 0.10,
        gloss: Double = 0.22
    ) -> some View {
        modifier(GlassSurface(shape: shape, tint: tint, strength: strength, gloss: gloss))
    }
}
