import SwiftUI

extension Color {
    // Category language
    static let catAction = Color(red: 1.0, green: 0.624, blue: 0.039)    // #FF9F0A
    static let catDecision = Color(red: 0.188, green: 0.820, blue: 0.345) // #30D158
    static let catQuestion = Color(red: 0.039, green: 0.518, blue: 1.0)   // #0A84FF
    static let catDiscussion = Color(red: 0.557, green: 0.557, blue: 0.576) // #8E8E93

    // Text
    static let textPrimary = Color.white
    static let textSecondary = Color(red: 0.788, green: 0.773, blue: 0.863) // #C9C5DC
    static let textTertiary = Color(red: 0.541, green: 0.522, blue: 0.659)   // #8A85A8

    // Glassmorphism surface tokens
    static let glassFill = Color.white.opacity(0.05)
    static let glassStroke = Color.white.opacity(0.09)

    // Accent gradient endpoints
    static let accentPurple = Color(red: 0.482, green: 0.424, blue: 1.0) // #7B6CFF
    static let accentCyan = Color(red: 0.133, green: 0.827, blue: 0.933) // #22D3EE

    static var accentGradient: LinearGradient {
        LinearGradient(colors: [.accentPurple, .accentCyan],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var appBackground: LinearGradient {
        LinearGradient(colors: [Color(red: 0.043, green: 0.043, blue: 0.078), // #0B0B14
                                .black],
                       startPoint: .top, endPoint: .bottom)
    }
}

extension Animation {
    /// Signature app spring (response 0.45, damping 0.8). Use as `.recaplySpring`.
    /// Honors Reduce Motion at the call site.
    static let recaplySpring = Animation.spring(response: 0.45, dampingFraction: 0.8)
}
