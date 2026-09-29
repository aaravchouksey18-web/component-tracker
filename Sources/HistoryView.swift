import SwiftUI

// MARK: - Usage history

/// The consumption log. Every take-out and put-back is recorded when it happens,
/// so this is a record of what actually left the shelves — not something
/// reconstructed later from stock levels.
struct HistoryView: View {
    @EnvironmentObject private var store: InventoryStore

    /// Tapping a row jumps to that part. The link is dangle-able: entries for a
    /// deleted component still show, but are not clickable.
    var onOpenPart: (UUID) -> Void

    /// Scopes the log to one part. Set from the component editor's history sheet.
    var focusComponentID: UUID? = nil

    /// Off in the offscreen render harness only. A ScrollView rasterises empty
    /// under ImageRenderer, and the same is true of `Table`, so the views that
    /// use those containers can never be checked that way. Exposing the switch
    /// is cheaper than duplicating the layout, and it keeps the render going
    /// through `body` — reading `@EnvironmentObject` while building a view tree
    /// outside a render pass traps.
    var scrollable: Bool = true

    @StateObject private var ui = HistoryUI()

    private var entries: [ConsumptionEntry] {
        guard let id = focusComponentID else { return store.filteredHistory }
        return store.filteredHistory.filter { $0.componentID == id }
    }

    var body: some View {
        Group {
            if scrollable {
                ScrollView { content.padding(Metrics.pad) }
            } else {
                content.padding(Metrics.pad)
            }
        }
        .background(Palette.bg)
        .confirmationDialog(
            "Clear all \(store.consumed.count) log entr\(store.consumed.count == 1 ? "y" : "ies")?",
            isPresented: $ui.showClearConfirm, titleVisibility: .visible
        ) {
            Button("Clear Usage History", role: .destructive) { store.clearAllHistory() }
            Button("Cancel", role: .cancel) {}
        } message: {
            // Undo covers a mis-click, but not a log that has simply grown too
            // large — so be explicit that this is permanent.
            Text("Stock counts are not affected — only the record of what was taken out. This cannot be undone after the app restarts.")
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            if entries.isEmpty {
                emptyState.frame(maxWidth: .infinity)
            } else {
                summaryTiles
                if focusComponentID == nil { projectBreakdown }
                logList
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Usage History")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .tracking(1.0)
                    .foregroundStyle(Palette.textHi)
                Text(store.consumed.isEmpty
                     ? "Nothing logged yet"
                     : "\(store.consumed.count) entr\(store.consumed.count == 1 ? "y" : "ies") · \(store.totalConsumed) net unit\(store.totalConsumed == 1 ? "" : "s") used")
                    .font(.ui(11))
                    .foregroundStyle(Palette.textLow)
            }
            Spacer(minLength: 8)
            if !store.consumed.isEmpty && focusComponentID == nil {
                GhostButton(title: "Clear", systemImage: "trash") { ui.showClearConfirm = true }
                    .help("Clear the whole usage log")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Summary

    private var summaryTiles: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: 12)], spacing: 12) {
            StatTile(label: "Net used", value: "\(store.totalConsumed)",
                     sub: "returns subtracted")
            StatTile(label: "This month", value: "\(netUsedThisMonth)",
                     sub: monthLabel)
            StatTile(label: "Projects", value: "\(store.consumptionByProject.count)",
                     sub: "named in the log")
            StatTile(label: "Most used", value: topPart ?? "—",
                     sub: topPartUnits > 0 ? "\(topPartUnits) units" : "",
                     tint: Palette.textHi)
        }
    }

    /// Per-project totals as a proportional bar list. No Charts here on purpose:
    /// this reads as a small table, not a plot, and it stays legible at any width.
    /// Bar length is gross take-outs, so a project that got parts back still has
    /// a bar the right size.
    private var projectBreakdown: some View {
        let rows = store.consumptionByProject
        let peak = max(1, rows.map(\.used).max() ?? 1)

        return VStack(alignment: .leading, spacing: 11) {
            SectionLabel("By project")
            VStack(spacing: 0) {
                ForEach(rows, id: \.project) { row in
                    HStack(spacing: 10) {
                        Text(row.project)
                            .font(.ui(11))
                            .foregroundStyle(row.project == "Unassigned" ? Palette.textLow : Palette.textHi)
                            .frame(width: 130, alignment: .leading)
                            .lineLimit(1)
                        // Square bar. The track behind it matters as much as
                        // the fill: a bar floating in empty space cannot be
                        // compared against the peak, which is the only reason
                        // to draw one.
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(Palette.lineSoft)
                                Rectangle()
                                    .fill(Palette.accent.opacity(row.project == "Unassigned" ? 0.3 : 0.85))
                                    .frame(width: max(2, geo.size.width * CGFloat(row.used) / CGFloat(peak)))
                            }
                        }
                        .frame(height: 9)
                        // Gross take-outs, with returns shown separately so the
                        // figure is never negative and never misleading.
                        Text("\(row.used)")
                            .font(.mono(11, .medium))
                            .foregroundStyle(Palette.textMid)
                            .frame(width: 46, alignment: .trailing)
                        Text(row.returned > 0 ? "−\(row.returned) back" : "")
                            .font(.mono(9))
                            .foregroundStyle(Palette.good)
                            .frame(width: 58, alignment: .leading)
                    }
                    .padding(.vertical, 7)

                    if row.project != rows.last?.project {
                        Divider().overlay(Palette.lineSoft.opacity(0.6))
                    }
                }
            }
        }
        .padding(15)
        .overlay(Rectangle().strokeBorder(Palette.line, lineWidth: Metrics.rule))
    }

    // MARK: Log

    private var logList: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                SectionLabel(focusComponentID == nil ? "All entries" : "This part only")
                Spacer()
                Text("\(entries.count)")
                    .font(.mono(10))
                    .foregroundStyle(Palette.textLow)
            }

            VStack(spacing: 0) {
                ForEach(entries) { e in
                    row(e)
                    if e.id != entries.last?.id {
                        Divider().overlay(Palette.lineSoft.opacity(0.6))
                    }
                }
            }
        }
        .padding(15)
        .overlay(Rectangle().strokeBorder(Palette.line, lineWidth: Metrics.rule))
    }

    private func row(_ e: ConsumptionEntry) -> some View {
        let stillThere = store.components.contains { $0.id == e.componentID }

        return HStack(alignment: .center, spacing: 11) {
            // Sign column. Returns are the exception, so they read green and
            // carry a +; a take-out is the normal case and reads plain.
            Text(e.kind == .used ? "−\(e.quantity)" : "+\(e.quantity)")
                .font(.mono(12, .semibold))
                .foregroundStyle(e.kind == .used ? Palette.textHi : Palette.good)
                .frame(width: 46, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                Text(e.displayPart)
                    .font(.mono(11, .medium))
                    .foregroundStyle(stillThere ? Palette.textHi : Palette.textMid)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(stamp(e.date))
                        .font(.mono(10))
                        .foregroundStyle(Palette.textLow)
                    if !e.subtitle.isEmpty {
                        Text("·")
                            .font(.mono(10))
                            .foregroundStyle(Palette.textLow)
                        Text(e.subtitle)
                            .font(.ui(10))
                            .foregroundStyle(Palette.textLow)
                            .lineLimit(1)
                    }
                    if !stillThere {
                        Text("· deleted")
                            .font(.ui(10))
                            .foregroundStyle(Palette.warn)
                    }
                }
            }

            Spacer(minLength: 8)

            if !e.project.isEmpty {
                Pill(text: e.project, tint: Palette.textMid)
            }
            // Only meaningful once a second entry exists for the same part —
            // a single row's "after" is just today's stock count.
            if !stillThere || !hasEarlierEntry(for: e) {
                Text("—")
                    .font(.mono(10))
                    .foregroundStyle(Palette.textLow)
                    .help(stillThere ? "No earlier entry to compare" : "Part deleted")
            } else {
                Text("\(e.resultingStock) left")
                    .font(.mono(10))
                    .foregroundStyle(e.resultingStock <= 0 ? Palette.danger : Palette.textLow)
            }

            if stillThere {
                Button { onOpenPart(e.componentID) } label: {
                    Image(systemName: "arrow.up.left")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Palette.textMid)
                }
                .buttonStyle(.plain)
                .help("Show this part in the inventory")
            }
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    /// True when some other entry for the same part is older than this one.
    private func hasEarlierEntry(for e: ConsumptionEntry) -> Bool {
        store.consumed.contains { $0.componentID == e.componentID && $0.date < e.date }
    }

    // MARK: Empty

    private var emptyState: some View {
        EmptyStateView(
            systemImage: "clock.arrow.circlepath",
            title: store.consumed.isEmpty ? "No usage recorded yet" : "No entries match",
            message: store.consumed.isEmpty
                ? "Use “Take Out” on any part to record what you used, and it will show up here with the date and project."
                : "No logged entry matches the current search."
        )
        .frame(height: 200)
    }

    // MARK: Derived

    private var netUsedThisMonth: Int {
        let cal = Calendar.current
        return store.consumed.reduce(0) { sum, e in
            cal.isDate(e.date, equalTo: Date(), toGranularity: .month) ? sum + e.signedQuantity : sum
        }
    }

    private var monthLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: Date())
    }

    /// The part with the most units taken out. Gross take-outs, not the net —
    /// ranking by net could crown a part that was only ever put back.
    private var usageByPart: [(part: String, used: Int)] {
        var totals: [UUID: (String, Int)] = [:]
        for e in store.consumed where e.kind == .used {
            let existing = totals[e.componentID]
            totals[e.componentID] = (existing?.0 ?? e.displayPart, (existing?.1 ?? 0) + e.quantity)
        }
        return totals.values
            .map { (part: $0.0, used: $0.1) }
            .sorted { $0.used != $1.used ? $0.used > $1.used : $0.part < $1.part }
    }

    private var topPart: String? { usageByPart.first?.part }

    private var topPartUnits: Int { usageByPart.first?.used ?? 0 }

    /// Absolute date and time. A log has to be unambiguous — "yesterday" is
    /// useless when you are trying to reconstruct a build.
    private func stamp(_ d: Date) -> String {
        Self.stampFormatter.string(from: d)
    }

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy, HH:mm"
        return f
    }()

    /// Date without the time, for the compact list inside the editor.
    static func dayStamp(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
        return f.string(from: d)
    }
}
