import SwiftUI

// MARK: - Sidebar

/// Reads as a command panel rather than a navigation list. The one idea worth
/// naming: a selected row is drawn in *inverse video* — accent fill, background
/// text — because that is what selection looks like in a terminal, and it
/// replaces the coloured-pill-and-left-bar treatment with something that
/// belongs to the rest of this design instead of fighting it.
struct Sidebar: View {
    @EnvironmentObject private var store: InventoryStore
    @EnvironmentObject private var pi: PiSyncController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            VStack(spacing: 0) {
                ForEach(Section.allCases) { s in
                    SidebarRow(section: s,
                               active: store.section == s,
                               badge: badge(for: s),
                               action: {
                                   store.section = s
                                   if s != .categories { store.categoryFilter = nil }
                               })
                }
            }

            if !store.categoryCounts.isEmpty {
                SectionLabel("By category")
                    .padding(.horizontal, Metrics.pad)
                    .padding(.top, 18)
                    .padding(.bottom, 6)

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(store.categoryCounts, id: \.0) { pair in
                            CategoryRow(name: pair.0,
                                        count: pair.1,
                                        active: store.categoryFilter == pair.0 &&
                                                store.section == .categories) {
                                if store.section == .categories && store.categoryFilter == pair.0 {
                                    store.section = .all
                                    store.categoryFilter = nil
                                } else {
                                    store.section = .categories
                                    store.categoryFilter = pair.0
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 210)
            }

            Spacer(minLength: 0)
            Rule()
            ThemeSwitcher()
            Rule()
            PiStatusBar()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            ZStack(alignment: .topLeading) {
                Palette.bg
                if SkinController.skin.gridBackdrop { GridBackdrop() }
            }
        }
    }

    /// A shell prompt, then the live count. The `$` is the whole personality of
    /// this header in four pixels.
    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("component-tracker")
                .font(.ui(.title, .bold))
                .tracking(0.8)
                .foregroundStyle(Palette.textHi)
            HStack(spacing: 5) {
                Text(SkinController.skin.id == "swiss" ? "—" : "$")
                    .font(.mono(.small, .bold))
                    .foregroundStyle(Palette.accent)
                Text("\(store.totalUnits) units on hand")
                    .font(.mono(.small))
                    .foregroundStyle(Palette.textLow)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Metrics.pad)
        .padding(.top, 8)
        .padding(.bottom, 14)
    }

    private func badge(for s: Section) -> Int? {
        switch s {
        case .all:        return nil
        case .lowStock:   let n = store.lowStockCount;  return n > 0 ? n : nil
        case .outOfStock: let n = store.outOfStockCount; return n > 0 ? n : nil
        default:          return nil
        }
    }
}

struct SidebarRow: View {
    var section: Section
    var active: Bool
    var badge: Int?
    var action: () -> Void

    private var badgeTint: Color {
        section == .outOfStock ? Palette.danger : Palette.warn
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                // The prompt. Reserve the slot on every row so labels stay in
                // one column whether or not anything is selected.
                Text("›")
                    .font(.mono(.body, .bold))
                    .foregroundStyle(active ? Palette.bg : .clear)
                    .frame(width: 12)
                Image(systemName: section.icon)
                    .font(.ui(.body, .regular))
                    .foregroundStyle(active ? Palette.bg : Palette.textLow)
                    .frame(width: 18)
                Text(section.label)
                    .font(.ui(.body, active ? .bold : .regular))
                    .foregroundStyle(active ? Palette.bg : Palette.textMid)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if let badge {
                    // Bracketed count — the terminal's stand-in for a badge.
                    Text("[\(badge)]")
                        .font(.mono(.small, .semibold))
                        .foregroundStyle(active ? Palette.bg : badgeTint)
                }
            }
            .padding(.horizontal, Metrics.pad)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(active ? Palette.accent : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct CategoryRow: View {
    var name: String
    var count: Int
    var active: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Text("›")
                    .font(.mono(.body, .bold))
                    .foregroundStyle(active ? Palette.bg : .clear)
                    .frame(width: 12)
                // A 4pt block in the category colour, not a dot. Square
                // because everything else here is square.
                Rectangle()
                    .fill(swiftUIColor(for: name))
                    .frame(width: 4, height: 9)
                    .opacity(active ? 1 : 0.65)
                Text(name)
                    .font(.ui(.small, active ? .bold : .regular))
                    .foregroundStyle(active ? Palette.bg : Palette.textMid)
                    .lineLimit(1)
                    .padding(.leading, 6)
                Spacer(minLength: 6)
                Text("\(count)")
                    .font(.mono(.small))
                    .foregroundStyle(active ? Palette.bg : Palette.textLow)
            }
            .padding(.horizontal, Metrics.pad)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(active ? Palette.accent : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Live skin and scheme switching, in the place you would look for it.
///
/// Pinned to the bottom of the sidebar rather than buried in Settings, because
/// a skin is the first thing you want to change when a skin is wrong — and
/// burying it means the next attempt at picking one starts from the app you
/// already dislike.
///
/// Each row carries a **live swatch** rather than a name only: the swatch is
/// drawn with that skin's own palette, so you see what you are choosing before
/// you click it, and the difference between three designs that share a name
/// ("dark", "dark") is visible rather than described.
struct ThemeSwitcher: View {
    @EnvironmentObject private var store: InventoryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Themes")
                .padding(.horizontal, Metrics.pad)
                .padding(.top, 10)
                .padding(.bottom, 5)

            SkinPicker()
            // Same fixed width as Settings so the two halves are square-ish,
            // not 210pt-wide oblongs.
            SchemePair(fixedWidth: 84)
                .padding(.horizontal, Metrics.pad)
                .padding(.top, 8)
        }
        .padding(.bottom, 8)
    }
}

struct PiStatusBar: View {
    @EnvironmentObject private var pi: PiSyncController

    var body: some View {
        HStack(spacing: 6) {
            // Block indicator rather than a dot: a blinking block is what a
            // terminal shows for "waiting", and this row is a waiting indicator.
            Rectangle()
                .fill(pi.config.enabled ? Palette.good : Palette.textLow)
                .frame(width: 5, height: 5)
            Text(pi.config.enabled ? "PI SYNC" : "PI SYNC OFF")
                .font(.mono(.label, .semibold))
                .tracking(0.5)
                .foregroundStyle(pi.config.enabled ? Palette.good : Palette.textLow)
            if pi.config.enabled {
                Text(pi.config.displayString)
                    .font(.mono(.label))
                    .foregroundStyle(Palette.textLow)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Metrics.pad)
        .padding(.vertical, 8)
    }
}
