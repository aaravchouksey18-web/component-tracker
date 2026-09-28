import SwiftUI
import Combine

// MARK: - View state holders
//
// NOTE: this toolchain ships SwiftUI without the `SwiftUIMacros` compiler plugin, so the
// `@State` property wrapper cannot expand (it resolves to a macro in the macOS 27 SDK).
// `@StateObject` / `@Published` are ordinary property wrappers and work fine, so all
// view-local state lives in these small ObservableObject holders instead.

@MainActor
final class MainViewUI: ObservableObject {
    /// Identifiable rather than a Bool, so "save and add another" can re-present
    /// the sheet reliably — flipping a Boolean false-then-true in the same turn
    /// is silently ignored by SwiftUI.
    @Published var editorRequest: EditorRequest? = nil
    @Published var showSettings = false
    @Published var showExport = false
    @Published var showDeleteConfirm = false
    @Published var selection: Set<UUID> = []
    @Published var takeOutTarget: Component? = nil
}

struct EditorRequest: Identifiable, Equatable {
    var id = UUID()
    /// nil = new component
    var component: Component?
    /// Opened as part of a bulk-entry run: save and immediately present a blank one.
    var rapid = false

    static func new(rapid: Bool = false) -> EditorRequest { EditorRequest(component: nil, rapid: rapid) }
    static func edit(_ c: Component) -> EditorRequest { EditorRequest(component: c) }
}

@MainActor
final class EditorUI: ObservableObject {
    @Published var draft: Component {
        didSet {
            // Clamp numeric values
            if draft.quantity < 0 { draft.quantity = 0 }
            if draft.quantity > 1_000_000 { draft.quantity = 1_000_000 }
            if draft.minimumStock < 0 { draft.minimumStock = 0 }
            if draft.minimumStock > 1_000_000 { draft.minimumStock = 1_000_000 }
            if draft.unitCost < 0 { draft.unitCost = 0 }
            if draft.unitCost > 10_000_000 { draft.unitCost = 10_000_000 }
        }
    }
    @Published var hasOrdered: Bool
    @Published var hasReceived: Bool
    @Published var showDeleteConfirm = false
    /// Set when the part number typed matches a component already in the inventory.
    @Published var duplicateOf: Component? = nil

    init(draft: Component) {
        self.draft = draft
        self.hasOrdered = draft.dateOrdered != nil
        self.hasReceived = draft.dateReceived != nil
    }
}

@MainActor
final class TakeOutUI: ObservableObject {
    @Published var count = 1 {
        didSet {
            if count < 0 { count = 0 }
            if count > 1_000_000 { count = 1_000_000 }
        }
    }
    @Published var project = ""
}

@MainActor
final class SettingsUI: ObservableObject {
    @Published var showResetConfirm = false
}

@MainActor
final class HistoryUI: ObservableObject {
    @Published var showClearConfirm = false
}

@MainActor
final class ExportUI: ObservableObject {
    @Published var status: String? = nil
    @Published var isError = false
    @Published var mergeMode = true

    func report(_ message: String, error: Bool = false) {
        status = message
        isError = error
    }
}

@MainActor
final class TableUI: ObservableObject {
    @Published var sortOrder: [KeyPathComparator<Component>] = [
        KeyPathComparator(\.partNumber, order: .forward)
    ]
}
