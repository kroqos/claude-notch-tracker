import SwiftUI

/// The card's colours. One poppy accent on the black for "on pace", warm sand for "ahead of the
/// window's clock", ember for "near the cap", so the three read as three at a glance.
enum Palette {
    static let accent = Color(red: 0.64, green: 0.50, blue: 1.0)    // electric violet, pops on black
    static let amber = Color(red: 0.96, green: 0.80, blue: 0.30)    // sand
    static let red = Color(red: 0.86, green: 0.22, blue: 0.24)      // ember
    static let label = Color.white.opacity(0.45)
    static let muted = Color.white.opacity(0.45)
    static let track = Color.white.opacity(0.10)
    static let rule = Color.white.opacity(0.08)
}
