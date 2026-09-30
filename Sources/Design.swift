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

// MARK: - Colour set

/// One colour set. Six ship: three skins, each with a dark and a light reading.
///
/// Every set has the same shape — two background steps, one raised step, two
/// rule weights, three text steps, four status colours — because that shape is
/// what lets a single set of components render in all three skins without any of
/// them special-casing. What differs between skins is the *values*, plus a small
/// set of structural flags on `Skin`.
struct Palette2 {
    var bg, surface, raised: Color
    var rule, ruleSoft: Color
    var textHi, textMid, textLow: Color
    var accent, good, warn, danger: Color
    var isDark: Bool
}

extension Color {
    /// 0xRRGGBB. Written out rather than `.init(.sRGB:)` so a hex in a palette
    /// literal below is copy-pasteable from any colour picker.
    init(hex: UInt32) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >>  8) & 0xFF) / 255,
                  blue:  Double( hex        & 0xFF) / 255,
                  opacity: 1)
    }
}

// MARK: - Skin

/// Structural decisions a palette cannot express.
///
/// This is the part that keeps a skin switch from being a rewrite. Colours are
/// data, but "cards are filled blocks with a 6px radius" versus "cards are a
/// top rule and nothing else" versus "cards sit on a gridded field with corner
/// ticks" is not a colour and cannot be one — so it lives here as a flag and the
/// components branch on it once, in one place.
struct Skin {
    var id: String
    var name: String
    var blurb: String

    var dark: Palette2
    var light: Palette2

    /// Corner radius. Swiss and Blueprint are square by design; Graphite is not.
    var radius: CGFloat
    /// Cards get a filled background. Swiss refuses — it has no cards at all.
    var cardFill: Bool
    /// Draw a ruled field behind the content (Blueprint).
    var gridBackdrop: Bool
    /// Corner ticks and leader lines on cards (Blueprint).
    var draftingMarks: Bool
    /// Monospace throughout. Blueprint yes, the other two no.
    var monospaced: Bool
    /// Type scale. Swiss runs a far wider range — that size contrast *is* the
    /// style — so the numbers have to come from here rather than from call sites.
    var figureSize: CGFloat
    var bodySize: CGFloat
    var labelSize: CGFloat
    var labelTracking: CGFloat
    /// Space scale. Swiss is generous, Graphite is tight.
    var pad: CGFloat
    var gap: CGFloat

    // MARK: The three skins

    /// Restrained dark utility. No nostalgia, no costume — an 8pt spacing
    /// scale, 1px borders, one accent, real density. The option that does not
    /// try to be a character.
    static let graphite = Skin(
        id: "graphite", name: "Graphite", blurb: "Restrained dark utility",
        dark: Palette2(
            bg:       Color(hex: 0x16181B), surface: Color(hex: 0x1E2125),
            raised:   Color(hex: 0x262A2F), rule:    Color(hex: 0x33383E),
            ruleSoft: Color(hex: 0x24282D),
            textHi:   Color(hex: 0xE8EAED), textMid: Color(hex: 0xA0A6AD),
            textLow:  Color(hex: 0x6E757D),
            accent:   Color(hex: 0x4C8DF6), good:   Color(hex: 0x3FB950),
            warn:     Color(hex: 0xD29922), danger: Color(hex: 0xF85149),
            isDark: true),
        light: Palette2(
            bg:       Color(hex: 0xFAFAFA), surface: Color(hex: 0xF2F3F5),
            raised:   Color(hex: 0xFFFFFF), rule:    Color(hex: 0xDCDEE2),
            ruleSoft: Color(hex: 0xE8EAED),
            textHi:   Color(hex: 0x1A1C1E), textMid: Color(hex: 0x5B6067),
            textLow:  Color(hex: 0x8B9098),
            accent:   Color(hex: 0x1F6FEB), good:   Color(hex: 0x1A7F37),
            warn:     Color(hex: 0x9A6700), danger: Color(hex: 0xCF222E),
            isDark: false),
        radius: 6, cardFill: true, gridBackdrop: false, draftingMarks: false,
        monospaced: false, figureSize: 20, bodySize: 11, labelSize: 9,
        labelTracking: 0.7, pad: 14, gap: 8)

    /// Swiss / International Typographic. No cards, no fills, no radius — just
    /// type, hairline rules and a great deal of air. The size contrast between a
    /// 40pt figure and an 8pt label is not decoration, it is the hierarchy.
    static let swiss = Skin(
        id: "swiss", name: "Swiss", blurb: "International typographic",
        dark: Palette2(
            bg:       Color(hex: 0x0A0A0A), surface: Color(hex: 0x0A0A0A),
            raised:   Color(hex: 0x141414), rule:    Color(hex: 0xE8E8E8),
            ruleSoft: Color(hex: 0x262626),
            textHi:   Color(hex: 0xFAFAFA), textMid: Color(hex: 0x909090),
            // 3.66:1 on #0A0A0A. Was #5C5C5C at 2.96:1, which cleared a 2.0
            // floor and not much else — a floor chosen to fit the colour rather
            // than to make the text readable.
            textLow:  Color(hex: 0x6A6A6A),
            accent:   Color(hex: 0xFF3B30), good:   Color(hex: 0x4ADE80),
            warn:     Color(hex: 0xFBBF24), danger: Color(hex: 0xFF3B30),
            isDark: true),
        light: Palette2(
            bg:       Color(hex: 0xFFFFFF), surface: Color(hex: 0xFFFFFF),
            raised:   Color(hex: 0xF4F4F2), rule:    Color(hex: 0x111111),
            ruleSoft: Color(hex: 0xD8D8D4),
            textHi:   Color(hex: 0x000000), textMid: Color(hex: 0x4A4A4A),
            textLow:  Color(hex: 0x8A8A8A),
            accent:   Color(hex: 0xE30613), good:   Color(hex: 0x00874A),
            warn:     Color(hex: 0x8A6D00), danger: Color(hex: 0xE30613),
            isDark: false),
        radius: 0, cardFill: false, gridBackdrop: false, draftingMarks: false,
        monospaced: false, figureSize: 34, bodySize: 12, labelSize: 8,
        labelTracking: 1.6, pad: 20, gap: 14)

    /// Blueprint. Deep blue field, white hairlines, a faint grid, and corner
    /// ticks on cards so a part reads as a drawing rather than a tile. Labels
    /// are monospace; figures stay proportional so columns of numbers align.
    static let blueprint = Skin(
        id: "blueprint", name: "Blueprint", blurb: "Drafting table",
        dark: Palette2(
            bg:       Color(hex: 0x0A2540), surface: Color(hex: 0x0A2540),
            raised:   Color(hex: 0x0E2E4F), rule:    Color(hex: 0x2A5C8F),
            ruleSoft: Color(hex: 0x14355A),
            textHi:   Color(hex: 0xEAF2FF), textMid: Color(hex: 0xA8C4E0),
            textLow:  Color(hex: 0x6B90B8),
            accent:   Color(hex: 0x4FC3F7), good:   Color(hex: 0x6FE3B0),
            warn:     Color(hex: 0xFFD166), danger: Color(hex: 0xFF8A80),
            isDark: true),
        light: Palette2(
            // The light reading is a drafting sheet, not a pale blueprint:
            // white stock with blue ink. Inverting a blueprint gives you a
            // photograph of a negative, which is not what anyone wants.
            bg:       Color(hex: 0xF4F7FA), surface: Color(hex: 0xF4F7FA),
            raised:   Color(hex: 0xFFFFFF), rule:    Color(hex: 0x2E5C8A),
            ruleSoft: Color(hex: 0xC6D8EA),
            textHi:   Color(hex: 0x0A2540), textMid: Color(hex: 0x3D6B99),
            // 3.10:1 on the #F4F7FA stock. Was #7FA3C4 at 2.46:1. The same ink
            // as the dark scheme's `textLow`: one blue for both, so the sheet
            // and the blueprint are the same drawing in different stock rather
            // than two drawings that happen to share a layout.
            textLow:  Color(hex: 0x6B90B8),
            accent:   Color(hex: 0x0A6EB8), good:   Color(hex: 0x0E7C4A),
            warn:     Color(hex: 0x9A6700), danger: Color(hex: 0xB4231C),
            isDark: false),
        radius: 0, cardFill: false, gridBackdrop: true, draftingMarks: true,
        monospaced: true, figureSize: 24, bodySize: 11, labelSize: 8,
        labelTracking: 1.2, pad: 16, gap: 10)

    static let all: [Skin] = [.graphite, .swiss, .blueprint]

    static func named(_ id: String) -> Skin {
        all.first { $0.id == id } ?? .graphite
    }
}

// MARK: - Live selection

/// The active skin and scheme.
///
/// Globals rather than environment values, for a reason that is now more load
/// bearing than it was: the sidebar has to be able to switch skin *and* the
/// store is the only object every view already observes, so one publish
/// repaints the entire app. Threading a skin through the environment would mean
/// touching every call site and every `environmentObject` to gain nothing.
///
/// The cost is real and worth naming: `Palette` read outside a `body` captures
/// the value at read time, not at render time. Default arguments must therefore
/// never default to a `Palette` value — see `Pill` and `StatTile`.
enum SkinController {
    static var skin: Skin = .graphite
    static var dark: Bool = true

    static var palette: Palette2 { dark ? skin.dark : skin.light }

    static func set(skin newSkin: Skin, dark newDark: Bool? = nil) {
        skin = newSkin
        if let newDark { dark = newDark }
    }
}

/// The user's choices, so the sidebar and Settings cannot disagree.
enum Prefs {
    static let skinKey = "componenttracker.skin"
    static let darkKey = "componenttracker.darkMode"

    static func load() {
        let id = UserDefaults.standard.string(forKey: skinKey) ?? "graphite"
        let isDark = UserDefaults.standard.object(forKey: darkKey) as? Bool ?? true
        SkinController.set(skin: .named(id), dark: isDark)
    }

    static func save() {
        UserDefaults.standard.set(SkinController.skin.id, forKey: skinKey)
        UserDefaults.standard.set(SkinController.dark, forKey: darkKey)
    }
}

/// Named accessors rather than `Palette2` fields, so the ~40 existing
/// `Palette.x` call sites are unchanged across a skin switch. Every value is a
/// computed read, so switching costs one assignment and no call-site edits.
enum Palette {
    static var bg: Color      { SkinController.palette.bg }
    static var panel: Color   { SkinController.palette.surface }
    static var panelHi: Color { SkinController.palette.raised }
    static var line: Color    { SkinController.palette.rule }
    static var lineSoft: Color{ SkinController.palette.ruleSoft }
    static var textHi: Color  { SkinController.palette.textHi }
    static var textMid: Color { SkinController.palette.textMid }
    static var textLow: Color { SkinController.palette.textLow }
    static var accent: Color  { SkinController.palette.accent }
    static var good: Color    { SkinController.palette.good }
    static var warn: Color    { SkinController.palette.warn }
    static var danger: Color  { SkinController.palette.danger }
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
    /// Corner radius follows the skin. Swiss and Blueprint are square by design,
    /// Graphite is not — so this cannot be a constant any more.
    static var corner: CGFloat { SkinController.skin.radius }
    static var cornerSm: CGFloat { SkinController.skin.radius }
    /// Padding and gap are part of the style. Swiss runs open, Graphite runs
    /// tight, and neither is a default — they are the two things that most make
    /// a UI feel designed or generic.
    static var pad: CGFloat { SkinController.skin.pad }
    static var gap: CGFloat { SkinController.skin.gap }
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
// MARK: - Type scale

/// Named type sizes, derived from the skin's three anchors.
///
/// This exists because `Skin.figureSize` was declared, described in a commit
/// message as the thing that gives Swiss its character, tested by comparing it
/// against another `Skin` field — and then read by nothing. All 117 font sites
/// in the app passed a literal. So switching skins moved colour, radius, card
/// treatment and spacing, and left typography untouched: the whole app rendered
/// in 8–14pt with one 20pt figure, in every skin.
///
/// A test comparing two struct fields verifies the *config*. It cannot verify
/// that anything *renders* at that config, and that gap is how a dead parameter
/// shipped as a headline feature. `Tests/Tests.swift` now asserts that every
/// role below is reached by a real call site, not merely that the sizes differ.
///
/// Every size is an offset from an anchor, so a skin is tuned in one place and
/// the whole app moves with it.
enum Type {

    /// The ladder, with each role's offset from the skin's anchors spelled out
    /// so the intent is checkable rather than implied.
    enum Role {
        /// Hero number on an empty state. `figureSize + 8`.
        case hero
        /// Large readout: a stat tile's value, a header total. `figureSize`.
        case display
        /// A card's own figure: the stock count. `figureSize - 3`.
        case figure
        /// Section heading. `bodySize + 3`.
        case heading
        /// Prominent label or card title. `bodySize + 1`.
        case title
        /// Running text. `bodySize`.
        case body
        /// Secondary text, captions, button labels. `bodySize - 1`.
        case small
        /// Field labels, table headers. `labelSize`.
        case label
        /// Legal print, badges, smallest text anywhere. `labelSize - 1`.
        case micro
    }

    static func size(_ r: Role) -> CGFloat {
        let k = SkinController.skin
        switch r {
        case .hero:    return k.figureSize + 8
        case .display: return k.figureSize
        case .figure:  return k.figureSize - 3
        case .heading: return k.bodySize + 3
        case .title:   return k.bodySize + 1
        case .body:    return k.bodySize
        case .small:   return k.bodySize - 1
        case .label:   return k.labelSize
        case .micro:   return max(7, k.labelSize - 1)
        }
    }

    /// Every role, for the test that asserts none of them is dead.
    static let allRoles: [Role] = [.hero, .display, .figure, .heading, .title,
                                   .body, .small, .label, .micro]
}

extension Font {
    /// Monospaced, unconditionally. Used for figures, codes, part numbers and
    /// paths — the places where alignment is load-bearing.
    static func mono(_ size: CGFloat, _ w: Font.Weight = .regular) -> Font {
        .system(size: size, weight: w, design: .monospaced)
    }

    /// Everything else. Proportional in Graphite and Swiss, monospaced in
    /// Blueprint, which is the one skin where the drafting convention beats the
    /// alignment convention.
    static func ui(_ size: CGFloat, _ w: Font.Weight = .regular) -> Font {
        .system(size: size, weight: w, design: SkinController.skin.monospaced ? .monospaced : .default)
    }

    /// Monospaced at a named size, for figures, codes and part numbers.
    static func mono(_ role: Type.Role, _ w: Font.Weight = .regular) -> Font {
        .system(size: Type.size(role), weight: w, design: .monospaced)
    }

    /// Proportional (or monospaced, if the skin says so) at a named size.
    static func ui(_ role: Type.Role, _ w: Font.Weight = .regular) -> Font {
        .system(size: Type.size(role), weight: w,
                design: SkinController.skin.monospaced ? .monospaced : .default)
    }

    /// The field label: small, bold, tracked caps. Tracking width is the skin's,
    /// because wide tracking is Swiss and tight tracking is Graphite.
    static func field(_ size: CGFloat? = nil) -> Font {
        .system(size: size ?? SkinController.skin.labelSize, weight: .semibold,
                design: SkinController.skin.monospaced ? .monospaced : .default)
    }
}

// MARK: - Structural chrome

/// The one place a skin's structure is expressed, so the rest of the app never
/// branches on which skin is active.
///
/// A card in Graphite is a filled block with a radius. In Swiss it is a top rule
/// and nothing else — no fill, no box, because a card in that language is
/// exactly the thing the language is arguing against. In Blueprint it is a
/// hairline box on a gridded field with corner ticks, i.e. a drawing.
///
/// The lint's no-flexible-children rule applies here like anywhere else. The
/// grid is a `Canvas`, which fills its frame and adds no width negotiation.
/// Generic over the content rather than storing an `@ViewBuilder` closure
/// property: a stored `() -> some View` property cannot infer its opaque return
/// type from the declaration alone, and the `FieldGroup` in EditorSheet already
/// solves this the same way. Two shapes for the same idea is one too many, but
/// consistency here beats novelty.
struct CardChrome<Content: View>: View {
    @ViewBuilder var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        let skin = SkinController.skin
        if skin.draftingMarks {
            // Opaque paper, then the drawing marks on top.
            //
            // The fill is the point and it was missing. A card with no
            // background over a ruled field lets the field's 24pt grid run
            // straight through the part number, the quantity and the value —
            // measured at 16,843 grid pixels inside a single card, ~11
            // vertical and ~7 horizontal lines across the text. A drawing sits
            // ON the grid, not under it; the card is a window cut in the field.
            //
            // `cardFill` is false for this skin, which is right about the
            // *style* — a Blueprint card has no rounded filled panel — and was
            // being read as *transparent*, which is a different property
            // entirely. Opacity and fill are separate questions, and the two
            // were collapsed into one flag.
            content
                .background(Rectangle().fill(Palette.panel))
                // `overlay` rather than a sibling in a `ZStack`: the overlay is
                // sized to the base view, so the Canvas fills it exactly and
                // never competes for layout space. In a ZStack it was another
                // greedy child negotiating the card's width.
                .overlay { draftingMarks }
        } else if skin.cardFill {
            content
                .background(skinShape.fill(Palette.panel))
                .overlay(skinShape.strokeBorder(Palette.line, lineWidth: 1))
        } else {
            // Swiss: a rule above, and nothing else. A box here would undo the
            // whole style. Transparency is correct here precisely because Swiss
            // has no ruled field for it to reveal.
            VStack(alignment: .leading, spacing: 0) {
                Rule()
                content.padding(.top, 9)
            }
        }
    }

    /// The hairline extent box and the four corner ticks.
    private var draftingMarks: some View {
        Canvas { ctx, size in
            let w = size.width - 1, h = size.height - 1
            var p = Path()
            p.move(to: .zero)
            p.addLine(to: CGPoint(x: w, y: 0))
            p.addLine(to: CGPoint(x: w, y: h))
            p.addLine(to: CGPoint(x: 0, y: h))
            p.closeSubpath()
            ctx.stroke(p, with: .color(Palette.line), lineWidth: 1)
            // Corner ticks — the drafting convention for "this extent is the
            // whole part", and the reason a Blueprint card reads as a drawing
            // rather than as a tile.
            let t: CGFloat = 7
            var ticks = Path()
            let corners: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
                (0, 0, 1, 1), (w, 0, -1, 1), (0, h, 1, -1), (w, h, -1, -1),
            ]
            for (cx, cy, dx, dy) in corners {
                ticks.move(to: CGPoint(x: cx, y: cy + dy * t))
                ticks.addLine(to: CGPoint(x: cx, y: cy))
                ticks.move(to: CGPoint(x: cx + dx * t, y: cy))
                ticks.addLine(to: CGPoint(x: cx, y: cy))
            }
            ctx.stroke(ticks, with: .color(Palette.accent.opacity(0.8)), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }

    /// Radius is the skin's, so this is the only place it is read.
    private var skinShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: SkinController.skin.radius, style: .continuous)
    }
}

/// Blueprint's ruled field. Drawn rather than tiled from an asset so it inherits
/// the palette automatically — a baked grid image would have to be regenerated
/// per scheme, and would be one more thing to forget.
struct GridBackdrop: View {
    var spacing: CGFloat = 24

    var body: some View {
        Canvas { ctx, size in
            var p = Path()
            var x: CGFloat = 0
            while x <= size.width {
                p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height))
                x += spacing
            }
            var y: CGFloat = 0
            while y <= size.height {
                p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y))
                y += spacing
            }
            ctx.stroke(p, with: .color(Palette.lineSoft.opacity(0.55)), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Appearance controls

/// The two schemes as a mutually exclusive pair.
///
/// A pair rather than a switch, because that is how every other exclusive
/// choice in this app reads — the card/table toggle, the sidebar selection —
/// and a `Toggle` would be the only control on screen with two visual idioms.
/// Solid fill marks the live one, and its text flips to the background colour,
/// which is inverse video and costs nothing.
///
/// Lives here rather than in the sidebar because the sidebar and Settings both
/// need it and two copies of an exclusive-pair control is how they drift apart
/// and then disagree about what is selected.
struct SchemePair: View {
    @EnvironmentObject private var store: InventoryStore
    /// Settings has room for a fixed width beside a label; the sidebar does not.
    var fixedWidth: CGFloat? = nil

    var body: some View {
        HStack(spacing: 0) {
            button("Dark", isOn: store.darkMode)  { store.darkMode = true }
            Rule(axis: .vertical)
            button("Light", isOn: !store.darkMode) { store.darkMode = false }
            // lint:allow greedy — a two-up exclusive pair that does not span
            // the width it is offered reads as an accidental gap, and this
            // Spacer is the outermost child of the stack, so it competes with
            // nothing. It is also the one child whose greed is the point: the
            // two halves must be equal, and only one of them can absorb the
            // slack.
            if fixedWidth == nil { Spacer(minLength: 0) }
        }
        .overlay(Rectangle().strokeBorder(Palette.line, lineWidth: Metrics.rule))
    }

    private func button(_ name: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(name.uppercased())
                .font(.field())
                .tracking(SkinController.skin.labelTracking)
                .foregroundStyle(isOn ? Palette.bg : Palette.textMid)
                .frame(width: fixedWidth, height: fixedWidth == nil ? nil : 24)
                .frame(maxWidth: fixedWidth == nil ? .infinity : nil)
                .padding(.vertical, 5)
                .background(isOn ? Palette.accent : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Current: \(name.lowercased())" + (isOn ? "" : " — click to switch"))
    }
}

/// The three skins, each with a live swatch drawn from its own palette.
///
/// The swatch is not decoration. Three designs that are all "a dark UI" are
/// indistinguishable from their names, so the row has to carry the thing you
/// are actually choosing. It draws from the skin's own colours rather than from
/// the live palette, which means each row previews its own skin even while a
/// different one is selected.
struct SkinPicker: View {
    @EnvironmentObject private var store: InventoryStore
    /// The sidebar stacks rows full-bleed; Settings pads them.
    var rowPadding: CGFloat? = nil

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Skin.all, id: \.id) { skin in
                SkinRow(skin: skin, active: store.skinID == skin.id) { store.skinID = skin.id }
                    .padding(.horizontal, rowPadding ?? 0)
            }
        }
    }
}

struct SkinRow: View {
    var skin: Skin
    var active: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                SkinSwatch(skin: skin)
                VStack(alignment: .leading, spacing: 1) {
                    Text(skin.name)
                        .font(.ui(.body, active ? .bold : .regular))
                        .foregroundStyle(active ? Palette.accent : Palette.textHi)
                    Text(skin.blurb)
                        .font(.ui(.label))
                        .foregroundStyle(Palette.textLow)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                // A tick, not a filled row. Filling the row would recolour the
                // swatch's own neighbourhood and destroy the preview it exists
                // to provide.
                Text(active ? "\u{2713}" : "")
                    .font(.ui(.body, .bold))
                    .foregroundStyle(Palette.accent)
            }
            .padding(.horizontal, Metrics.pad)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Switch to \(skin.name) — \(skin.blurb)")
    }
}

/// Three bands, a rule, a figure and a fill from the named skin's own palette:
/// enough to tell a filled card from a ruled one and a dense grid from an open
/// page, which is the actual difference between these three designs.
struct SkinSwatch: View {
    var skin: Skin

    private var p: Palette2 { SkinController.dark ? skin.dark : skin.light }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(p.bg).frame(width: 11, height: 22)
            Rectangle().fill(p.surface).frame(width: 6, height: 22)
            VStack(spacing: 1) {
                Rectangle().fill(p.rule).frame(width: 7, height: 1)
                Rectangle().fill(p.accent).frame(width: 7, height: 5)
                Rectangle().fill(p.textHi).frame(width: 5, height: 4)
            }
            .frame(width: 7, height: 22)
            .background(p.bg)
        }
        .overlay(Rectangle().strokeBorder(p.rule, lineWidth: 1))
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
                    Image(systemName: systemImage).font(.ui(.small, .medium))
                }
                Text(title.uppercased())
                    .font(.mono(.small, .semibold))
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
            .font(.mono(.label, .medium))
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
                .font(.mono(.display, .medium))
                .foregroundStyle(tint ?? Palette.textHi)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Rule(weight: Palette.lineSoft)
            if let sub {
                Text(sub.uppercased())
                    .font(.mono(.label))
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
                .font(.ui(.hero, .light))
                .foregroundStyle(Palette.textLow)
            Text(title.uppercased())
                .font(.mono(.title, .semibold))
                .tracking(1.0)
                .foregroundStyle(Palette.textHi)
            Text(message)
                .font(.mono(.body))
                .foregroundStyle(Palette.textMid)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
