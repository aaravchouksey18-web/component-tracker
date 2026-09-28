import Foundation

// MARK: - CSV / JSON export + import

enum ExportService {

    static let csvColumns: [(String, String)] = [
        ("Part Number", "partNumber"),
        ("Name", "name"),
        ("Category", "category"),
        ("Quantity", "quantity"),
        ("Min Stock", "minimumStock"),
        ("Location", "location"),
        ("Value", "value"),
        ("Footprint", "footprint"),
        ("Tolerance", "tolerance"),
        ("Voltage", "voltageRating"),
        ("Manufacturer", "manufacturer"),
        ("Supplier", "supplier"),
        ("Order Number", "orderNumber"),
        ("Unit Cost", "unitCost"),
        ("Total Cost", "totalValue"),
        ("Date Ordered", "dateOrdered"),
        ("Date Received", "dateReceived"),
        ("Project", "project"),
        ("Datasheet", "datasheetURL"),
        ("Notes", "notes")
    ]

    static func csv(from components: [Component]) -> String {
        var lines = [csvColumns.map { $0.0 }.map(escapeCSV).joined(separator: ",")]
        for c in components {
            let values: [String] = [
                c.partNumber, c.name, c.category,
                String(c.quantity), String(c.minimumStock), c.location,
                c.value, c.footprint, c.tolerance, c.voltageRating,
                c.manufacturer, c.supplier, c.orderNumber,
                String(format: "%.4f", c.unitCost), String(format: "%.4f", c.totalValue),
                formatDate(c.dateOrdered), formatDate(c.dateReceived),
                c.project, c.datasheetURL, c.notes
            ]
            lines.append(values.map(escapeCSV).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func escapeCSV(_ s: String) -> String {
        let needsQuote = s.contains(",") || s.contains("\"") || s.contains("\n") || s.contains("\r")
        if needsQuote {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }

    static func formatDate(_ d: Date?) -> String {
        guard let d else { return "" }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    /// Full-document export: components *and* the usage log. The log is part of
    /// the backup, not a view — a Pi snapshot without it would be a partial
    /// backup of exactly the data that is hardest to recreate.
    static func json(from components: [Component], consumed: [ConsumptionEntry] = []) -> String {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let doc = Inventory(components: components, consumed: consumed)
        guard let data = try? enc.encode(doc) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// The usage log as CSV, for pasting into a spreadsheet. Separate from the
    /// component CSV on purpose — different grain, one row per event rather than
    /// one row per part, so flattening them together would lose the distinction.
    static func consumptionCSV(from entries: [ConsumptionEntry]) -> String {
        var out = "Date,Part Number,Name,Action,Quantity,Project,Stock After\n"
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        for e in entries {
            let cells = [
                f.string(from: e.date),
                e.partNumber,
                e.name,
                e.kind == .used ? "Used" : "Returned",
                "\(e.quantity)",
                e.project,
                "\(e.resultingStock)",
            ]
            out += cells.map(escapeCSV).joined(separator: ",") + "\n"
        }
        return out
    }

    /// Lenient CSV parse: header row maps columns by name, unknown columns ignored.
    static func parseCSV(_ text: String) -> [Component] {
        // Security: Limit input size to prevent DoS
        guard text.count <= 10_000_000 else { return [] }
        
        let rows = parseCSVRows(text)
        guard let header = rows.first else { return [] }
        let headerMap: [String: Int] = {
            var m: [String: Int] = [:]
            for (i, h) in header.enumerated() {
                m[h.trimmingCharacters(in: .whitespaces).lowercased()] = i
            }
            return m
        }()

        func field(_ row: [String], _ key: String) -> String {
            guard let i = headerMap[key], i < row.count else { return "" }
            return sanitizeImportField(row[i])
        }

        var out: [Component] = []
        for row in rows.dropFirst() {
            guard !row.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) else { continue }
            guard out.count < 10_000 else { break } // Limit components
            var c = Component()
            c.partNumber   = sanitizeImportField(field(row, "part number"))
            c.name         = sanitizeImportField(field(row, "name"))
            let cat = field(row, "category")
            c.category     = cat.isEmpty ? Categories.other : sanitizeImportField(cat)
            c.quantity     = max(0, Int(field(row, "quantity")) ?? 0)
            c.minimumStock = max(0, Int(field(row, "min stock")) ?? 0)
            c.location     = sanitizeImportField(field(row, "location"))
            c.value        = sanitizeImportField(field(row, "value"))
            c.footprint    = sanitizeImportField(field(row, "footprint"))
            c.tolerance    = sanitizeImportField(field(row, "tolerance"))
            c.voltageRating = sanitizeImportField(field(row, "voltage"))
            c.manufacturer = sanitizeImportField(field(row, "manufacturer"))
            c.supplier     = sanitizeImportField(field(row, "supplier"))
            c.orderNumber  = sanitizeImportField(field(row, "order number"))
            c.unitCost     = max(0, min(Double(field(row, "unit cost")) ?? 0, 10_000_000))
            c.project      = sanitizeImportField(field(row, "project"))
            c.datasheetURL = sanitizeImportURL(field(row, "datasheet"))
            c.notes        = sanitizeImportField(field(row, "notes"), maxLength: 5000)
            c.dateOrdered  = parseDateFlexible(field(row, "date ordered"))
            c.dateReceived = parseDateFlexible(field(row, "date received"))
            if c.partNumber.isEmpty && c.name.isEmpty { continue }
            out.append(c)
        }
        return out
    }
    
    private static func sanitizeImportField(_ s: String, maxLength: Int = 1000) -> String {
        var result = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.count > maxLength {
            result = String(result.prefix(maxLength))
        }
        // Remove control characters
        result = result.filter { !$0.isNewline || $0 == "\n" || $0 == "\t" }
        return result
    }
    
    private static func sanitizeImportURL(_ s: String) -> String {
        let trimmed = sanitizeImportField(s)
        guard trimmed.isEmpty || (trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")) else {
            return ""
        }
        return trimmed
    }

    static func parseJSON(_ text: String) -> [Component]? {
        // Security: Limit input size
        guard text.count <= 10_000_000 else { return nil }
        guard let data = text.data(using: .utf8) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        if let inv = try? dec.decode(Inventory.self, from: data) { return inv.components }
        // Also accept a bare array of components.
        if let arr = try? dec.decode([Component].self, from: data) { return arr }
        return nil
    }

    static func parseDate(_ s: String) -> Date? {
        parseDateFlexible(s)
    }
    
    /// Parse date with multiple format support
    static func parseDateFlexible(_ s: String) -> Date? {
        guard !s.isEmpty else { return nil }
        let formatters = [
            "yyyy-MM-dd",
            "yyyy/MM/dd",
            "dd-MM-yyyy",
            "dd/MM/yyyy",
            "MM/dd/yyyy",
            "MM-dd-yyyy",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        ]
        for format in formatters {
            let f = DateFormatter()
            f.dateFormat = format
            if let date = f.date(from: s) { return date }
        }
        return nil
    }

    static func parseCSVRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var field = ""
        var row: [String] = []
        var inQuotes = false
        var iterator = text.makeIterator()
        var pending: Character?

        func endField() { row.append(field); field = "" }
        func endRow() {
            endField()
            rows.append(row)
            row = []
        }

        while let ch = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if ch == "\"" {
                    if let n = iterator.next() {
                        if n == "\"" { field.append("\"") } else { inQuotes = false; pending = n }
                    } else { inQuotes = false }
                } else {
                    field.append(ch)
                }
            } else {
                switch ch {
                case "\"": inQuotes = true
                case ",":  endField()
                case "\n": endRow()
                case "\r": 
                    // Handle \r\n - peek next char
                    if let next = iterator.next() {
                        if next != "\n" { pending = next }
                    }
                    endRow()
                default:   field.append(ch)
                }
            }
        }
        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows.filter { $0.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
    }
}
