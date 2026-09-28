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

// MARK: - Category colour mapping

func swiftUIColor(for category: String) -> Color {
    switch Categories.tint(for: category) {
    case .teal:   return Color(red: 0.31, green: 0.80, blue: 0.78)
    case .amber:  return Color(red: 0.98, green: 0.75, blue: 0.36)
    case .violet: return Color(red: 0.68, green: 0.60, blue: 0.96)
    case .blue:   return Color(red: 0.47, green: 0.68, blue: 0.98)
    case .green:  return Color(red: 0.44, green: 0.83, blue: 0.58)
    case .orange: return Color(red: 0.96, green: 0.62, blue: 0.42)
    case .gray:   return Palette.textMid
    }
}

// MARK: - Minimalist black design system

enum Palette {
    static let bg          = Color(red: 0.039, green: 0.039, blue: 0.043)   // #0A0A0B
    static let panel       = Color(red: 0.075, green: 0.075, blue: 0.082)   // #131314
    static let panelHi     = Color(red: 0.110, green: 0.110, blue: 0.118)   // #1C1C1E
    static let line        = Color(red: 0.165, green: 0.165, blue: 0.175)   // #2A2A2D
    static let lineSoft    = Color(red: 0.125, green: 0.125, blue: 0.133)   // #202023
    static let textHi      = Color(red: 0.960, green: 0.960, blue: 0.965)
    static let textMid     = Color(red: 0.560, green: 0.560, blue: 0.585)
    static let textLow     = Color(red: 0.380, green: 0.380, blue: 0.400)
    static let accent      = Color(red: 1.000, green: 1.000, blue: 1.000)
    static let warn        = Color(red: 0.980, green: 0.702, blue: 0.231)   // amber - low stock
    static let danger      = Color(red: 0.945, green: 0.325, blue: 0.325)   // red   - out
    static let good        = Color(red: 0.290, green: 0.780, blue: 0.549)
}

enum Metrics {
    static let corner: CGFloat = 10
    static let cornerSm: CGFloat = 7
    static let pad: CGFloat = 16
}

extension Font {
    static func mono(_ size: CGFloat, _ w: Font.Weight = .regular) -> Font {
        .system(size: size, weight: w, design: .monospaced)
    }
    static func ui(_ size: CGFloat, _ w: Font.Weight = .regular) -> Font {
        .system(size: size, weight: w)
    }
}

// MARK: - Reusable chrome

struct PanelBackground: ViewModifier {
    var radius: CGFloat = Metrics.corner
    var fill: Color = Palette.panel
    var stroke: Color = Palette.lineSoft
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(stroke, lineWidth: 1)
            )
    }
}

extension View {
    func panel(radius: CGFloat = Metrics.corner,
               fill: Color = Palette.panel,
               stroke: Color = Palette.lineSoft) -> some View {
        modifier(PanelBackground(radius: radius, fill: fill, stroke: stroke))
    }
}

/// Minimal primary button
struct GhostButton: View {
    var title: String
    var systemImage: String? = nil
    var prominent: Bool = false
    var enabled: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 11, weight: .semibold))
                }
                Text(title).font(.ui(12, .medium))
            }
            .foregroundStyle(prominent ? Color.black : Palette.textHi)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: Metrics.cornerSm, style: .continuous)
                    .fill(prominent ? Palette.accent : Palette.panelHi)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.cornerSm, style: .continuous)
                    .strokeBorder(prominent ? .clear : Palette.line, lineWidth: 1)
            )
            .opacity(enabled ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// Small uppercase section label
struct SectionLabel: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.ui(10, .semibold))
            .tracking(0.9)
            .foregroundStyle(Palette.textLow)
    }
}

/// Rounded category pill
struct Pill: View {
    var text: String
    var tint: Color = Palette.textMid
    var filled: Bool = false
    var body: some View {
        Text(text.uppercased())
            .font(.ui(9, .semibold))
            .tracking(0.7)
            .foregroundStyle(filled ? Color.black : tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(filled ? tint : tint.opacity(0.13))
            )
            .overlay(
                Capsule().strokeBorder(filled ? .clear : tint.opacity(0.28), lineWidth: 1)
            )
            .lineLimit(1)
    }
}

struct StatTile: View {
    var label: String
    var value: String
    var sub: String? = nil
    var tint: Color = Palette.textHi

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel(label)
            Text(value)
                .font(.mono(24, .medium))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if let sub {
                Text(sub)
                    .font(.ui(10))
                    .foregroundStyle(Palette.textLow)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .panel()
    }
}

struct EmptyStateView: View {
    var systemImage: String
    var title: String
    var message: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Palette.textLow)
            Text(title)
                .font(.ui(15, .medium))
                .foregroundStyle(Palette.textMid)
            Text(message)
                .font(.ui(12))
                .foregroundStyle(Palette.textLow)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
