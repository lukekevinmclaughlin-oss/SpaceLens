import SwiftUI

/// SpaceLens visual language — a holographic HUD palette that matches the
/// arc-reactor app icon: cyan light on deep navy, amber for accents.
enum Theme {
    static let holoCyan   = Color(red: 0.19, green: 0.91, blue: 1.0)   // #31E8FF
    static let holoCyanDim = Color(red: 0.12, green: 0.55, blue: 0.66)
    static let holoIce    = Color(red: 0.72, green: 0.96, blue: 1.0)   // #B7F3FF
    static let amber      = Color(red: 1.0, green: 0.71, blue: 0.23)   // #FFB53A

    static let deepTop    = Color(red: 0.043, green: 0.14, blue: 0.21) // #0B2436
    static let deepMid    = Color(red: 0.024, green: 0.071, blue: 0.12)
    static let deepBottom = Color(red: 0.008, green: 0.02, blue: 0.035)

    static let bgGradient = LinearGradient(
        colors: [deepTop, deepMid, deepBottom],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let cyanGradient = LinearGradient(
        colors: [holoIce, holoCyan], startPoint: .top, endPoint: .bottom)
}
