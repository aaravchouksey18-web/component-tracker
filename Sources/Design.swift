import SwiftUI

// MARK: - Currency

/// Single source of truth for money. Nothing else in the app hardcodes a
/// currency symbol or a grouping rule — change `code` here and the whole app
/// (table, cards, dashboard, editor, exports) follows.
enum Money {
    static let code = "INR"
    static let symbol = "₹"

    /// Indian digit grouping: 12,34,567 — not 1,234,567. The last three digits
    /// are grouped, then pairs, which is how the number is actually read.
    private static let indian: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_IN")
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.usesGroupingSeparator = true
        return f
    }()

    /// Full precision — ₹1,23,456.78
    static func exact(_ v: Double) -> String {
        symbol + (indian.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v))
    }

    /// Compact for tight spaces, using lakh/crore the way large numbers are
    /// actually spoken: ₹999.00 · ₹12.3K · ₹1.2L · ₹1.2Cr
    static func compact(_ v: Double) -> String {
        let a = abs(v)
        let body: String
        switch a {
        case ..<1_000:      body = String(format: "%.2f", a)
        case ..<100_000:    body = String(format: "%.1fK", a / 1_000)
        case ..<10_000_000: body = String(format: "%.1fL", a / 100_000)
        default:            body = String(format: "%.1fCr", a / 10_000_000)
        }
        return (v < 0 ? "-" : "") + symbol + body
    }
}

// MARK: - Theme

/// One colour set. Two of them ship: a phosphor-on-black terminal, and the
/// same instrument read as dark ink on paper for daylight.
///
/// Both are built from the same six-part structure, because that structure is
/// what makes the app look like a ledger rather than a consumer product:
/// two background steps, one raised step, two rule weights, three text steps,
/// and four status colours that mean exactly one thing each.
struct Theme {
    var bg, surface, raised: Color
    var rule, ruleSoft: Color
    var textHi, textMid, textLow: Color
    var accent, good, warn, danger: Color
    var isDark: Bool

    static let dark = Theme(
        bg:      Color(hex: 0x0A0B0C),
        surface: Color(hex: 0x111315),
        raised:  Color(hex: 0x191C1F),
        rule:    Color(hex: 0x24282C),
        ruleSoft:Color(hex: 0x191C20),
        textHi:  Color(hex: 0xD7DBDF),
        textMid: Color(hex: 0x8B9298),
        textLow: Color(hex: 0x5C6369),
        accent:  Color(hex: 0xFFB000),   // amber phosphor
        good:    Color(hex: 0x2FD07A),
        warn:    Color(hex: 0xFFB000),
        danger:  Color(hex: 0xFF4B3E),
        isDark:  true
    )

    /// The light set is not an inversion. Status colours are darkened rather
    /// than lightened, because #FF4B3E on paper has almost no contrast and a
    /// red that has to be re-tuned is a red that will drift the next time
    /// someone tweaks it.
    static let light = Theme(
        bg:      Color(hex: 0xF4F3EF),
        surface: Color(hex: 0xEAE9E3),
        raised:  Color(hex: 0xFFFFFF),
        rule:    Color(hex: 0xCBC9C0),
        ruleSoft:Color(hex: 0xE0DED6),
        textHi:  Color(hex: 0x14150F),
        textMid: Color(hex: 0x5A5C55),
        textLow: Color(hex: 0x8A8C84),
        accent:  Color(hex: 0xA66400),
        good:    Color(hex: 0x0B7A3E),
        warn:    Color(hex: 0x9A6200),
        danger:  Color(hex: 0xBE2318),
        isDark:  false
    )
}

extension Color {
    /// 0xRRGGBB. Written out rather than using `.init(.sRGB:)` so a hex in a
    /// theme literal above is copy-pasteable from any colour picker.
    init(hex: UInt32) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >>  8) & 0xFF) / 255,
                  blue:  Double( hex        & 0xFF) / 255,
                  opacity: 1)
    }
}

/// The live theme. Read through `Palette`, never touched directly.
///
/// A stored static rather than an environment value: every control in this app
/// already reads `Palette` by name, and threading a theme through the
/// environment would mean touching 40 call sites to change a colour. The store
/// republishes on toggle, so anything observing it re-renders and re-reads this.
enum ThemeController {
    static var current: Theme = Theme.dark

    static func set(dark: Bool) { current = dark ? .dark : .light }
}

/// Kept as named accessors rather than `Theme` fields so the ~40 existing
/// `Palette.x` call sites are unchanged. Every value is a computed read, so a
/// theme switch costs one assignment and no call-site edits.
enum Palette {
    static var bg: Color      { ThemeController.current.bg }
    static var panel: Color   { ThemeController.current.surface }
    static var panelHi: Color { ThemeController.current.raised }
    static var line: Color    { ThemeController.current.rule }
    static var lineSoft: Color{ ThemeController.current.ruleSoft }
    static var textHi: Color  { ThemeController.current.textHi }
    static var textMid: Color { ThemeController.current.textMid }
    static var textLow: Color { ThemeController.current.textLow }
    static var accent: Color  { ThemeController.current.accent }
    static var good: Color    { ThemeController.current.good }
    static var warn: Color    { ThemeController.current.warn }
    static var danger: Color  { ThemeController.current.danger }
}

// MARK: - Category colour mapping

func swiftUIColor(for category: String) -> Color {
    switch Categories.tint(for: category) {
    case .teal:   return Color(hex: 0x2AA198)
    case .amber:  return Color(hex: 0xCB9B2E)
    case .violet: return Color(hex: 0x7C6BB0)
    case .blue:   return Color(hex: 0x4A7FC1)
    case .green:  return Color(hex: 0x3A9E5C)
    case .orange: return Color(hex: 0xC2683A)
    case .gray:   return Palette.textMid
    }
}

// MARK: - Metrics

enum Metrics {
    /// Terminal UI has no rounded corners. These are retained because call
    /// sites still reference them, and the honest value is zero.
    static let corner: CGFloat = 0
    static let cornerSm: CGFloat = 0
    /// Tighter than a consumer layout on purpose. Information density is the
    /// point of the aesthetic, not a side effect of it.
    static let pad: CGFloat = 14
    /// The one structural rule width. Everything divides by this.
    static let rule: CGFloat = 1
}

// MARK: - Fonts

/// Monospace everywhere, and that is not a nostalgia costume — it is the
/// mechanism. Digits in a proportional face do not line up in a column, and a
/// stock ledger whose numbers do not align is a worse ledger.
///
/// Uses the system monospaced design rather than a named face on purpose: a
/// `.custom("Some Family-Bold")` that CoreText cannot resolve falls back
/// silently and renders in the wrong typeface with no error anywhere.
extension Font {
    static func mono(_ size: CGFloat, _ w: Font.Weight = .regular) -> Font {
        .system(size: size, weight: w, design: .monospaced)
    }
    /// Kept as a separate name so the UI/mono distinction survives as a hook,
    /// even though this theme sets both.
    static func ui(_ size: CGFloat, _ w: Font.Weight = .regular) -> Font {
        .system(size: size, weight: w, design: .monospaced)
    }

    /// Bloomberg's field label: small, bold, widely tracked caps. This is the
    /// single typographic move that reads as "instrument" rather than "app".
    static func field(_ size: CGFloat = 9) -> Font {
        .system(size: size, weight: .semibold, design: .monospaced)
    }
}

// MARK: - Hairlines

/// A 1px rule. Wrapped in a view rather than sprinkled as `.frame(height: 1)`
/// so the width is decided in one place.
struct Rule: View {
    var axis: Axis = .horizontal
    var weight: Color? = nil
    var body: some View {
        Rectangle()
            .fill(weight ?? Palette.line)
            .frame(width: axis == .vertical ? Metrics.rule : nil,
                   height: axis == .horizontal ? Metrics.rule : nil)
    }
}

// MARK: - Controls

/// LAYOUT CONTRACT, enforced by `lint.sh`:
///
/// Every shared component below must lay out *rigidly*. No `Spacer()`, no
/// greedy `Rectangle()`/`Color.clear`, no `.frame(maxWidth: .infinity)` inside
/// an `HStack` that also holds other content. A flexible child inside a shared
/// component changes the width negotiation of whatever embeds it, and the
/// symptom shows up in a different component entirely.
///
/// This is not hypothetical: an earlier revision made `SectionLabel` a row of
/// `Text` plus a greedy `Rectangle`, and the rule it drew competed with the
/// `Spacer` in the card footer — so the "IN STOCK" and "VALUE" captions drifted
/// out of alignment with the figures underneath them. The check exists because
/// that bug shipped past a clean test run and a clean render log.
struct GhostButton: View {
    var title: String
    var systemImage: String? = nil
    var prominent: Bool = false
    var enabled: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 10, weight: .medium))
                }
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(0.6)
            }
            .foregroundStyle(prominent ? Palette.bg : Palette.textHi)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            // Terminal buttons are outlined and hollow, not filled. The
            // prominent one fills with accent and flips to background-coloured
            // text — which is exactly what inverse video is.
            .background(prominent ? Palette.accent : Color.clear)
            .overlay(Rectangle().strokeBorder(prominent ? Palette.accent : Palette.line,
                                             lineWidth: Metrics.rule))
            .opacity(enabled ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// Bloomberg field label: caps, tracked, dim. Deliberately *not* a row with a
/// rule after the text — see the layout contract above.
struct SectionLabel: View {
    var text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.field())
            .tracking(0.9)
            .foregroundStyle(Palette.textLow)
            .fixedSize()
    }
}

/// Outlined tag. Terminal equivalents are square and boxed; a capsule would put
/// this design back in the consumer-product drawer.
struct Pill: View {
    var text: String
    /// Optional rather than `= Palette.textMid`. A default argument is
    /// evaluated at the *call site*, which is a construction-time read of a
    /// global — it captures whatever the theme was when the caller built the
    /// view, not when the body runs. In the app that happens to coincide
    /// (the tree is rebuilt after the store publishes), but it is one refactor
    /// away from silently keeping stale colours, and the offscreen renderer
    /// tripped over exactly this. Resolving nil inside `body` cannot drift.
    var tint: Color? = nil
    var filled: Bool = false

    var body: some View {
        let c = tint ?? Palette.textMid
        Text(text.uppercased())
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .tracking(0.5)
            .foregroundStyle(filled ? Palette.bg : c)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .overlay(Rectangle().strokeBorder(filled ? c : c.opacity(0.45),
                                             lineWidth: Metrics.rule))
    }
}

/// A readout, not a card: label, figure, caption, separated by rules rather
/// than by padding and a background block.
struct StatTile: View {
    var label: String
    var value: String
    var sub: String? = nil
    /// See `Pill.tint` — resolved in `body`, never as a default argument, so a
    /// construction-time theme read cannot freeze the colour.
    var tint: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            SectionLabel(label)
            Text(value)
                .font(.mono(20, .medium))
                .foregroundStyle(tint ?? Palette.textHi)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Rule(weight: Palette.lineSoft)
            if let sub {
                Text(sub.uppercased())
                    .font(.system(size: 9, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(Palette.textLow)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .overlay(Rectangle().strokeBorder(Palette.line, lineWidth: Metrics.rule))
    }
}

struct EmptyStateView: View {
    var systemImage: String
    var title: String
    var message: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Palette.textLow)
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(Palette.textHi)
            Text(message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Palette.textMid)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
