import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Settings

struct SettingsSheet: View {
    @EnvironmentObject private var store: InventoryStore
    @EnvironmentObject private var pi: PiSyncController
    @Environment(\.dismiss) private var dismiss

    @StateObject private var ui = SettingsUI()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.ui(15, .semibold))
                    .foregroundStyle(Palette.textHi)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.textMid)
                }
                .buttonStyle(.plain)
            }
            .padding(Metrics.pad)

            Divider().overlay(Palette.line)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    piSection
                    dataSection
                }
                .padding(Metrics.pad)
            }

            Divider().overlay(Palette.line)
            HStack { Spacer(); GhostButton(title: "Done", prominent: true) { dismiss() } }
                .padding(.horizontal, Metrics.pad)
                .padding(.vertical, 13)
        }
        .frame(width: 540, height: 560)
        .background(Palette.bg)
    }

    private var piSection: some View {
        FieldGroup("Raspberry Pi backup") {
            Toggle("Enable Pi sync", isOn: $pi.config.enabled)
                .toggleStyle(.switch).controlSize(.small)
                .font(.ui(12))
                .foregroundStyle(Palette.textHi)

            HStack(spacing: 12) {
                LabeledField("Host") {
                    TextField("pi.local", text: $pi.config.host)
                        .monoField()
                        .onChange(of: pi.config.host) { _, v in
                            // Sanitize host input - only allow alphanumeric, dots, hyphens
                            let sanitized = v.filter { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == ":" }
                            if sanitized != v { pi.config.host = sanitized }
                        }
                }
                LabeledField("SSH port") {
                    TextField("22", value: $pi.config.port, format: .number)
                        .monoField()
                        .onChange(of: pi.config.port) { _, v in
                            if v < 1 { pi.config.port = 1 }
                            if v > 65535 { pi.config.port = 65535 }
                        }
                }
            }
            HStack(spacing: 12) {
                LabeledField("User") {
                    TextField(NSUserName(), text: $pi.config.user)
                        .monoField()
                        .onChange(of: pi.config.user) { _, v in
                            // Sanitize user - only alphanumeric, underscore, hyphen
                            let sanitized = v.filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
                            if sanitized != v { pi.config.user = sanitized }
                        }
                }
                LabeledField("Remote folder") {
                    TextField("~/component-tracker", text: $pi.config.remoteDir)
                        .monoField()
                        .onChange(of: pi.config.remoteDir) { _, v in
                            // Basic sanitization for path
                            let sanitized = v.filter { !$0.isNewline && !$0.isWhitespace || $0 == " " || $0 == "/" || $0 == "~" || $0 == "-" || $0 == "_" || $0 == "." || $0.isLetter || $0.isNumber }
                            if sanitized != v { pi.config.remoteDir = sanitized }
                        }
                }
            }

            HStack(spacing: 9) {
                GhostButton(title: pi.isSyncing ? "Working…" : "Test Connection",
                            systemImage: "network") {
                    pi.testConnection()
                }
                .disabled(pi.isSyncing)

                GhostButton(title: "Back Up Now", systemImage: "arrow.up.doc",
                            prominent: true) {
                    pi.sync(components: store.components, consumed: store.consumed)
                }
                .disabled(!pi.config.enabled || pi.isSyncing)
            }

            if let r = pi.lastResult {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: r.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                    Text(message(r))
                        .font(.ui(11))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(tone(r))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(tone(r).opacity(0.10)))
            }

            if let v = pi.lastVerified {
                Text("Last push verified — \(PiSyncController.byteText(v.bytes)), sha256 \(v.sha)…")
                    .font(.ui(10))
                    .foregroundStyle(Palette.textLow)
            }

            HStack(spacing: 12) {
                LabeledField("Keep last N backups") {
                    HStack(spacing: 5) {
                        TextField("50", value: $pi.config.keepSnapshots, format: .number)
                            .monoField()
                            .onChange(of: pi.config.keepSnapshots) { _, v in
                                if v < 0 { pi.config.keepSnapshots = 0 }
                                if v > 1000 { pi.config.keepSnapshots = 1000 }
                            }
                        Text("0 = all")
                            .font(.ui(10))
                            .foregroundStyle(Palette.textLow)
                    }
                }
                Spacer(minLength: 0)
            }

            if let d = pi.lastSyncDate {
                Text("Last backup \(d.formatted(date: .abbreviated, time: .shortened))")
                    .font(.ui(10))
                    .foregroundStyle(Palette.textLow)
            }
            
            // Security note
            Text("Security: SSH host keys must be pre-accepted. Run `ssh-keyscan -H <host> >> ~/.ssh/known_hosts` on first use.")
                .font(.ui(9))
                .foregroundStyle(Palette.textLow)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var dataSection: some View {
        FieldGroup("Data") {
            VStack(alignment: .leading, spacing: 5) {
                Text(InventoryStore.inventoryFile.path)
                    .font(.mono(10))
                    .foregroundStyle(Palette.textMid)
                    .textSelection(.enabled)
                    .lineLimit(3)
                    .truncationMode(.middle)
                Text("Every change is written to this file automatically. Use “Save Snapshot…” or the Pi backup for off-Mac copies — this file is personal data and is never part of the app's repository.")
                    .font(.ui(10))
                    .foregroundStyle(Palette.textLow)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 9) {
                GhostButton(title: "Reveal in Finder", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([InventoryStore.inventoryFile])
                }
                GhostButton(title: "Save Snapshot…", systemImage: "square.and.arrow.down") {
                    writeSnapshot()
                }
            }

            HStack(spacing: 9) {
                GhostButton(title: "Load Sample Data", systemImage: "sparkles") {
                    store.replaceAll(with: InventoryStore.seedComponents())
                    store.notify("Loaded 10 sample components")
                }
                Spacer(minLength: 0)
            }
            Text("Fills the app with 10 example parts so you can see how everything works. Settings ▸ Data ▸ Delete All clears them.")
                .font(.ui(10))
                .foregroundStyle(Palette.textLow)
                .fixedSize(horizontal: false, vertical: true)

            Divider().overlay(Palette.lineSoft)

            GhostButton(title: "Delete All Components", systemImage: "trash") {
                ui.showResetConfirm = true
            }
            .confirmationDialog("Delete all \(store.components.count) components?",
                                isPresented: $ui.showResetConfirm, titleVisibility: .visible) {
                Button("Delete Everything", role: .destructive) {
                    store.replaceAll(with: [])
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This wipes the inventory file. Export a backup first.")
            }
        }
    }

    private func isSuccess(_ r: PiSyncResult) -> Bool { r.isSuccess }

    /// A checksum mismatch is its own colour — it's a data-integrity warning,
    /// not a network warning, and reads wrong in the same amber as "can't connect".
    private func tone(_ r: PiSyncResult) -> Color {
        r.isSuccess ? Palette.good : (r.isCorrupt ? Palette.danger : Palette.warn)
    }

    private func message(_ r: PiSyncResult) -> String {
        switch r {
        case .success(let m): return m
        case .failure(let m): return m
        case .corrupt(let m): return m
        }
    }

    private func writeSnapshot() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "component-tracker-\(Date().formatted(.iso8601.year().month().day())).json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.message = "Save an inventory snapshot"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? ExportService.json(from: store.components, consumed: store.consumed).data(using: .utf8)?.write(to: url, options: .atomic)
    }
}

// MARK: - Export / Import

struct ExportSheet: View {
    @EnvironmentObject private var store: InventoryStore
    @Environment(\.dismiss) private var dismiss

    @StateObject private var ui = ExportUI()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Export / Import")
                    .font(.ui(15, .semibold))
                    .foregroundStyle(Palette.textHi)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.textMid)
                }
                .buttonStyle(.plain)
            }
            .padding(Metrics.pad)

            Divider().overlay(Palette.line)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    exportGroup
                    Divider().overlay(Palette.lineSoft)
                    importGroup
                }
                .padding(Metrics.pad)
            }

            if let status = ui.status {
                Divider().overlay(Palette.line)
                HStack(spacing: 7) {
                    Image(systemName: ui.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 10))
                    Text(status).font(.ui(11))
                }
                .foregroundStyle(ui.isError ? Palette.warn : Palette.good)
                .padding(.horizontal, Metrics.pad).padding(.bottom, 12)
            }
        }
        .frame(width: 540, height: 500)
        .background(Palette.bg)
    }

    private var exportGroup: some View {
        let shown = store.filtered.count
        return FieldGroup("Export") {
            exportRow("CSV — all \(shown) shown component\(shown == 1 ? "" : "s")",
                      detail: "What the list shows right now — clear search/filters first for the whole inventory",
                      icon: "tablecells") {
                save(contents: ExportService.csv(from: store.filtered),
                     name: "component-inventory.csv",
                     type: .commaSeparatedText)
            }
            exportRow("JSON backup — all \(store.components.count) component\(store.components.count == 1 ? "" : "s")",
                      detail: "Lossless full document — parts hidden by a search or filter are included",
                      icon: "curlybraces") {
                save(contents: ExportService.json(from: store.components,
                                                 consumed: store.consumed),
                     name: "component-inventory.json",
                     type: .json)
            }
            exportRow("Usage log CSV",
                      detail: store.consumed.isEmpty
                          ? "Nothing logged yet — take some parts out first"
                          : "\(store.consumed.count) entr\(store.consumed.count == 1 ? "y" : "ies"), one row per take-out",
                      icon: "clock.arrow.circlepath") {
                save(contents: ExportService.consumptionCSV(from: store.consumed),
                     name: "component-usage-log.csv",
                     type: .commaSeparatedText)
            }
            .disabled(store.consumed.isEmpty)
        }
    }

    private var importGroup: some View {
        FieldGroup("Import") {
            Picker("Mode", selection: $ui.mergeMode) {
                Text("Merge — combine quantities for matching part numbers").tag(true)
                Text("Replace — discard existing and use the file").tag(false)
            }
            .pickerStyle(.radioGroup)
            .font(.ui(11))
            .foregroundStyle(Palette.textMid)
            .controlSize(.small)

            HStack(spacing: 9) {
                GhostButton(title: "Import CSV…", systemImage: "square.and.arrow.down") { pickFile(isCSV: true) }
                GhostButton(title: "Import JSON…", systemImage: "square.and.arrow.down") { pickFile(isCSV: false) }
            }

            Text("Merge adds quantities when the part number already exists, and ignores rows with no part number or name.")
                .font(.ui(10))
                .foregroundStyle(Palette.textLow)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func exportRow(_ title: String, detail: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .light))
                    .foregroundStyle(Palette.textMid)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.ui(12, .medium)).foregroundStyle(Palette.textHi)
                    Text(detail).font(.ui(10)).foregroundStyle(Palette.textLow)
                }
                Spacer(minLength: 8)
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textLow)
            }
            .padding(11)
            .panel()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func save(contents: String, name: String, type: UTType) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try contents.data(using: .utf8)?.write(to: url, options: .atomic)
            ui.report("Exported to \(url.lastPathComponent)")
        } catch {
            ui.report("Export failed: \(error.localizedDescription)", error: true)
        }
    }

    private func pickFile(isCSV: Bool) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = isCSV ? [.commaSeparatedText, .text] : [.json]
        panel.allowsMultipleSelection = false
        panel.message = isCSV ? "Choose a CSV file" : "Choose a JSON backup"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let imported: [Component]?
            if isCSV {
                let rows = ExportService.parseCSV(text)
                imported = rows.isEmpty ? nil : rows
            } else {
                imported = ExportService.parseJSON(text)
            }

            guard let list = imported, !list.isEmpty else {
                ui.report("No components found in that file.", error: true)
                return
            }

            if ui.mergeMode {
                store.merge(imported: list)
                ui.report("Merged \(list.count) component\(list.count == 1 ? "" : "s").")
            } else {
                store.replaceAll(with: list)
                ui.report("Replaced inventory with \(list.count) component\(list.count == 1 ? "" : "s").")
            }
        } catch {
            ui.report("Could not read file: \(error.localizedDescription)", error: true)
        }
    }
}
