import SwiftUI
import UIKit

/// The Nexus kit, the same on the laptop, the iPad and the iPhone (the new-look picks, Nov 20 2026; project files new-look/mockups/kit.png):
/// - surfaces are told apart by tone, not lines: page, rests (a card, the sidebar), hover and chips, selected, one line where a line
///   is needed, and the board's paper;
/// - colour is spent in four places only: the accent (green, one primary action), Claude (blue), due and partly (amber), late and
///   delete (red), plus the key date's gold; a subject's own colour is the thread that connects it everywhere;
/// - type: Gabarito for titles and figures, Onest for the rest (KitFonts);
/// - shape: radii 14 for surfaces, 10 for controls, 8 for chips, 12 for menus, on a 4 pt grid; one spring for everything that moves,
///   and nothing moves on its own.
enum Kit {
    // MARK: surfaces

    static let page = Theme.dynamic(light: "#FFFFFF", dark: "#0F0F0F")
    static let rests = Theme.dynamic(light: "#F6F6F3", dark: "#171717")
    static let hover = Theme.dynamic(light: "#EEEEEA", dark: "#202020")
    static let selected = Theme.dynamic(light: "#E4E4DF", dark: "#2B2B2B")
    static let line = Theme.dynamic(light: "#E7E7E2", dark: "#272727")
    static let paper = Theme.dynamic(light: "#FFFFFF", dark: "#191A1F")

    // MARK: words

    static let ink = Theme.dynamic(light: "#1C1C1A", dark: "#ECECE8")
    static let muted = Theme.dynamic(light: "#6B6B66", dark: "#A9A9A3")
    static let faint = Theme.dynamic(light: "#9A9A94", dark: "#7A7A75")

    // MARK: colour's washes (a chip's or a done unit's background)

    static let accentWash = Theme.dynamic(light: "#E2F1E8", dark: "#163325")
    static let warnWash = Theme.dynamic(light: "#F8ECDC", dark: "#3A2B16")
    static let lateWash = Theme.dynamic(light: "#FBE5E3", dark: "#3D1C1A")
    /// The default ink: navy, the first of the pen's colours in the new look.
    static let defaultInk = "#1D2650"

    // MARK: shape

    static let surfaceRadius: CGFloat = 14
    static let controlRadius: CGFloat = 10
    static let chipRadius: CGFloat = 8
    static let menuRadius: CGFloat = 12

    // MARK: motion

    /// The one spring: everything that moves moves with it.
    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.8)
    /// A quicker one, for a press or a small change of state.
    static let snap = Animation.spring(response: 0.28, dampingFraction: 0.82)

    /// The same colours for UIKit (the board's bar, the quick ring).
    enum ui {
        static let page = Theme.uiDynamic(light: "#FFFFFF", dark: "#0F0F0F")
        static let rests = Theme.uiDynamic(light: "#F6F6F3", dark: "#171717")
        static let hover = Theme.uiDynamic(light: "#EEEEEA", dark: "#202020")
        static let selected = Theme.uiDynamic(light: "#E4E4DF", dark: "#2B2B2B")
        static let line = Theme.uiDynamic(light: "#E7E7E2", dark: "#272727")
        static let ink = Theme.uiDynamic(light: "#1C1C1A", dark: "#ECECE8")
        static let muted = Theme.uiDynamic(light: "#6B6B66", dark: "#A9A9A3")
        static let accent = Theme.uiDynamic(light: "#0F7A49", dark: "#4FD28F")
        static let accentWash = Theme.uiDynamic(light: "#E2F1E8", dark: "#163325")
    }
}

extension Theme {
    /// A light and dark pair as a UIColor.
    static func uiDynamic(light: String, dark: String) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? uiColor(dark) : uiColor(light) }
    }
}

/// The kit's buttons: the accent for the one primary action, a tone for the rest, Claude's blue tint for anything Claude does.
struct KitButtonStyle: ButtonStyle {
    enum Kind { case primary, tone, claude, plain }
    var kind: Kind = .tone
    var small = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.nx(small ? .subheadline : .callout, .medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, small ? 10 : 14)
            .frame(minHeight: small ? 30 : 36)
            .background(background, in: RoundedRectangle(cornerRadius: Kit.controlRadius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Kit.snap, value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary: return .white
        case .tone, .plain: return Kit.ink
        case .claude: return Theme.claude
        }
    }

    private var background: Color {
        switch kind {
        case .primary: return Theme.accent
        case .tone: return Kit.hover
        case .claude: return Theme.claudeTint
        case .plain: return .clear
        }
    }
}

extension ButtonStyle where Self == KitButtonStyle {
    static var kit: KitButtonStyle { KitButtonStyle() }
    static var kitPrimary: KitButtonStyle { KitButtonStyle(kind: .primary) }
    static var kitClaude: KitButtonStyle { KitButtonStyle(kind: .claude) }
}

extension View {
    /// A surface at rest: the kit's tone and radius, no line.
    func kitSurface(_ fill: Color = Kit.rests, radius: CGFloat = Kit.surfaceRadius) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// The kit's switch (Week | Month, Draw | Insert | View): the picked one lifts onto the page's tone, the rest rest on the switch.
struct KitSwitch<T: Hashable>: View {
    let items: [(T, String)]
    @Binding var selection: T
    @Namespace private var lift

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items.indices, id: \.self) { i in
                let value = items[i].0, title = items[i].1
                let on = value == selection
                Button {
                    withAnimation(Kit.spring) { selection = value }
                } label: {
                    Text(title)
                        .font(.nx(.subheadline, on ? .semibold : .regular))
                        .foregroundStyle(on ? Kit.ink : Kit.muted)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Kit.page)
                                    .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                                    .matchedGeometryEffect(id: "lift", in: lift)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Kit.hover, in: RoundedRectangle(cornerRadius: Kit.controlRadius, style: .continuous))
    }
}
