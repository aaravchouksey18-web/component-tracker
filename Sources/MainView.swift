import SwiftUI

@main
struct ComponentTrackerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = InventoryStore()
    @StateObject private var pi = PiSyncController()
    // Owned here rather than inside MainView: the menu bar is not part of the
    // view hierarchy, so ⌘N needs a handle on the same instance the window uses.
    @StateObject private var ui = MainViewUI()

    var body: some Scene {
        WindowGroup {
            MainView(ui: ui)
                .preferredColorScheme(.dark)
                .tint(Palette.accent)
        }
        .defaultSize(width: 1180, height: 760)
        .environmentObject(store)
        .environmentObject(pi)
        // Passed in explicitly. Menu-bar Commands are not part of the view
        // hierarchy, so neither the window's nor the scene's environment objects
        // are visible here — reading one traps at launch. Observe them directly.
        .commands { AppCommands(store: store, pi: pi, ui: ui) }
    }
}

/// Makes sure nothing is lost if the app is quit with a debounced write pending.
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Copies of this app can exist in more than one place (/Applications, Desktop,
    /// a build folder). Without a guard, two instances would write the same
    /// inventory.json concurrently and silently lose an edit, so hand off to the
    /// already-running instance and step aside.
    func applicationDidFinishLaunching(_ notification: Notification) {
        let myID = Bundle.main.bundleIdentifier ?? ""
        guard !myID.isEmpty else { return }
        let me = ProcessInfo.processInfo.processIdentifier
        let siblings = NSRunningApplication.runningApplications(withBundleIdentifier: myID)
            .filter { $0.processIdentifier != me && !$0.isTerminated }

        if let other = siblings.first {
            other.activate(options: [.activateAllWindows])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                NSApp.terminate(nil)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            InventoryStore.shared?.flush()
        }
    }
}

struct AppCommands: Commands {
    @ObservedObject var store: InventoryStore
    @ObservedObject var pi: PiSyncController
    @ObservedObject var ui: MainViewUI

    var body: some Commands {
        // Each group is anchored to its own slot. Putting "Save Now" in the
        // .newItem replacement instead left the .saveItem anchor pointing at a
        // group that no longer existed, which left two bare separators stacked
        // together in the File menu.
        CommandGroup(replacing: .newItem) {
            // ⌘N lives here, not on the toolbar button: menu commands fire even
            // when a sheet owns the key window, which is where a bulk-entry run
            // spends most of its time.
            Button("New Component") { MainView.presentEditor(.new(), in: ui) }
                .keyboardShortcut("n", modifiers: .command)
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save Now") { store.flush() }
                .keyboardShortcut("s", modifiers: .command)
        }
        // Replaces the system group outright. SwiftUI's own Undo/Redo items are
        // driven by an UndoManager the views never register with, so they were
        // permanently greyed out; these are wired to the store instead and carry
        // the action's name, so the menu reads "Undo Delete HC-SR04".
        CommandGroup(replacing: .undoRedo) {
            Button(store.undoLabel.map { "Undo \($0)" } ?? "Undo") { store.undo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(store.undoLabel == nil)
            Button(store.redoLabel.map { "Redo \($0)" } ?? "Redo") { store.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(store.redoLabel == nil)
        }
        // ⌘B — the one-button push, straight from anywhere in the app.
        CommandGroup(after: .saveItem) {
            Button("Back Up to Pi") {
                store.flush()
                pi.sync(components: store.components, consumed: store.consumed)
            }
            .keyboardShortcut("b", modifiers: .command)
            .disabled(!pi.config.enabled || pi.isSyncing)
        }
    }
}

// MARK: - Root

struct MainView: View {
    @EnvironmentObject private var store: InventoryStore
    @EnvironmentObject private var pi: PiSyncController

    /// Owned by the `App` struct so the menu bar can reach the same instance.
    @ObservedObject var ui: MainViewUI

    var body: some View {
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 196, ideal: 210, max: 260)
        } detail: {
            detail
                .background(Palette.bg)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbarBackground(Palette.bg, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .toolbar { toolbarContent }
        .sheet(item: $ui.editorRequest) { req in
            ComponentEditor(
                component: req.component,
                rapid: req.rapid,
                onSave: { keepGoing in
                    if keepGoing { Self.presentEditor(.new(rapid: true), in: ui) }
                },
                onEditExisting: { existing in
                    Self.presentEditor(.edit(existing), in: ui)
                }
            )
            .environmentObject(store)
        }
        .sheet(item: $ui.takeOutTarget) { c in
            TakeOutSheet(component: c)
                .environmentObject(store)
        }
        .sheet(isPresented: $ui.showSettings) {
            SettingsSheet()
                .environmentObject(store)
                .environmentObject(pi)
        }
        .sheet(isPresented: $ui.showExport) {
            ExportSheet()
                .environmentObject(store)
        }
        .confirmationDialog(
            ui.selection.isEmpty
                ? "Delete “\(store.filtered.first { ui.selection.contains($0.id) }?.name ?? "")”?"
                : "Delete \(ui.selection.count) selected component\(ui.selection.count == 1 ? "" : "s")?",
            isPresented: $ui.showDeleteConfirm, titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                store.delete(ids: ui.selection)
                ui.selection.removeAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the record permanently. Export a backup first if unsure.")
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch store.section {
        case .dashboard:
            DashboardView()
        case .history:
            HistoryView(onOpenPart: { id in
                // Jumping from the log back to a part: land on All Components
                // with the search narrowed to that part number, which is the
                // only way to find a record that has since been renamed.
                store.section = .all
                store.categoryFilter = nil
                if let c = store.components.first(where: { $0.id == id }) {
                    store.searchText = c.partNumber.isEmpty ? c.name : c.partNumber
                }
            })
        default:
            componentsList
        }
    }

    private var componentsList: some View {
        VStack(spacing: 0) {
            listHeader
            Divider().overlay(Palette.lineSoft)
            if store.filtered.isEmpty {
                emptyState
            } else if store.cardView {
                ComponentCardGrid(components: store.filtered,
                                  selection: $ui.selection,
                                  onEdit: { edit($0) },
                                  onTakeOut: { ui.takeOutTarget = $0 },
                                  onDelete: { confirmDelete([$0]) })
            } else {
                ComponentTable(components: store.filtered,
                               selection: $ui.selection,
                               onEdit: { edit($0) },
                               onTakeOut: { ui.takeOutTarget = $0 },
                               onDelete: { confirmDelete([$0]) })
            }
        }
    }

    private var listHeader: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(titleText)
                    .font(.ui(16, .semibold))
                    .foregroundStyle(Palette.textHi)
                Text("\(store.filtered.count) of \(store.components.count) component\(store.components.count == 1 ? "" : "s")")
                    .font(.ui(11))
                    .foregroundStyle(Palette.textLow)
            }

            Spacer(minLength: 12)

            if !ui.selection.isEmpty {
                HStack(spacing: 8) {
                    Text("\(ui.selection.count) selected")
                        .font(.mono(11))
                        .foregroundStyle(Palette.textMid)
                    GhostButton(title: "Take Out", systemImage: "minus.circle") {
                        if let first = store.filtered.first(where: { ui.selection.contains($0.id) }) {
                            ui.takeOutTarget = first
                        }
                    }
                    GhostButton(title: "Delete", systemImage: "trash") { ui.showDeleteConfirm = true }
                    GhostButton(title: "Clear") { ui.selection.removeAll() }
                }
            } else {
                if let cat = store.categoryFilter {
                    Button {
                        store.categoryFilter = nil
                    } label: {
                        HStack(spacing: 5) {
                            Text(cat).font(.ui(10, .semibold))
                            Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                        }
                        .foregroundStyle(Palette.textMid)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(Palette.panelHi))
                        .overlay(Capsule().strokeBorder(Palette.line, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                SearchField(text: $store.searchText)
                viewToggle
            }
        }
        .padding(.horizontal, Metrics.pad)
        .padding(.vertical, 13)
    }

    private var titleText: String {
        if store.section == .categories, let cat = store.categoryFilter { return cat }
        return store.section.label
    }

    private var viewToggle: some View {
        HStack(spacing: 2) {
            iconToggle(isOn: !store.cardView, icon: "list.bullet", help: "Table view") {
                store.cardView = false
            }
            iconToggle(isOn: store.cardView, icon: "square.grid.2x2", help: "Card view") {
                store.cardView = true
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: Metrics.cornerSm, style: .continuous).fill(Palette.panel))
        .overlay(RoundedRectangle(cornerRadius: Metrics.cornerSm, style: .continuous)
            .strokeBorder(Palette.lineSoft, lineWidth: 1))
    }

    private func iconToggle(isOn: Bool, icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isOn ? Color.black : Palette.textMid)
                .frame(width: 26, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isOn ? Palette.accent : .clear)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    @ViewBuilder
    private var emptyState: some View {
        if store.components.isEmpty {
            EmptyStateView(systemImage: "tray",
                           title: "No components yet",
                           message: "Add your first component to start tracking stock, locations and orders.")
        } else {
            EmptyStateView(systemImage: "magnifyingglass",
                           title: "No matches",
                           message: "Nothing matches your search or filters. Try clearing them.")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                store.flush()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
            .help("Save now")
            .disabled(store.components.isEmpty)

            Button { ui.showExport = true } label: { Image(systemName: "square.and.arrow.up") }
                .help("Export / Import")

            Button {
                store.flush()
                pi.sync(components: store.components, consumed: store.consumed)
            } label: {
                Image(systemName: pi.isSyncing
                      ? "arrow.up.doc.fill"
                      : "externaldrive.connected.to.line.below")
            }
            .help(pi.isSyncing ? "Backing up to Pi…" : "Back up to Raspberry Pi (⌘B)")
            .disabled(!pi.config.enabled || pi.isSyncing || store.components.isEmpty)

            Button { ui.showSettings = true } label: { Image(systemName: "gearshape") }
                .help("Settings")

            Button {
                Self.presentEditor(.new(), in: ui)
            } label: {
                Label("Add Component", systemImage: "plus")
            }
            .help("Add component (⌘N)")
        }
    }

    /// Swaps in a different editor once the current sheet has finished dismissing.
    /// Assigning a new `item` while the old one is still on screen is silently
    /// ignored, which breaks both "add another" and the duplicate-part jump.
    @MainActor
    static func presentEditor(_ request: EditorRequest, in ui: MainViewUI) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            ui.editorRequest = request
        }
    }

    private func edit(_ c: Component) {
        Self.presentEditor(.edit(c), in: ui)
    }

    private func confirmDelete(_ items: [Component]) {
        ui.selection = Set(items.map(\.id))
        ui.showDeleteConfirm = true
    }
}

// MARK: - Search field

struct SearchField: View {
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.textLow)
            TextField("Search part number, value, location…", text: $text)
                .textFieldStyle(.plain)
                .font(.ui(12))
                .foregroundStyle(Palette.textHi)
                .focused($focused)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textLow)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .frame(width: 250)
        .background(RoundedRectangle(cornerRadius: Metrics.cornerSm, style: .continuous).fill(Palette.panel))
        .overlay(RoundedRectangle(cornerRadius: Metrics.cornerSm, style: .continuous)
            .strokeBorder(focused ? Palette.textLow : Palette.lineSoft, lineWidth: 1))
    }
}

// MARK: - Category colour mapping is in Design.swift
