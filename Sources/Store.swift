import Foundation
import Combine

// MARK: - Security Constants

private enum SecurityLimits {
    static let maxInventoryFileSize = 10_000_000 // 10 MB
    static let maxComponents = 10_000
    static let maxStringLength = 1000
    static let maxQuantity = 1_000_000
    static let maxUnitCost = 10_000_000.0
    static let maxUndoStackSize = 40
}

// MARK: - Validation

private func validateString(_ s: String, maxLength: Int = SecurityLimits.maxStringLength) -> String {
    var result = s.trimmingCharacters(in: .whitespacesAndNewlines)
    if result.count > maxLength {
        result = String(result.prefix(maxLength))
    }
    // Remove control characters except newlines/tabs in notes
    result = result.filter { !$0.isNewline || $0 == "\n" || $0 == "\t" }
    return result
}

private func validateQuantity(_ q: Int) -> Int {
    max(0, min(q, SecurityLimits.maxQuantity))
}

private func validateCost(_ c: Double) -> Double {
    max(0, min(c, SecurityLimits.maxUnitCost))
}

private func validateURL(_ url: String) -> String {
    let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.isEmpty || (trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")) else {
        return "" // Reject non-HTTP(S) URLs
    }
    return String(trimmed.prefix(SecurityLimits.maxStringLength))
}

// MARK: - Sorting

enum SortField: String, CaseIterable {
    case partNumber, name, category, quantity, location, value, totalValue, updatedAt
    var label: String {
        switch self {
        case .partNumber: return "Part Number"
        case .name:       return "Name"
        case .category:   return "Category"
        case .quantity:   return "Qty"
        case .location:   return "Location"
        case .value:      return "Value"
        case .totalValue: return "Total Cost"
        case .updatedAt:  return "Updated"
        }
    }
}

// MARK: - Sidebar destinations

enum Section: String, CaseIterable, Identifiable {
    case dashboard, all, lowStock, outOfStock, history, categories
    var id: String { self.rawValue }
    var label: String {
        switch self {
        case .dashboard:   return "Dashboard"
        case .all:         return "All Components"
        case .lowStock:    return "Low Stock"
        case .outOfStock:  return "Out of Stock"
        case .history:     return "Usage History"
        case .categories:  return "Categories"
        }
    }
    var icon: String {
        switch self {
        case .dashboard:   return "square.grid.2x2"
        case .all:         return "tray.full"
        case .lowStock:    return "exclamationmark.triangle"
        case .outOfStock:  return "xmark.octagon"
        case .history:     return "clock.arrow.circlepath"
        case .categories:  return "square.grid.3x3"
        }
    }
    /// The log has no count badge and no per-category children.
    var supportsCategories: Bool { self != .history }
}

// MARK: - App store

@MainActor
final class InventoryStore: ObservableObject {
    @Published var components: [Component] = []
    /// Take-out history, newest first. Top-level in the document, not inside a
    /// component, so entries outlive the records they point at.
    @Published private(set) var consumed: [ConsumptionEntry] = []
    @Published var searchText: String = ""
    @Published var section: Section = .all
    @Published var categoryFilter: String? = nil
    @Published var sortField: SortField = .partNumber
    @Published var sortAscending: Bool = true
    @Published var cardView: Bool = false

    /// Phosphor-on-black or ink-on-paper.
    ///
    /// This lives on the store rather than in its own observable object for a
    /// concrete reason: every view in the app already observes the store, so a
    /// single publish here repaints all of them. A dedicated `ThemeController`
    /// as an `ObservableObject` would need to be injected into every
    /// `environmentObject` call site to get the same coverage.
    ///
    /// `Palette` reads a plain global rather than the environment, so the new
    /// colours must be in place *before* the publish propagates. `didSet` runs
    /// before any view re-renders, which is why it is safe here.
    @Published var darkMode: Bool {
        didSet {
            guard darkMode != oldValue else { return }
            ThemeController.set(dark: darkMode)
            UserDefaults.standard.set(darkMode, forKey: Self.themeKey)
        }
    }

    static let themeKey = "componenttracker.darkMode"

    @Published private(set) var lastSaved: Date? = nil
    @Published private(set) var statusMessage: String? = nil

    /// Surface a one-off message to the user (cleared automatically after a few seconds).
    func notify(_ message: String) {
        statusMessage = message
        statusWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.statusMessage == message else { return }
            self.statusMessage = nil
        }
        statusWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }

    private let storeURL: URL
    private let fileManager = FileManager.default
    private var saveWorkItem: DispatchWorkItem?
    private var statusWorkItem: DispatchWorkItem?

    // MARK: Paths

    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("ComponentTracker", isDirectory: true)
    }

    static var inventoryFile: URL {
        supportDirectory.appendingPathComponent("inventory.json")
    }

    /// The live store, so the app delegate can flush pending writes on quit.
    nonisolated(unsafe) static var shared: InventoryStore?

    init(storeURL: URL? = nil) {
        // Seed from UserDefaults *before* the first view reads `Palette`.
        // `didSet` does not fire for a property set during initialisation, so
        // the theme has to be pushed into the global by hand or the first frame
        // renders the wrong scheme and then corrects itself a frame later.
        let stored = UserDefaults.standard.object(forKey: Self.themeKey) as? Bool
        let dark = stored ?? true
        self.darkMode = dark
        ThemeController.set(dark: dark)

        self.storeURL = storeURL ?? InventoryStore.inventoryFile
        load()
        if storeURL == nil { InventoryStore.shared = self }
    }

    // MARK: Load / Save

    private func ensureDirectory() {
        let dir = storeURL.deletingLastPathComponent()
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func load() {
        ensureDirectory()
        guard fileManager.fileExists(atPath: storeURL.path) else {
            components = []
            consumed = []
            return
        }
        do {
            // Security: Check file size before loading to prevent DoS
            let attrs = try fileManager.attributesOfItem(atPath: storeURL.path)
            if let fileSize = attrs[.size] as? Int64, fileSize > SecurityLimits.maxInventoryFileSize {
                throw NSError(domain: "InventoryStore", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Inventory file exceeds size limit"])
            }
            
            let data = try Data(contentsOf: storeURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let inv = try decoder.decode(Inventory.self, from: data)
            
            // Validate loaded data
            components = inv.components.map { sanitizeComponent($0) }
            consumed = inv.consumed.map { sanitizeConsumptionEntry($0) }
            
            // Enforce component count limit
            if components.count > SecurityLimits.maxComponents {
                components = Array(components.prefix(SecurityLimits.maxComponents))
            }
        } catch {
            // Never lose data: park the unreadable file and start clean.
            let backup = storeURL.deletingLastPathComponent()
                .appendingPathComponent("inventory-corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? fileManager.moveItem(at: storeURL, to: backup)
            components = []
            consumed = []
            statusMessage = "Data file was unreadable — original saved as inventory-corrupt-*.json"
        }
    }
    
    private func sanitizeComponent(_ c: Component) -> Component {
        var result = c
        result.partNumber = validateString(c.partNumber)
        result.name = validateString(c.name)
        result.category = validateString(c.category)
        result.location = validateString(c.location)
        result.manufacturer = validateString(c.manufacturer)
        result.supplier = validateString(c.supplier)
        result.orderNumber = validateString(c.orderNumber)
        result.value = validateString(c.value)
        result.footprint = validateString(c.footprint)
        result.tolerance = validateString(c.tolerance)
        result.voltageRating = validateString(c.voltageRating)
        result.datasheetURL = validateURL(c.datasheetURL)
        result.notes = validateString(c.notes, maxLength: 5000)
        result.quantity = validateQuantity(c.quantity)
        result.minimumStock = validateQuantity(c.minimumStock)
        result.unitCost = validateCost(c.unitCost)
        result.project = validateString(c.project)
        return result
    }
    
    private func sanitizeConsumptionEntry(_ e: ConsumptionEntry) -> ConsumptionEntry {
        var result = e
        result.partNumber = validateString(e.partNumber)
        result.name = validateString(e.name)
        result.project = validateString(e.project)
        result.quantity = validateQuantity(e.quantity)
        result.resultingStock = validateQuantity(e.resultingStock)
        return result
    }

    /// Debounced atomic write.
    func save() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.writeNow() }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    /// Writes immediately, cancelling any pending debounced write.
    /// Used by ⌘S, the toolbar save button, and on app termination.
    func flush() {
        saveWorkItem?.cancel()
        writeNow()
    }

    private func writeNow() {
        ensureDirectory()
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(Inventory(components: components, consumed: consumed))
            try data.write(to: storeURL, options: .atomic)
            lastSaved = Date()
        } catch {
            statusMessage = "Could not save: \(error.localizedDescription)"
        }
    }
    // MARK: CRUD

    func add(_ c: Component) {
        guard components.count < SecurityLimits.maxComponents else {
            statusMessage = "Maximum component limit reached"
            return
        }
        let sanitized = sanitizeComponent(c)
        recordUndo("Add \(shortName(sanitized))")
        components.append(sanitized)
        sort()
        save()
    }

    func update(_ c: Component) {
        guard let idx = components.firstIndex(where: { $0.id == c.id }) else { return }
        let sanitized = sanitizeComponent(c)
        // A no-op save (open the editor, hit Save, change nothing) must not burn
        // an undo step — the first ⌘Z after it would appear to do nothing.
        guard sanitized != components[idx] else { return }
        recordUndo("Edit \(shortName(sanitized))")
        var updated = sanitized
        updated.updatedAt = Date()
        components[idx] = updated
        sort()
        save()
    }

    func delete(_ c: Component) {
        guard components.contains(where: { $0.id == c.id }) else { return }
        recordUndo("Delete \(shortName(c))")
        components.removeAll { $0.id == c.id }
        save()
    }

    func delete(ids: Set<UUID>) {
        let names = components.filter { ids.contains($0.id) }.map(shortName)
        guard !names.isEmpty else { return }
        recordUndo("Delete \(names.count) component\(names.count == 1 ? "" : "s")")
        components.removeAll { ids.contains($0.id) }
        save()
    }

    /// "Take out" — remove units from stock and record why. Returns how many
    /// were actually taken, which may be fewer than asked for.
    ///
    /// Each call is its own undo step. Someone filling in the take-out sheet
    /// twice in a row meant two things, even if the second followed quickly.
    @discardableResult
    func takeOut(_ c: Component, count: Int, project: String = "") -> Int {
        let validCount = validateQuantity(count)
        let validProject = validateString(project)
        return applyTakeOut(c, count: validCount, project: validProject, undoKey: nil)
    }

    /// "Put back" — return units to stock. Logged too, as a signed return,
    /// so the history never claims parts were consumed when they were not.
    @discardableResult
    func putBack(_ c: Component, count: Int, project: String = "") -> Int {
        let validCount = validateQuantity(count)
        let validProject = validateString(project)
        return applyPutBack(c, count: validCount, project: validProject, undoKey: nil)
    }

    @discardableResult
    private func applyTakeOut(_ c: Component, count: Int, project: String, undoKey: String?) -> Int {
        guard let idx = components.firstIndex(where: { $0.id == c.id }) else { return 0 }
        let taken = min(max(count, 0), components[idx].quantity)
        guard taken > 0 else { return 0 }
        recordUndo("Take \(taken) × \(shortName(c))", coalescing: undoKey)
        components[idx].quantity -= taken
        components[idx].updatedAt = Date()
        log(.used, component: components[idx], quantity: taken, project: project)
        save()
        return taken
    }

    @discardableResult
    private func applyPutBack(_ c: Component, count: Int, project: String, undoKey: String?) -> Int {
        guard let idx = components.firstIndex(where: { $0.id == c.id }) else { return 0 }
        let added = max(count, 0)
        guard added > 0 else { return 0 }
        recordUndo("Return \(added) × \(shortName(c))", coalescing: undoKey)
        components[idx].quantity = validateQuantity(components[idx].quantity + added)
        components[idx].updatedAt = Date()
        log(.returned, component: components[idx], quantity: added, project: project)
        save()
        return added
    }

    /// Records one entry, newest first. Captures the part number and name as
    /// they are right now, because both may be edited or the record deleted
    /// later and the log has to keep making sense.
    private func log(_ kind: ConsumptionEntry.Kind, component c: Component,
                     quantity: Int, project: String) {
        var entry = ConsumptionEntry()
        entry.componentID = c.id
        entry.partNumber = validateString(c.partNumber)
        entry.name = validateString(c.name)
        entry.quantity = validateQuantity(quantity)
        entry.date = Date()
        entry.project = validateString(project)
        entry.resultingStock = validateQuantity(c.quantity)
        entry.kind = kind
        consumed.insert(entry, at: 0)
        
        // Limit consumption log size to prevent memory issues
        if consumed.count > SecurityLimits.maxComponents * 10 {
            consumed = Array(consumed.prefix(SecurityLimits.maxComponents * 10))
        }
    }

    /// Drops a component's history. Offered in the UI as a way to tidy up after
    /// a mis-keyed entry, and used when the user explicitly clears the log.
    func clearHistory(for componentID: UUID) {
        let n = consumed.filter { $0.componentID == componentID }.count
        guard n > 0 else { return }
        recordUndo("Clear \(n) log entr\(n == 1 ? "y" : "ies")")
        consumed.removeAll { $0.componentID == componentID }
        save()
    }

    func clearAllHistory() {
        let n = consumed.count
        guard n > 0 else { return }
        recordUndo("Clear all \(n) log entr\(n == 1 ? "y" : "ies")")
        consumed.removeAll()
        save()
    }

    /// Inline +/- from the list. Routed through take-out / put-back so a
    /// correction made here shows up in the history rather than silently
    /// desynchronising it from the stock count.
    ///
    /// These *do* coalesce: holding down the button should be one undo step, not
    /// twenty. Keyed per part *and direction*: a − that overshoots plus the +
    /// that corrects it are two gestures and must undo separately, otherwise a
    /// quick correction collapses into one step labelled with the first action.
    func adjustQuantity(_ c: Component, by delta: Int) {
        guard components.contains(where: { $0.id == c.id }) else { return }
        let validDelta = max(-SecurityLimits.maxQuantity, min(delta, SecurityLimits.maxQuantity))
        if validDelta < 0 {
            applyTakeOut(c, count: -validDelta, project: "", undoKey: "adjust:\(c.id):down")
        } else if validDelta > 0 {
            applyPutBack(c, count: validDelta, project: "", undoKey: "adjust:\(c.id):up")
        }
    }

    func duplicate(_ c: Component) {
        guard components.count < SecurityLimits.maxComponents else {
            statusMessage = "Maximum component limit reached"
            return
        }
        var copy = sanitizeComponent(c)
        copy.id = UUID()
        copy.partNumber = c.partNumber.isEmpty ? "" : validateString(c.partNumber + " (copy)")
        recordUndo("Duplicate \(shortName(c))")
        copy.createdAt = Date()
        copy.updatedAt = Date()
        components.append(copy)
        sort()
        save()
    }

    // MARK: Undo / redo

    /// One reversible step: the state *before* an edit, plus a label describing
    /// the edit that followed.
    private struct UndoStep {
        var components: [Component]
        var consumed: [ConsumptionEntry]
        var label: String
        /// Non-nil when this step may absorb a following edit (see `recordUndo`).
        var key: String?
        var at: Date
    }

    /// Snapshots rather than inverse commands. Every mutation here touches both
    /// the component list and the usage log, and a take-out is really *two*
    /// changes in one gesture — maintaining a correctly paired inverse for each
    /// is far more code than copying two arrays. The inventory is a few hundred
    /// rows at most, so the copies are cheap.
    private var undoStack: [UndoStep] = []
    private var redoStack: [UndoStep] = []

    @Published private(set) var undoLabel: String? = nil
    @Published private(set) var redoLabel: String? = nil

    /// Deep enough to walk back a whole session of edits, shallow enough that the
    /// copied arrays cannot grow without bound.
    private let undoLimit = SecurityLimits.maxUndoStackSize
    /// Two edits with the same key inside this window count as one gesture.
    private let coalesceWindow: TimeInterval = 1.5

    /// Call immediately *before* mutating. Captures the current state so `undo`
    /// has somewhere to go back to.
    private func recordUndo(_ label: String, coalescing key: String? = nil) {
        // If the step on top is the same gesture still in progress, its snapshot
        // already predates both edits — pushing again would make the first press
        // of ⌘Z look like it did nothing.
        if let key,
           let top = undoStack.last,
           top.key == key,
           Date().timeIntervalSince(top.at) < coalesceWindow {
            // Same gesture still in progress: the snapshot on top already
            // predates every edit in the run, so push nothing. Refresh the
            // timestamp so a continuously held button stays one undo step for
            // as long as it is held — only a deliberate pause begins the next
            // step. Keep the original wording: "Take 1 × X" reads better than
            // "Take 3 × X" for a run of single clicks that undo together.
            undoStack[undoStack.count - 1].at = Date()
            return
        }
        undoStack.append(UndoStep(components: components, consumed: consumed,
                                  label: label, key: key, at: Date()))
        if undoStack.count > undoLimit {
            undoStack.removeFirst(undoStack.count - undoLimit)
        }
        // Any new edit invalidates the redo branch, or redo could replay a
        // history the user has already stepped away from.
        redoStack.removeAll()
        refreshUndoState()
    }

    @MainActor
    func undo() {
        guard let step = undoStack.popLast() else { return }
        // The redo entry is the state we are leaving, tagged with the same label
        // so the menu can say "Redo: Take 3 × X".
        redoStack.append(UndoStep(components: components, consumed: consumed,
                                  label: step.label, key: nil, at: Date()))
        apply(step)
    }

    @MainActor
    func redo() {
        guard let step = redoStack.popLast() else { return }
        undoStack.append(UndoStep(components: components, consumed: consumed,
                                  label: step.label, key: nil, at: Date()))
        apply(step)
    }

    private func apply(_ step: UndoStep) {
        components = step.components
        consumed = step.consumed
        sort()
        save()
        refreshUndoState()
    }

    private func refreshUndoState() {
        let u = undoStack.last?.label
        let r = redoStack.last?.label
        if undoLabel != u { undoLabel = u }
        if redoLabel != r { redoLabel = r }
    }

    /// Part number if there is one, else the name, else something readable.
    /// Used for undo labels, which are shown in the menu bar.
    private func shortName(_ c: Component) -> String {
        if !c.partNumber.isEmpty { return c.partNumber }
        if !c.name.isEmpty { return c.name }
        return "untitled"
    }

    // MARK: Derived data

    var lowStockComponents: [Component] {
        components.filter { $0.stockLevel != .ok }
    }

    var lowStockCount: Int {
        components.filter { $0.isLowStock && !$0.isOutOfStock }.count
    }

    var outOfStockCount: Int {
        components.filter { $0.isOutOfStock }.count
    }

    var totalUnits: Int {
        components.reduce(0) { $0 + $1.quantity }
    }

    var totalValue: Double {
        components.reduce(0) { $0 + $1.totalValue }
    }

    var categoryCounts: [(String, Int)] {
        Dictionary(grouping: components, by: { $0.category })
            .map { ($0.key, $0.value.count) }
            .sorted { $0.1 > $1.1 }
    }

    // MARK: Consumption queries

    /// History for one part, newest first.
    func history(for componentID: UUID) -> [ConsumptionEntry] {
        consumed.filter { $0.componentID == componentID }
    }

    /// Net units that have left the inventory. Returns cancel take-outs, so a
    /// part that was taken out and then put back nets to zero. Can go negative
    /// if more was returned than was ever taken out — that is a true statement
    /// about the log rather than a bug, but it is why the per-project breakdown
    /// below does not use this number.
    var totalConsumed: Int {
        consumed.reduce(0) { $0 + $1.signedQuantity }
    }

    /// Units taken out per project, biggest first. Entries with no project are
    /// grouped under a placeholder rather than dropped, so the totals add up.
    ///
    /// Split into used/returned rather than one signed figure, because a project
    /// that returned more than it consumed would otherwise show negative usage —
    /// arithmetically right, but not something a bar chart can draw.
    var consumptionByProject: [(project: String, used: Int, returned: Int, net: Int)] {
        struct Acc { var used = 0; var returned = 0 }
        var totals: [String: Acc] = [:]
        for e in consumed {
            let key = e.project.isEmpty ? "Unassigned" : e.project
            var acc = totals[key] ?? Acc()
            if e.kind == .used { acc.used += e.quantity } else { acc.returned += e.quantity }
            totals[key] = acc
        }
        return totals
            .map { ($0.key, $0.value.used, $0.value.returned, $0.value.used - $0.value.returned) }
            .sorted { $0.used != $1.used ? $0.used > $1.used : $0.project < $1.project }
    }

    /// The log as the history list renders it: newest first, narrowed by the
    /// search box and optionally to a single part.
    var filteredHistory: [ConsumptionEntry] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return consumed }
        let terms = q.split(separator: " ").map(String.init)
        return consumed.filter { e in
            let hay = [e.partNumber, e.name, e.project].joined(separator: " ").lowercased()
            return terms.allSatisfy { hay.contains($0) }
        }
    }

    /// The list the main view renders, after search + filters + sort.
    var filtered: [Component] {
        var out = components

        switch section {
        case .dashboard:
            break
        case .all:
            break
        case .lowStock:
            out = out.filter { $0.isLowStock && !$0.isOutOfStock }
        case .outOfStock:
            out = out.filter { $0.isOutOfStock }
        case .categories:
            if let cat = categoryFilter { out = out.filter { $0.category == cat } }
        case .history:
            // The log has its own list; the component table is not shown.
            return []
        }

        if let cat = categoryFilter, section != .categories {
            out = out.filter { $0.category == cat }
        }

        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            let terms = q.split(separator: " ").map(String.init)
            out = out.filter { c in
                terms.allSatisfy { c.searchHaystack.contains($0) }
            }
        }

        return sortComponents(out)
    }

    private func sortComponents(_ list: [Component]) -> [Component] {
        let asc = sortAscending
        func cmp<T: Comparable>(_ a: T, _ b: T) -> Bool { asc ? a < b : a > b }
        return list.sorted { a, b in
            switch sortField {
            case .partNumber: return cmp(a.partNumber.lowercased(), b.partNumber.lowercased())
            case .name:       return cmp(a.name.lowercased(), b.name.lowercased())
            case .category:   return cmp(a.category, b.category)
            case .quantity:   return cmp(a.quantity, b.quantity)
            case .location:   return cmp(a.location.lowercased(), b.location.lowercased())
            case .value:      return cmp(a.value.lowercased(), b.value.lowercased())
            case .totalValue: return cmp(a.totalValue, b.totalValue)
            case .updatedAt:  return cmp(a.updatedAt, b.updatedAt)
            }
        }
    }

    func sort() {
        components = sortComponents(components)
    }

    func resetFilters() {
        searchText = ""
        categoryFilter = nil
    }

    // MARK: Sample data

    /// Realistic starter inventory, used for the render harness and available
    /// as a convenience for first run.
    static func seedComponents() -> [Component] {
        func make(_ pn: String, _ name: String, _ cat: String, _ qty: Int, _ min: Int,
                  _ loc: String, value: String = "", fp: String = "", tol: String = "",
                  vr: String = "", mfr: String = "", sup: String = "", unit: Double = 0,
                  proj: String = "", notes: String = "") -> Component {
            var c = Component()
            c.partNumber = pn; c.name = name; c.category = cat
            c.quantity = qty; c.minimumStock = min; c.location = loc
            c.value = value; c.footprint = fp; c.tolerance = tol; c.voltageRating = vr
            c.manufacturer = mfr; c.supplier = sup; c.unitCost = unit
            c.project = proj; c.notes = notes
            return c
        }
        return [
            make("RC0805FR-0710KL", "10kΩ 1% thick film resistor", Categories.resistors, 480, 200,
                 "Drawer A / Bin 04", value: "10k", fp: "0805", tol: "±1%", vr: "200V",
                 mfr: "Yageo", sup: "element14", unit: 1.20, proj: "Line Follower"),
            make("RC0603FR-0747KL", "47kΩ 1% resistor", Categories.resistors, 120, 150,
                 "Drawer A / Bin 04", value: "47k", fp: "0603", tol: "±1%", vr: "100V",
                 mfr: "Yageo", sup: "element14", unit: 0.80, proj: "Line Follower",
                 notes: "Below minimum — reorder"),
            make("CL05B104KO5NNNC", "100nF 16V X7R ceramic", Categories.capacitors, 900, 300,
                 "Drawer A / Bin 07", value: "100nF", fp: "0402", tol: "±10%", vr: "16V",
                 mfr: "Samsung", sup: "Robu", unit: 0.45, proj: "Line Follower"),
            make("ATMEGA328P-AU", "8-bit AVR MCU, 32-pin", Categories.micros, 6, 10,
                 "Anti-static Box 1", fp: "TQFP-32", mfr: "Microchip", sup: "element14",
                 unit: 185.00, proj: "Line Follower", notes: "Low stock"),
            make("LM358DR", "Dual op-amp", Categories.ics, 22, 10, "Drawer B / Bin 02",
                 fp: "SOIC-8", mfr: "Texas Instruments", sup: "element14", unit: 22.00,
                 proj: "Sensor Board"),
            make("LED-0603-RED", "Red LED 620nm", Categories.leds, 340, 100,
                 "Drawer B / Bin 05", value: "Red", fp: "0603", sup: "Robu", unit: 2.50,
                 proj: "Status Panel"),
            make("HC-SR04", "Ultrasonic distance sensor", Categories.modules, 4, 3,
                 "Shelf 1", sup: "Robu", unit: 320.00, proj: "Line Follower"),
            make("BREAD-830", "830-point solderless breadboard", Categories.tools, 2, 1,
                 "Bench Shelf", sup: "Robu", unit: 540.00, proj: "Workshop"),
            make("PUSHBTN-6MM", "6mm tactile switch", Categories.switches, 0, 25,
                 "Drawer C / Bin 01", value: "6mm", sup: "Robu", unit: 5.00,
                 proj: "UI Panel", notes: "Out of stock — reorder"),
            make("USB-C-PWR", "USB-C breakout board", Categories.modules, 3, 2,
                 "Shelf 1", sup: "Amazon.in", unit: 430.00, proj: "Bench PSU"),
        ]
    }

    // MARK: Import / Export

    /// Whole-inventory replacement. One undo step regardless of how many rows
    /// came in — "Undo: Import 40 components", not 40 separate steps.
    func replaceAll(with newComponents: [Component]) {
        let sanitized = newComponents.map(sanitizeComponent)
        recordUndo(sanitized.isEmpty
                   ? "Delete everything"
                   : "Replace with \(sanitized.count) components")
        components = sanitized
        sort()
        save()
    }

    func merge(imported: [Component]) {
        guard !imported.isEmpty else { return }
        let sanitized = imported.map(sanitizeComponent)
        // Also one step: an import is a single deliberate act, not N edits.
        recordUndo("Merge \(sanitized.count) component\(sanitized.count == 1 ? "" : "s")")
        var index: [String: Int] = [:]
        for (i, c) in components.enumerated() {
            let key = c.partNumber.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !key.isEmpty { index[key] = i }
        }
        for var c in sanitized {
            let key = c.partNumber.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !key.isEmpty, let i = index[key] {
                // Sum quantities rather than creating a duplicate line.
                components[i].quantity = validateQuantity(components[i].quantity + c.quantity)
                if components[i].name.isEmpty { components[i].name = c.name }
                if components[i].location.isEmpty { components[i].location = c.location }
                components[i].updatedAt = Date()
            } else {
                c.id = UUID()
                components.append(c)
                if !key.isEmpty { index[key] = components.count - 1 }
            }
        }
        sort()
        save()
    }
}
