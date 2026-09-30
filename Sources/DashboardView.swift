import SwiftUI
import Charts

struct DashboardView: View {
    @EnvironmentObject private var store: InventoryStore

    /// The category chart is backed by Swift Charts. It renders normally in the app;
    /// the flag exists so the offscreen render harness can skip it (ImageRenderer
    /// cannot rasterise a Charts view without a window host).
    var showChart: Bool = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 158), spacing: 8)], spacing: 8) {
                    StatTile(label: "Components", value: "\(store.components.count)",
                             sub: "distinct part numbers")
                    StatTile(label: "Total units", value: "\(store.totalUnits)",
                             sub: "across all bins")
                    StatTile(label: "Inventory value", value: money(store.totalValue),
                             sub: "qty × unit cost")
                    StatTile(label: "Low stock", value: "\(store.lowStockCount)",
                             sub: "at or under minimum",
                             tint: store.lowStockCount > 0 ? Palette.warn : Palette.textHi)
                    StatTile(label: "Out of stock", value: "\(store.outOfStockCount)",
                             sub: "nothing on hand",
                             tint: store.outOfStockCount > 0 ? Palette.danger : Palette.textHi)
                }

                if showChart && !store.categoryCounts.isEmpty {
                    categoryChart
                }

                if !store.lowStockComponents.isEmpty {
                    reorderList
                }

                if store.components.isEmpty {
                    EmptyStateView(systemImage: "square.grid.2x2",
                                   title: "Nothing to summarise yet",
                                   message: "Add components and your stock levels, value and category mix will appear here.")
                        .frame(height: 200)
                }
            }
            .padding(12)
        }
        .background {
            ZStack(alignment: .topLeading) {
                Palette.bg
                if SkinController.skin.gridBackdrop { GridBackdrop() }
            }
        }
    }

    var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("COMPONENTTRACKER \(store.totalUnits) UNITS ON HAND")
                .font(.mono(.title, .bold))
                .tracking(0.8)
                .foregroundStyle(Palette.textHi)
            Text(store.lastSaved.map { "Saved \(relative($0))" } ?? "Not saved yet")
                .font(.mono(.small))
                .foregroundStyle(Palette.textLow)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var categoryChart: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel("Units by category")
            Chart {
                ForEach(store.categoryCounts, id: \.0) { name, count in
                    BarMark(
                        x: .value("Units", unitsIn(name)),
                        y: .value("Category", name)
                    )
                    // Square, not 3pt-rounded: a rounded bar is a chart in a
                    // marketing deck, a square one is a readout on an instrument.
                    .foregroundStyle(swiftUIColor(for: name).opacity(0.9))
                    // Annotated inline. A terminal shows you the number, not
                    // just the shape.
                    .annotation(position: .trailing) {
                        Text("\(unitsIn(name))")
                            .font(.mono(.label))
                            .foregroundStyle(Palette.textMid)
                    }
                }
            }
            .chartXAxis {
                AxisMarks(preset: .aligned, position: .bottom) { _ in
                    AxisValueLabel()
                        .font(.mono(.label))
                        .foregroundStyle(Palette.textLow)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisValueLabel()
                        .font(.mono(.small))
                        .foregroundStyle(Palette.textMid)
                }
            }
            .frame(height: max(130, CGFloat(store.categoryCounts.count) * 26))
        }
        .padding(11)
        .overlay(Rectangle().strokeBorder(Palette.line, lineWidth: Metrics.rule))
    }

    var reorderList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("Needs reordering")
                Spacer(minLength: 8)
                Text("\(store.lowStockComponents.count) ITEM\(store.lowStockComponents.count == 1 ? "" : "S")")
                    .font(.mono(.small))
                    .foregroundStyle(Palette.textLow)
            }

            VStack(spacing: 0) {
                ForEach(Array(store.lowStockComponents.sorted { $0.stockLevel != $1.stockLevel ? $0.stockLevel == .low : $0.quantity < $1.quantity })) { c in
                    HStack(spacing: 8) {
                        StockDot(level: c.stockLevel)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(c.partNumber.isEmpty ? c.name : c.partNumber)
                                .font(.mono(.body, .semibold))
                                .foregroundStyle(Palette.textHi)
                                .lineLimit(1)
                            Text([c.name, c.supplier].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.ui(.small))
                                .foregroundStyle(Palette.textLow)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        if c.minimumStock > 0 {
                            Text("min \(c.minimumStock)")
                                .font(.mono(.label))
                                .foregroundStyle(Palette.textLow)
                        }
                        Text("\(c.quantity)")
                            .font(.mono(.title, .bold))
                            .foregroundStyle(c.stockLevel == .out ? Palette.danger : Palette.warn)
                            .frame(width: 34, alignment: .trailing)
                        Pill(text: c.category, tint: swiftUIColor(for: c.category))
                    }
                    .padding(.vertical, 6)

                    if c.id != store.lowStockComponents.last?.id {
                        Rule(weight: Palette.lineSoft)
                    }
                }
            }
        }
        .padding(11)
        .overlay(Rectangle().strokeBorder(Palette.line, lineWidth: Metrics.rule))
    }

    private func unitsIn(_ category: String) -> Int {
        store.components.filter { $0.category == category }.reduce(0) { $0 + $1.quantity }
    }

    private func money(_ v: Double) -> String {
        Money.compact(v)
    }

    private func relative(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: d, relativeTo: Date())
    }
}
