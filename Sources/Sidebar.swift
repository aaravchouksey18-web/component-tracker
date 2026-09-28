import SwiftUI

// MARK: - Sidebar

struct Sidebar: View {
    @EnvironmentObject private var store: InventoryStore
    @EnvironmentObject private var pi: PiSyncController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("COMPONENT TRACKER")
                    .font(.ui(11, .bold))
                    .tracking(1.4)
                    .foregroundStyle(Palette.textHi)
                Text("\(store.totalUnits) units on hand")
                    .font(.mono(10))
                    .foregroundStyle(Palette.textLow)
            }
            .padding(.horizontal, Metrics.pad)
            .padding(.top, 6)
            .padding(.bottom, 16)

            VStack(spacing: 2) {
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
                    .padding(.top, 20)
                    .padding(.bottom, 7)

                ScrollView {
                    VStack(spacing: 1) {
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

            Divider().overlay(Palette.lineSoft)
            PiStatusBar()
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.bg)
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

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: section.icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(active ? Palette.textHi : Palette.textMid)
                    .frame(width: 16)
                Text(section.label)
                    .font(.ui(12, active ? .semibold : .regular))
                    .foregroundStyle(active ? Palette.textHi : Palette.textMid)
                Spacer(minLength: 4)
                if let badge {
                    Text("\(badge)")
                        .font(.mono(9, .semibold))
                        .foregroundStyle(section == .outOfStock ? Palette.danger : Palette.warn)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Capsule().fill((section == .outOfStock ? Palette.danger : Palette.warn).opacity(0.15)))
                }
            }
            .padding(.horizontal, Metrics.pad)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: Metrics.cornerSm, style: .continuous)
                    .fill(active ? Palette.panelHi : .clear)
            )
            .overlay(alignment: .leading) {
                if active {
                    Capsule().fill(Palette.accent).frame(width: 2, height: 14)
                }
            }
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
            HStack(spacing: 8) {
                Circle()
                    .fill(swiftUIColor(for: name))
                    .frame(width: 5, height: 5)
                    .opacity(active ? 1 : 0.7)
                Text(name)
                    .font(.ui(11, active ? .semibold : .regular))
                    .foregroundStyle(active ? Palette.textHi : Palette.textMid)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(count)")
                    .font(.mono(10))
                    .foregroundStyle(Palette.textLow)
            }
            .padding(.horizontal, Metrics.pad)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(active ? Palette.panelHi : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct PiStatusBar: View {
    @EnvironmentObject private var pi: PiSyncController

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(pi.config.enabled ? Palette.good : Palette.textLow)
                .frame(width: 5, height: 5)
            VStack(alignment: .leading, spacing: 1) {
                Text(pi.config.enabled ? "Pi sync on" : "Pi sync off")
                    .font(.ui(10, .medium))
                    .foregroundStyle(Palette.textMid)
                if pi.config.enabled {
                    Text(pi.config.displayString)
                        .font(.mono(9))
                        .foregroundStyle(Palette.textLow)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Metrics.pad)
        .padding(.top, 10)
    }
}
