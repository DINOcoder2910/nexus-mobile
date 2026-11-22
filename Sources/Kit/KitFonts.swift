import SwiftUI
import UIKit
import CoreText

/// The kit's type, on the iPad and the iPhone as on the laptop: Gabarito for titles and figures, Onest for everything else.
/// The fonts are static cuts of the two OFL variable fonts (Resources/Fonts, made from Google Fonts' `Onest[wght]` and
/// `Gabarito[wght]` with fontTools' instancer), registered for the app's own process at launch, so no Info.plist list is needed.
/// If a font is missing, `.custom` falls back to the system font: nothing breaks, it only looks like before.
enum KitFonts {
    private static var registered = false

    /// Registers the fonts and gives UIKit's bars the kit's type. Once, before the first window.
    static func register() {
        guard !registered else { return }
        registered = true
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? []
        for u in urls { CTFontManagerRegisterFontsForURL(u as CFURL, .process, nil) }
        appearance()
    }

    /// Navigation titles (large in Gabarito), segmented controls and the iPhone's tab bar in Onest.
    private static func appearance() {
        let nav = UINavigationBar.appearance()
        nav.largeTitleTextAttributes = [.font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: UIFont.nx(34, .bold, display: true))]
        nav.titleTextAttributes = [.font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: UIFont.nx(17, .semibold))]
        UISegmentedControl.appearance().setTitleTextAttributes([.font: UIFont.nx(13, .medium)], for: .normal)
        UISegmentedControl.appearance().setTitleTextAttributes([.font: UIFont.nx(13, .semibold)], for: .selected)
        UITabBarItem.appearance().setTitleTextAttributes([.font: UIFont.nx(10, .medium)], for: .normal)
    }

    /// A text style's size, whether it is a title (Gabarito) and its own weight, as iOS sets them at the default text size.
    static func spec(_ style: Font.TextStyle) -> (size: CGFloat, display: Bool, weight: Font.Weight) {
        switch style {
        case .largeTitle: return (34, true, .bold)
        case .title: return (28, true, .bold)
        case .title2: return (22, true, .semibold)
        case .title3: return (20, true, .semibold)
        case .headline: return (17, false, .semibold)
        case .body: return (17, false, .regular)
        case .callout: return (16, false, .regular)
        case .subheadline: return (15, false, .regular)
        case .footnote: return (13, false, .regular)
        case .caption: return (12, false, .regular)
        case .caption2: return (11, false, .regular)
        default: return (17, false, .regular)
        }
    }

    /// The cut for a weight: Onest has Regular, Medium, SemiBold and Bold; Gabarito SemiBold and Bold.
    static func name(display: Bool, weight: Font.Weight) -> String {
        let bold = weight == .bold || weight == .heavy || weight == .black
        if display { return bold ? "Gabarito-Bold" : "Gabarito-SemiBold" }
        if bold { return "Onest-Bold" }
        if weight == .semibold { return "Onest-SemiBold" }
        if weight == .medium { return "Onest-Medium" }
        return "Onest-Regular"
    }

    static func name(display: Bool, uiWeight w: UIFont.Weight) -> String {
        if w.rawValue >= UIFont.Weight.bold.rawValue { return name(display: display, weight: .bold) }
        if w.rawValue >= UIFont.Weight.semibold.rawValue { return name(display: display, weight: .semibold) }
        if w.rawValue >= UIFont.Weight.medium.rawValue { return name(display: display, weight: .medium) }
        return name(display: display, weight: .regular)
    }
}

extension Font {
    /// A text style in the kit's type, at its own weight; it follows Dynamic Type as the system's does.
    static func nx(_ style: Font.TextStyle) -> Font {
        let s = KitFonts.spec(style)
        return .custom(KitFonts.name(display: s.display, weight: s.weight), size: s.size, relativeTo: style)
    }

    /// A text style in the kit's type at another weight.
    static func nx(_ style: Font.TextStyle, _ weight: Font.Weight) -> Font {
        let s = KitFonts.spec(style)
        return .custom(KitFonts.name(display: s.display, weight: weight), size: s.size, relativeTo: style)
    }

    /// A fixed size (a figure, a big number) in the kit's type; `display` is Gabarito.
    static func nx(size: CGFloat, _ weight: Font.Weight = .regular, display: Bool = false, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(KitFonts.name(display: display, weight: weight), size: size, relativeTo: style)
    }
}

extension UIFont {
    /// The kit's type for UIKit (the board's bar, the quick ring); the system font if the font isn't there.
    static func nx(_ size: CGFloat, _ weight: UIFont.Weight = .regular, display: Bool = false) -> UIFont {
        UIFont(name: KitFonts.name(display: display, uiWeight: weight), size: size) ?? .systemFont(ofSize: size, weight: weight)
    }
}
