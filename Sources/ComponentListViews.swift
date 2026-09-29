import SwiftUI

// MARK: - Table view

struct ComponentTable: View {
    @EnvironmentObject private var store: InventoryStore
    var components: [Component]
    @Binding var selection: Set<UUID>
    var onEdit: (Component) -> Void
    var onTakeOut: (Component) -> Void
    var onDelete: (Component) -> Void

    @StateObject private var ui = TableUI()

    var body: some View {
        Table(components, selection: $selection, sortOrder: $ui.sortOrder) {
            TableColumn("") { c in
                StockDot(level: c.stockLevel)
            }
            .width(14)

            TableColumn("PART NO.", sortUsing: KeyPathComparator(\.partNumber)) { c in
                Text(c.partNumber.isEmpty ? "—" : c.partNumber)
                    .font(.mono(12, .medium))
                    .foregroundStyle(c.partNumber.isEmpty ? Palette.textLow : Palette.textHi)
                    .lineLimit(1)
            }
            .width(min: 130, ideal: 165)

            TableColumn("DESCRIPTION", sortUsing: KeyPathComparator(\.name)) { c in
                VStack(alignment: .leading, spacing: 1) {
                    Text(c.name.isEmpty ? "Unnamed" : c.name)
                        .font(.ui(12))
                        .foregroundStyle(c.name.isEmpty ? Palette.textLow : Palette.textHi)
                        .lineLimit(1)
                    if !c.value.isEmpty || !c.footprint.isEmpty {
                        Text([c.value, c.footprint].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.mono(10))
                            .foregroundStyle(Palette.textLow)
                            .lineLimit(1)
                    }
                }
            }
            .width(min: 150, ideal: 230)

            TableColumn("CATEGORY", sortUsing: KeyPathComparator(\.category)) { c in
                Pill(text: c.category, tint: swiftUIColor(for: c.category))
            }
            .width(min: 90, ideal: 118)

            TableColumn("QTY", sortUsing: KeyPathComparator(\.quantity)) { c in
                HStack(spacing: 2) {
                    Spacer(minLength: 0)
                    if c.minimumStock > 0 {
                        Text("/\(c.minimumStock)")
                            .font(.mono(10))
                            .foregroundStyle(Palette.textLow)
                    }
                    Text("\(c.quantity)")
                        .font(.mono(12, .medium))
                        .foregroundStyle(qtyColor(c))
                }
            }
            .width(min: 54, ideal: 66)

            TableColumn("LOCATION", sortUsing: KeyPathComparator(\.location)) { c in
                Text(c.location.isEmpty ? "—" : c.location)
                    .font(.mono(11))
                    .foregroundStyle(c.location.isEmpty ? Palette.textLow : Palette.textMid)
                    .lineLimit(1)
            }
            .width(min: 70, ideal: 110)

            TableColumn("VALUE", sortUsing: KeyPathComparator(\.totalValue)) { c in
                Text(c.unitCost > 0 ? currency(c.totalValue) : "—")
                    .font(.mono(11))
                    .foregroundStyle(Palette.textMid)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 60, ideal: 80)

            TableColumn("") { c in
                RowActions(component: c,
                           onEdit: { onEdit(c) },
                           onTakeOut: { onTakeOut(c) },
                           onDelete: { onDelete(c) })
            }
            .width(66)
        }
        // SwiftUI ships only `.inset` and `.automatic` — there is no `.plain`
        // TableStyle to reach for. `.inset(alternatesRowBackgrounds:)` is the
        // closest ledger-like option, and `.scrollContentBackground(.hidden)`
        // below lets the theme own the colour instead of the style's greys.
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .scrollContentBackground(.hidden)
        .background(Palette.bg)
        .onAppear { applyStoreSort() }
        // Keep the store's sort in step so the card view matches the table.
        .onChange(of: ui.sortOrder) { _, new in
            guard let c = new.first else { return }
            let desc = String(describing: c.keyPath)
            let field: SortField
            switch desc {
            case _ where desc.hasSuffix("partNumber"): field = .partNumber
            case _ where desc.hasSuffix("name"):       field = .name
            case _ where desc.hasSuffix("category"):   field = .category
            case _ where desc.hasSuffix("quantity"):   field = .quantity
            case _ where desc.hasSuffix("location"):   field = .location
            case _ where desc.hasSuffix("value"):      field = .value
            case _ where desc.hasSuffix("totalValue"): field = .totalValue
            case _ where desc.hasSuffix("updatedAt"):  field = .updatedAt
            default: return
            }
            if store.sortField != field || store.sortAscending != (c.order == .forward) {
                store.sortField = field
                store.sortAscending = (c.order == .forward)
            }
        }
    }

    /// Rebuilds the native table sort from the store's sort state.
    /// The Table only accepts one concrete comparator type, so each field is
    /// handled in its own branch rather than through a shared helper.
    private func applyStoreSort() {
        let order: SortOrder = store.sortAscending ? .forward : .reverse
        switch store.sortField {
        case .partNumber: ui.sortOrder = [KeyPathComparator(\.partNumber, order: order)]
        case .name:       ui.sortOrder = [KeyPathComparator(\.name, order: order)]
        case .category:   ui.sortOrder = [KeyPathComparator(\.category, order: order)]
        case .location:   ui.sortOrder = [KeyPathComparator(\.location, order: order)]
        case .value:      ui.sortOrder = [KeyPathComparator(\.value, order: order)]
        case .quantity:   ui.sortOrder = [KeyPathComparator(\.quantity, order: order)]
        case .totalValue: ui.sortOrder = [KeyPathComparator(\.totalValue, order: order)]
        case .updatedAt:  ui.sortOrder = [KeyPathComparator(\.updatedAt, order: order)]
        }
    }

    private func qtyColor(_ c: Component) -> Color {
        switch c.stockLevel {
        case .ok:  return Palette.textHi
        case .low: return Palette.warn
        case .out: return Palette.danger
        }
    }

    private func currency(_ v: Double) -> String {
        Money.compact(v)
    }
}

struct StockDot: View {
    var level: Component.StockLevel
    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: 6, height: 6)
            .opacity(level == .ok ? 0.4 : 1)
    }
    private var color: Color {
        switch level {
        case .ok:  return Palette.textMid
        case .low: return Palette.warn
        case .out: return Palette.danger
        }
    }
}

struct RowActions: View {
    var component: Component
    var onEdit: () -> Void
    var onTakeOut: () -> Void
    var onDelete: () -> Void
    @EnvironmentObject private var store: InventoryStore

    var body: some View {
        HStack(spacing: 3) {
            iconBtn("minus", help: "Take out") { onTakeOut() }
                .disabled(component.quantity == 0)
            iconBtn("plus", help: "Put back 1") { store.adjustQuantity(component, by: 1) }
            iconBtn("pencil", help: "Edit") { onEdit() }
            iconBtn("trash", help: "Delete") { onDelete() }
        }
    }

    private func iconBtn(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Palette.textMid)
                .frame(width: 15, height: 15)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - Card view

struct ComponentCardGrid: View {
    var components: [Component]
    @Binding var selection: Set<UUID>
    var onEdit: (Component) -> Void
    var onTakeOut: (Component) -> Void
    var onDelete: (Component) -> Void

    // Denser than the old 215pt minimum. Information density is the point of
    // this aesthetic, and a ledger that wastes a third of a screen on padding
    // is not a ledger.
    private let columns = [GridItem(.adaptive(minimum: 190, maximum: 300), spacing: 8)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(components) { c in
                    ComponentCard(component: c,
                                  onEdit: { onEdit(c) },
                                  onTakeOut: { onTakeOut(c) },
                                  onDelete: { onDelete(c) })
                }
            }
            .padding(10)
        }
        .background(Palette.bg)
    }
}

struct ComponentCard: View {
    @EnvironmentObject private var store: InventoryStore
    var component: Component
    var onEdit: () -> Void
    var onTakeOut: () -> Void
    var onDelete: () -> Void

    var body: some View {
        CardChrome {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(component.partNumber.isEmpty ? "—" : component.partNumber)
                        .font(.mono(12, .bold))
                        .foregroundStyle(Palette.textHi)
                        .lineLimit(1)
                    Text(component.name.isEmpty ? "Unnamed" : component.name)
                        .font(.ui(10))
                        .foregroundStyle(Palette.textMid)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                StockDot(level: component.stockLevel)
            }

            HStack(spacing: 5) {
                Pill(text: component.category, tint: swiftUIColor(for: component.category))
                if !component.footprint.isEmpty {
                    Pill(text: component.footprint, tint: Palette.textLow)
                }
            }

            if !component.value.isEmpty || !component.location.isEmpty {
                HStack(spacing: 12) {
                    if !component.value.isEmpty {
                        metaBlock("Value", component.value, mono: true)
                    }
                    if !component.location.isEmpty {
                        metaBlock("Location", component.location, mono: true)
                    }
                }
            }

            Rule(weight: Palette.lineSoft)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 1) {
                    SectionLabel("In stock")
                    HStack(spacing: 3) {
                        Text("\(component.quantity)")
                            .font(.mono(17, .medium))
                            .foregroundStyle(qtyColor)
                        if component.minimumStock > 0 {
                            Text("min \(component.minimumStock)")
                                .font(.mono(9))
                                .foregroundStyle(Palette.textLow)
                        }
                    }
                }
                Spacer(minLength: 0)
                if component.unitCost > 0 {
                    VStack(alignment: .trailing, spacing: 1) {
                        SectionLabel("Value")
                        Text(Money.exact(component.totalValue))
                            .font(.mono(12, .medium))
                            .foregroundStyle(Palette.textMid)
                    }
                }
            }

            HStack(spacing: 6) {
                GhostButton(title: "Take Out", systemImage: "minus") { onTakeOut() }
                    .disabled(component.quantity == 0)
                GhostButton(title: "Edit", systemImage: "pencil") { onEdit() }
                Spacer(minLength: 0)
                GhostButton(title: "Delete") { onDelete() }
            }
        }
        .padding(SkinController.skin.pad - 4)
        }
        .contextMenu {
            Button("Edit…") { onEdit() }
            Button("Take Out…") { onTakeOut() }
            Button("Duplicate") { store.duplicate(component) }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
    }

    private func metaBlock(_ label: String, _ value: String, mono: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            SectionLabel(label)
            Text(value)
                .font(mono ? .mono(11) : .ui(11))
                .foregroundStyle(Palette.textMid)
                .lineLimit(1)
        }
    }

    private var qtyColor: Color {
        switch component.stockLevel {
        case .ok:  return Palette.textHi
        case .low: return Palette.warn
        case .out: return Palette.danger
        }
    }
}
