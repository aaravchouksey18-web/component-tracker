import Foundation

// MARK: - Component model

struct Component: Identifiable, Codable, Hashable {
    var id: UUID = UUID()

    // Identity
    var partNumber: String = ""
    var name: String = ""
    var category: String = Categories.other

    // Stock
    var quantity: Int = 0
    var minimumStock: Int = 0
    var location: String = ""

    // Procurement
    var manufacturer: String = ""
    var supplier: String = ""
    var orderNumber: String = ""
    var unitCost: Double = 0
    var dateOrdered: Date? = nil
    var dateReceived: Date? = nil
    var project: String = ""

    // Electronic / breadboard specifics
    var value: String = ""
    var footprint: String = ""
    var tolerance: String = ""
    var voltageRating: String = ""
    var datasheetURL: String = ""
    var notes: String = ""

    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // Derived
    var totalValue: Double { Double(quantity) * unitCost }

    var isLowStock: Bool { minimumStock > 0 && quantity <= minimumStock }
    var isOutOfStock: Bool { quantity <= 0 }
    var stockLevel: StockLevel {
        if isOutOfStock { return .out }
        if isLowStock { return .low }
        return .ok
    }

    enum StockLevel { case ok, low, out }

    /// Everything the free-text search scans.
    var searchHaystack: String {
        [partNumber, name, category, location, manufacturer, supplier,
         orderNumber, project, value, footprint, tolerance, voltageRating, notes]
            .joined(separator: " ")
            .lowercased()
    }
}

enum Categories {
    static let resistors      = "Resistors"
    static let capacitors     = "Capacitors"
    static let inductors      = "Inductors"
    static let diodes         = "Diodes"
    static let leds           = "LEDs"
    static let transistors    = "Transistors"
    static let mosfets        = "MOSFETs"
    static let ics            = "ICs"
    static let micros         = "Microcontrollers"
    static let sensors        = "Sensors"
    static let modules        = "Modules"
    static let displays       = "Displays"
    static let connectors     = "Connectors"
    static let switches       = "Switches"
    static let relays         = "Relays"
    static let crystals       = "Crystals"
    static let transformers   = "Transformers"
    static let fuses          = "Fuses"
    static let antennas       = "Antennas"
    static let cables         = "Cables"
    static let pcbs           = "PCBs"
    static let mechanical     = "Mechanical"
    static let tools          = "Tools"
    static let other          = "Other"

    static let all: [String] = [
        resistors, capacitors, inductors, diodes, leds, transistors, mosfets,
        ics, micros, sensors, modules, displays, connectors, switches, relays,
        crystals, transformers, fuses, antennas, cables, pcbs, mechanical, tools, other
    ]

    /// Groups that get a matching category accent colour.
    static func tint(for category: String) -> ColorRef {
        switch category {
        case resistors, capacitors, inductors: return .teal
        case diodes, leds: return .amber
        case transistors, mosfets, ics, micros: return .violet
        case sensors, modules, displays: return .blue
        case connectors, switches, relays, crystals: return .green
        case pcbs, mechanical, tools: return .orange
        default: return .gray
        }
    }

    /// Palette wrapper so Model.swift stays free of SwiftUI imports.
    enum ColorRef { case teal, amber, violet, blue, green, orange, gray }
}

// MARK: - Consumption log

/// One recorded take-out. Deliberately *not* nested inside `Component`: a log
/// entry is a historical fact, and a fact should not vanish because the record
/// it refers to was deleted. `componentID` may therefore dangle.
struct ConsumptionEntry: Identifiable, Codable, Hashable {
    enum Kind: String, Codable {
        case used      // units left the inventory
        case returned  // units put back, e.g. an unused spares pack
    }

    var id: UUID = UUID()
    var componentID: UUID = UUID()
    /// Denormalised from the component at the time of the take-out, so the log
    /// still reads correctly after the part is renamed or deleted.
    var partNumber: String = ""
    var name: String = ""
    var quantity: Int = 0
    var date: Date = Date()
    var project: String = ""
    /// Stock on hand immediately after this entry was applied — lets the log
    /// show the trend without having to replay every entry.
    var resultingStock: Int = 0
    var kind: Kind = .used

    /// Signed for display and for summing "net used".
    var signedQuantity: Int { kind == .used ? quantity : -quantity }

    /// Part number if there is one, otherwise the description.
    var displayPart: String {
        if !partNumber.isEmpty { return partNumber }
        return name.isEmpty ? "Untitled" : name
    }

    var subtitle: String {
        if !name.isEmpty && name != partNumber { return name }
        return ""
    }
}

// MARK: - Inventory document (on-disk shape)

struct Inventory: Codable {
    var components: [Component] = []
    var consumed: [ConsumptionEntry] = []
    var version: Int = 2

    private enum CodingKeys: String, CodingKey {
        case components, consumed, version
    }

    init(components: [Component] = [], consumed: [ConsumptionEntry] = [], version: Int = 2) {
        self.components = components
        self.consumed = consumed
        self.version = version
    }

    /// Hand-written on purpose. The compiler's synthesised `init(from:)` treats
    /// every stored property as *required* and throws `keyNotFound` for a
    /// missing one, no matter what default the property declares — so adding
    /// `consumed` would make every inventory.json written by an earlier build
    /// fail to load, and the store's "unreadable file" path would move the
    /// user's whole inventory aside and start from empty.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        components = try container.decodeIfPresent([Component].self, forKey: .components) ?? []
        consumed   = try container.decodeIfPresent([ConsumptionEntry].self, forKey: .consumed) ?? []
        version     = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
    }
}
