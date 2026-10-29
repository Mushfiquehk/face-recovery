import SwiftUI
import UIKit

/// The app's few status colours, chosen so text in them stays readable (WCAG AA, 4.5:1) on the
/// grouped backgrounds in both light and dark mode. The system green, yellow and orange are too
/// pale for text on white, and these are often read by older eyes. See docs/DESIGN.md.
enum Palette {
    /// Well slept, and Contributions that raised the number.
    static let good = adaptive(light: 0x1E7B34, dark: 0x30D158)
    /// A little short on sleep.
    static let fair = adaptive(light: 0x8A6100, dark: 0xFFD60A)
    /// Short on sleep.
    static let low = adaptive(light: 0xC0262D, dark: 0xFF6961)
    /// Contributions that lowered the number, and photos that did not count. Orange rather
    /// than red, so a single sign is never read as an alarm.
    static let caution = adaptive(light: 0xB24A00, dark: 0xFF9F0A)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
