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
            VStack(alignment: .leading, spacing: 18) {
                header

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: 12)], spacing: 12) {
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
            .padding(Metrics.pad)
        }
        .background(Palette.bg)
    }

    var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Dashboard")
                .font(.ui(20, .semibold))
                .foregroundStyle(Palette.textHi)
            Text(store.lastSaved.map { "Saved \(relative($0))" } ?? "Not saved yet")
                .font(.ui(11))
                .foregroundStyle(Palette.textLow)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var categoryChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Units by category")
            Chart {
                ForEach(store.categoryCounts, id: \.0) { name, count in
                    BarMark(
                        x: .value("Units", unitsIn(name)),
                        y: .value("Category", name)
                    )
                    .foregroundStyle(swiftUIColor(for: name).opacity(0.85))
                    .cornerRadius(3)
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                        .foregroundStyle(Palette.lineSoft)
                    AxisValueLabel().foregroundStyle(Palette.textLow)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisValueLabel().foregroundStyle(Palette.textMid)
                }
            }
            .frame(height: max(130, CGFloat(store.categoryCounts.count) * 26))
        }
        .padding(15)
        .panel()
    }

    var reorderList: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                SectionLabel("Needs reordering")
                Spacer()
                Text("\(store.lowStockComponents.count) item\(store.lowStockComponents.count == 1 ? "" : "s")")
                    .font(.mono(10))
                    .foregroundStyle(Palette.textLow)
            }

            VStack(spacing: 0) {
                ForEach(Array(store.lowStockComponents.sorted { $0.stockLevel != $1.stockLevel ? $0.stockLevel == .low : $0.quantity < $1.quantity })) { c in
                    HStack(spacing: 10) {
                        StockDot(level: c.stockLevel)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(c.partNumber.isEmpty ? c.name : c.partNumber)
                                .font(.mono(11, .medium))
                                .foregroundStyle(Palette.textHi)
                                .lineLimit(1)
                            Text([c.name, c.supplier].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.ui(10))
                                .foregroundStyle(Palette.textLow)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Text("\(c.quantity)")
                            .font(.mono(12, .semibold))
                            .foregroundStyle(c.stockLevel == .out ? Palette.danger : Palette.warn)
                        if c.minimumStock > 0 {
                            Text("min \(c.minimumStock)")
                                .font(.mono(9))
                                .foregroundStyle(Palette.textLow)
                        }
                        Pill(text: c.category, tint: swiftUIColor(for: c.category))
                    }
                    .padding(.vertical, 9)

                    if c.id != store.lowStockComponents.last?.id {
                        Divider().overlay(Palette.lineSoft.opacity(0.6))
                    }
                }
            }
        }
        .padding(15)
        .panel()
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
