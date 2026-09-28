import SwiftUI
import UniformTypeIdentifiers
import AppKit

// MARK: - Add / Edit

struct ComponentEditor: View {
    @EnvironmentObject private var store: InventoryStore
    @Environment(\.dismiss) private var dismiss

    var component: Component?
    /// Opened mid-run: the save key reopens a blank editor instead of closing.
    var rapid: Bool = false
    /// Called with `true` when the user asked to keep going.
    var onSave: ((Bool) -> Void)? = nil
    /// Called when the user clicks through to a part that already exists.
    var onEditExisting: ((Component) -> Void)? = nil

    @StateObject private var ui: EditorUI
    @FocusState private var partFieldFocused: Bool

    private var isNew: Bool { component == nil }

    init(component: Component?, rapid: Bool = false,
         onSave: ((Bool) -> Void)? = nil,
         onEditExisting: ((Component) -> Void)? = nil) {
        self.component = component
        self.rapid = rapid
        self.onSave = onSave
        self.onEditExisting = onEditExisting
        _ui = StateObject(wrappedValue: EditorUI(draft: component ?? Component()))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Palette.line)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    identitySection
                    stockSection
                    electricalSection
                    procurementSection
                    if !isNew { historySection }
                    notesSection
                }
                .padding(Metrics.pad)
            }

            Divider().overlay(Palette.line)
            footer
        }
        .frame(width: 620, height: 640)
        .background(Palette.bg)
        // Start with the cursor in the part number — the field that actually
        // identifies a part. The rest of the form is optional.
        .onAppear { partFieldFocused = true }
        // Warn before the same part gets entered twice, which silently splits
        // its stock across two rows.
        .onChange(of: ui.draft.partNumber) { _, new in
            guard isNew else { ui.duplicateOf = nil; return }
            let key = new.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty else { ui.duplicateOf = nil; return }
            ui.duplicateOf = store.components.first {
                $0.id != component?.id
                && !$0.partNumber.isEmpty
                && $0.partNumber.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == key
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(isNew ? "New Component" : "Edit Component")
                    .font(.ui(15, .semibold))
                    .foregroundStyle(Palette.textHi)
                Text(isNew ? "Fill in what you know — everything is optional"
                           : (component?.partNumber.isEmpty == false ? component!.partNumber : "Untitled"))
                    .font(.mono(10))
                    .foregroundStyle(Palette.textLow)
                    .lineLimit(1)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.textMid)
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, Metrics.pad)
        .padding(.vertical, 14)
    }

    private var footer: some View {
        HStack(spacing: 9) {
            if !isNew {
                GhostButton(title: "Delete", systemImage: "trash") { ui.showDeleteConfirm = true }
            }
            Spacer()
            if rapid {
                Text("⌘↩ add · ⌘⇧↩ add another")
                    .font(.ui(10))
                    .foregroundStyle(Palette.textLow)
            }
            GhostButton(title: "Cancel") { dismiss() }
            // ⌘↩ saves and closes. ⌘⇧↩ saves and immediately opens a blank
            // editor, so a run of parts can be keyed without touching the mouse.
            GhostButton(title: isNew ? "Add Component" : "Save Changes",
                        systemImage: "checkmark", prominent: true) { save() }
                .keyboardShortcut(.return, modifiers: .command)
            if isNew {
                GhostButton(title: isNew ? "Add & Next" : "Save & Next",
                            systemImage: "arrow.turn.down.right", prominent: true) { save(continueAdding: true) }
                    .keyboardShortcut(.return, modifiers: [.command, .shift])
            }
        }
        .padding(.horizontal, Metrics.pad)
        .padding(.vertical, 13)
        .confirmationDialog("Delete this component?", isPresented: $ui.showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let c = component { store.delete(c) }
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Sections

    private var identitySection: some View {
        FieldGroup("Identity") {
            LabeledField("Part number") {
                VStack(alignment: .leading, spacing: 5) {
                    TextField("e.g. 0805WGF1002T5E", text: $ui.draft.partNumber)
                        .monoField()
                        .focused($partFieldFocused)
                    if let dup = ui.duplicateOf {
                        duplicateNotice(dup)
                    }
                }
            }
            LabeledField("Name / description") {
                TextField("e.g. 10kΩ 1% thick film resistor", text: $ui.draft.name)
                    .plainField()
            }
            LabeledField("Category") {
                Picker("", selection: $ui.draft.category) {
                    ForEach(Categories.all, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            LabeledField("Manufacturer") {
                TextField("e.g. Yageo, TE, Murata", text: $ui.draft.manufacturer)
                    .plainField()
            }
        }
    }

    private var stockSection: some View {
        FieldGroup("Stock") {
            HStack(spacing: 12) {
                LabeledField("Quantity") {
                    StepperField(value: $ui.draft.quantity)
                }
                LabeledField("Minimum (alert below)") {
                    StepperField(value: $ui.draft.minimumStock)
                }
            }
            LabeledField("Location / bin") {
                TextField("e.g. Drawer A3, Bin 12, Shelf 2", text: $ui.draft.location)
                    .plainField()
            }
            if ui.draft.isLowStock || ui.draft.isOutOfStock {
                HStack(spacing: 7) {
                    Image(systemName: ui.draft.isOutOfStock ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                    Text(ui.draft.isOutOfStock ? "Out of stock." : "At or below the minimum of \(ui.draft.minimumStock).")
                        .font(.ui(11))
                }
                .foregroundStyle(ui.draft.isOutOfStock ? Palette.danger : Palette.warn)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 6).fill((ui.draft.isOutOfStock ? Palette.danger : Palette.warn).opacity(0.10)))
            }
        }
    }

    private var electricalSection: some View {
        FieldGroup("Electrical") {
            HStack(spacing: 12) {
                LabeledField("Value") {
                    TextField("e.g. 10k, 100nF, 12V", text: $ui.draft.value)
                        .monoField()
                }
                LabeledField("Package / footprint") {
                    TextField("e.g. 0603, SOT-23", text: $ui.draft.footprint)
                        .monoField()
                }
            }
            HStack(spacing: 12) {
                LabeledField("Tolerance") {
                    TextField("e.g. ±1%", text: $ui.draft.tolerance)
                        .monoField()
                }
                LabeledField("Voltage / rating") {
                    TextField("e.g. 50V, 1A", text: $ui.draft.voltageRating)
                        .monoField()
                }
            }
            LabeledField("Datasheet URL") {
                TextField("https://…", text: $ui.draft.datasheetURL)
                    .monoField()
            }
        }
    }

    private var procurementSection: some View {
        FieldGroup("Procurement") {
            HStack(spacing: 12) {
                LabeledField("Supplier") {
                    TextField("e.g. Mouser, Digikey", text: $ui.draft.supplier)
                        .plainField()
                }
                LabeledField("Order number") {
                    TextField("e.g. PO-2291", text: $ui.draft.orderNumber)
                        .monoField()
                }
            }
            HStack(spacing: 12) {
                LabeledField("Unit cost (\(Money.symbol))") {
                    HStack(spacing: 4) {
                        Text(Money.symbol).font(.mono(12)).foregroundStyle(Palette.textLow)
                        TextField("0.00", value: $ui.draft.unitCost, format: .number.precision(.fractionLength(0...4)))
                            .monoField()
                            .onChange(of: ui.draft.unitCost) { _, _ in
                                if ui.draft.unitCost < 0 { ui.draft.unitCost = 0 }
                            }
                    }
                }
                LabeledField("Project") {
                    TextField("e.g. Line Follower", text: $ui.draft.project)
                        .plainField()
                }
            }
            ToggleRow(title: "Ordered", isOn: $ui.hasOrdered) {
                DatePicker("", selection: orderedBinding, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
            }
            ToggleRow(title: "Received", isOn: $ui.hasReceived) {
                DatePicker("", selection: receivedBinding, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
            }
        }
    }

    private var notesSection: some View {
        FieldGroup("Notes") {
            TextField("Anything worth remembering…", text: $ui.draft.notes, axis: .vertical)
                .plainField()
                .lineLimit(3...7)
        }
    }

    // MARK: Bindings

    private var orderedBinding: Binding<Date> {
        Binding(get: { ui.draft.dateOrdered ?? Date() },
                set: { ui.draft.dateOrdered = $0 })
    }

    private var receivedBinding: Binding<Date> {
        Binding(get: { ui.draft.dateReceived ?? Date() },
                set: { ui.draft.dateReceived = $0 })
    }

    /// Shown when the part number already exists. Two rows for one part means the
    /// stock count is wrong in a way nothing in the UI will ever flag.
    private func duplicateNotice(_ dup: Component) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text("Already in your inventory — \(dup.quantity) in stock")
                    .font(.ui(10, .medium))
                Button("Edit that one instead") {
                    // Nothing typed here is worth keeping, so the partially
                    // filled draft is dropped rather than merged into the
                    // existing record.
                    onEditExisting?(dup)
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(.ui(10))
                .foregroundStyle(Palette.accent)
            }
        }
        .foregroundStyle(Palette.warn)
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 5).fill(Palette.warn.opacity(0.09)))
    }

    /// Read-only log for this part. Shows the five most recent take-outs plus a
    /// running total, rather than the whole history — the full list lives in
    /// the Usage History sidebar destination, where there is room for it.
    @ViewBuilder
    private var historySection: some View {
        let id = component?.id
        let entries = id.map { store.history(for: $0) } ?? []
        let net = entries.reduce(0) { $0 + $1.signedQuantity }

        VStack(alignment: .leading, spacing: 9) {
            HStack {
                SectionLabel("Usage history")
                Spacer()
                if net != 0 {
                    Text("\(net) net used")
                        .font(.mono(10))
                        .foregroundStyle(Palette.textMid)
                }
            }

            if entries.isEmpty {
                Text("Nothing taken out of this part yet.")
                    .font(.ui(10))
                    .foregroundStyle(Palette.textLow)
            } else {
                VStack(spacing: 0) {
                    ForEach(entries.prefix(5)) { e in
                        HStack(spacing: 9) {
                            Text(e.kind == .used ? "−\(e.quantity)" : "+\(e.quantity)")
                                .font(.mono(11, .semibold))
                                .foregroundStyle(e.kind == .used ? Palette.textHi : Palette.good)
                                .frame(width: 42, alignment: .trailing)
                            Text(e.project.isEmpty ? "No project" : e.project)
                                .font(.ui(10))
                                .foregroundStyle(e.project.isEmpty ? Palette.textLow : Palette.textMid)
                                .lineLimit(1)
                            Spacer(minLength: 6)
                            Text(HistoryView.dayStamp(e.date))
                                .font(.mono(10))
                                .foregroundStyle(Palette.textLow)
                        }
                        .padding(.vertical, 6)

                        if e.id != entries.prefix(5).last?.id {
                            Divider().overlay(Palette.lineSoft.opacity(0.6))
                        }
                    }
                }
                if entries.count > 5 {
                    Text("and \(entries.count - 5) more — see Usage History in the sidebar")
                        .font(.ui(10))
                        .foregroundStyle(Palette.textLow)
                        .padding(.top, 2)
                }
            }
        }
    }

    private func save(continueAdding: Bool = false) {
        if !ui.hasOrdered { ui.draft.dateOrdered = nil }
        if !ui.hasReceived { ui.draft.dateReceived = nil }
        
        // Sanitize inputs
        ui.draft.partNumber = ui.draft.partNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        ui.draft.name = ui.draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        ui.draft.category = ui.draft.category.trimmingCharacters(in: .whitespacesAndNewlines)
        ui.draft.location = ui.draft.location.trimmingCharacters(in: .whitespacesAndNewlines)
        ui.draft.manufacturer = ui.draft.manufacturer.trimmingCharacters(in: .whitespacesAndNewlines)
        ui.draft.supplier = ui.draft.supplier.trimmingCharacters(in: .whitespacesAndNewlines)
        ui.draft.orderNumber = ui.draft.orderNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        ui.draft.value = ui.draft.value.trimmingCharacters(in: .whitespacesAndNewlines)
        ui.draft.footprint = ui.draft.footprint.trimmingCharacters(in: .whitespacesAndNewlines)
        ui.draft.tolerance = ui.draft.tolerance.trimmingCharacters(in: .whitespacesAndNewlines)
        ui.draft.voltageRating = ui.draft.voltageRating.trimmingCharacters(in: .whitespacesAndNewlines)
        ui.draft.datasheetURL = ui.draft.datasheetURL.trimmingCharacters(in: .whitespacesAndNewlines)
        // Validate URL - only allow HTTP/HTTPS
        if !ui.draft.datasheetURL.isEmpty && !(ui.draft.datasheetURL.hasPrefix("http://") || ui.draft.datasheetURL.hasPrefix("https://")) {
            ui.draft.datasheetURL = ""
        }
        ui.draft.notes = ui.draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        ui.draft.project = ui.draft.project.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Clamp numeric values
        ui.draft.quantity = max(0, min(ui.draft.quantity, 1_000_000))
        ui.draft.minimumStock = max(0, min(ui.draft.minimumStock, 1_000_000))
        ui.draft.unitCost = max(0, min(ui.draft.unitCost, 10_000_000))

        // Continuing only makes sense while adding; editing an existing part
        // then immediately reopening a blank editor would be nonsense.
        let keepGoing = continueAdding && isNew

        if isNew {
            store.add(ui.draft)
        } else {
            store.update(ui.draft)
        }
        onSave?(keepGoing)
        dismiss()
    }
}

// MARK: - Field group

struct FieldGroup<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title)
            VStack(alignment: .leading, spacing: 9) { content }
        }
    }
}

struct LabeledField<Content: View>: View {
    var label: String
    @ViewBuilder var content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.ui(10, .medium))
                .foregroundStyle(Palette.textMid)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ToggleRow<Content: View>: View {
    var title: String
    @Binding var isOn: Bool
    @ViewBuilder var trailing: Content

    init(title: String, isOn: Binding<Bool>, @ViewBuilder trailing: () -> Content) {
        self.title = title
        self._isOn = isOn
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.mini)
            Text(title)
                .font(.ui(11, .medium))
                .foregroundStyle(Palette.textMid)
                .frame(width: 60, alignment: .leading)
            trailing
        }
    }
}

struct StepperField: View {
    @Binding var value: Int

    var body: some View {
        HStack(spacing: 4) {
            TextField("0", value: $value, format: .number)
                .monoField()
                .onChange(of: value) { _, new in if new < 0 { value = 0 } }
            Button { value = max(0, value - 1) } label: { stepIcon("minus") }
                .buttonStyle(.plain)
            Button { value += 1 } label: { stepIcon("plus") }
                .buttonStyle(.plain)
        }
    }

    private func stepIcon(_ i: String) -> some View {
        Image(systemName: i)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(Palette.textMid)
            .frame(width: 18, height: 18)
            .background(RoundedRectangle(cornerRadius: 4).fill(Palette.panelHi))
    }
}

// MARK: - Field styling

extension View {
    func plainField() -> some View {
        self.font(.ui(12))
            .foregroundStyle(Palette.textHi)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: Metrics.cornerSm, style: .continuous).fill(Palette.panel))
            .overlay(RoundedRectangle(cornerRadius: Metrics.cornerSm, style: .continuous)
                .strokeBorder(Palette.line, lineWidth: 1))
    }

    func monoField() -> some View {
        self.font(.mono(12))
            .foregroundStyle(Palette.textHi)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: Metrics.cornerSm, style: .continuous).fill(Palette.panel))
            .overlay(RoundedRectangle(cornerRadius: Metrics.cornerSm, style: .continuous)
                .strokeBorder(Palette.line, lineWidth: 1))
    }
}

// MARK: - Take out

struct TakeOutSheet: View {
    @EnvironmentObject private var store: InventoryStore
    @Environment(\.dismiss) private var dismiss

    var component: Component
    @StateObject private var ui = TakeOutUI()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Take Out")
                        .font(.ui(15, .semibold))
                        .foregroundStyle(Palette.textHi)
                    Text(component.partNumber.isEmpty ? component.name : component.partNumber)
                        .font(.mono(10))
                        .foregroundStyle(Palette.textLow)
                }
                Spacer()
                Text("\(component.quantity) on hand")
                    .font(.mono(11))
                    .foregroundStyle(Palette.textMid)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Capsule().fill(Palette.panelHi))
            }
            .padding(Metrics.pad)

            Divider().overlay(Palette.line)

            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    LabeledField("How many") {
                        StepperField(value: $ui.count)
                    }
                    LabeledField("Remaining after") {
                        Text("\(max(0, component.quantity - ui.count))")
                            .font(.mono(14, .medium))
                            .foregroundStyle(component.quantity - ui.count <= (component.minimumStock > 0 ? component.minimumStock : 0)
                                             ? Palette.warn : Palette.textHi)
                            .padding(.vertical, 7)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel("Quick amounts")
                    HStack(spacing: 6) {
                        ForEach([1, 5, 10, 25, component.quantity].filter { $0 > 0 },
                                id: \.self) { n in
                            GhostButton(title: "\(n)", prominent: ui.count == n) { ui.count = n }
                        }
                    }
                }

                LabeledField("Used for (optional)") {
                    TextField("e.g. Line Follower, node 3", text: $ui.project)
                        .plainField()
                        .onChange(of: ui.project) { _, new in
                            // Sanitize project name
                            let sanitized = new.trimmingCharacters(in: .whitespacesAndNewlines)
                            if sanitized.count > 1000 {
                                ui.project = String(sanitized.prefix(1000))
                            } else if sanitized != new {
                                ui.project = sanitized
                            }
                        }
                }

                if component.quantity - ui.count <= 0 {
                    Label("This will leave the part out of stock.", systemImage: "xmark.octagon.fill")
                        .font(.ui(11))
                        .foregroundStyle(Palette.danger)
                } else if component.minimumStock > 0 && component.quantity - ui.count <= component.minimumStock {
                    Label("This drops below the minimum of \(component.minimumStock).",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.ui(11))
                        .foregroundStyle(Palette.warn)
                }
            }
            .padding(Metrics.pad)

            Spacer(minLength: 0)

            Divider().overlay(Palette.line)

            HStack(spacing: 9) {
                Spacer()
                GhostButton(title: "Cancel") { dismiss() }
                GhostButton(title: "Take Out", systemImage: "minus.circle", prominent: true) {
                    let taken = store.takeOut(component, count: ui.count, project: ui.project)
                    if taken < ui.count {
                        // Clamped to what was available — log what actually happened.
                        store.notify("Took \(taken) — that was all that was available.")
                    }
                    dismiss()
                }
                .disabled(ui.count <= 0)
            }
            .padding(.horizontal, Metrics.pad)
            .padding(.vertical, 13)
        }
        .frame(width: 430)
        .background(Palette.bg)
    }
}
