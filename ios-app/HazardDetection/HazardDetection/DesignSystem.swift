import SwiftUI

extension Color {
    static let appPrimary = Color(hex: "#3b82f6")
    static let appDark950 = Color(hex: "#020617")
    static let appDark900 = Color(hex: "#0f172a")
    static let appDark800 = Color(hex: "#1e293b")
    static let appDark400 = Color(hex: "#94a3b8")
    static let appSuccess = Color(hex: "#22c55e")
    static let appWarning = Color(hex: "#f59e0b")
    static let appDanger = Color(hex: "#ef4444")
    
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

struct GlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}

extension View {
    func glassCard() -> some View {
        self.modifier(GlassModifier())
    }
}

struct GradientAccent: View {
    var body: some View {
        LinearGradient(
            colors: [.appPrimary, .purple],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
