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

private struct GlassCard: ViewModifier {
    var tint: Color
    var strength: Double
    var radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(tint.opacity(strength))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            }
    }
}

extension View {
    func glassCard(tint: Color = .white, strength: Double = 0.06, radius: CGFloat = 28) -> some View {
        modifier(GlassCard(tint: tint, strength: strength, radius: radius))
    }
}
