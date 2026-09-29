import Foundation
import AppKit
import SwiftUI

// Headless checks for the non-UI logic: persistence, filtering, sorting,
// stock maths and CSV/JSON round-trips. Run via ./test.sh

@main
struct Tests {
    static var failures = 0
    static var checks = 0

    static func check(_ label: String, _ cond: Bool, _ detail: String = "") {
        checks += 1
        if cond { print("  ok   \(label)") }
        else {
            print("  FAIL \(label)\(detail.isEmpty ? "" : " — \(detail)")")
            failures += 1
        }
    }

    @MainActor
    static func main() {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ct-test-\(UUID().uuidString)")
        let url = tmp.appendingPathComponent("inventory.json")

        print("\n== persistence ==")
        let store = InventoryStore(storeURL: url)
        check("starts empty", store.components.isEmpty)

        var r = Component()
        r.partNumber = "RC0805FR-0710KL"
        r.name = "10k 1% 0805 resistor"
        r.category = Categories.resistors
        r.quantity = 250
        r.minimumStock = 100
        r.location = "Drawer A3 / Bin 12"
        r.value = "10k"
        r.footprint = "0805"
        r.tolerance = "±1%"
        r.manufacturer = "Yageo"
        r.supplier = "Mouser"
        r.unitCost = 0.012
        r.project = "Line Follower"
        // Dates exercise the ISO 8601 persistence path end to end — the JSON
        // reload below asserts they survive a save/load cycle.
        r.dateOrdered = Date(timeIntervalSince1970: 1_700_000_000)
        r.dateReceived = Date(timeIntervalSince1970: 1_700_008_000)
        store.add(r)

        var c = Component()
        c.partNumber = "ATMEGA328P-AU"
        c.name = "8-bit MCU"
        c.category = Categories.micros
        c.quantity = 4
        c.minimumStock = 10      // low stock
        c.unitCost = 2.45
        store.add(c)

        var d = Component()
        d.partNumber = "LED-RED-0603"
        d.name = "Red LED"
        d.category = Categories.leds
        d.quantity = 0           // out of stock
        d.minimumStock = 50
        store.add(d)

        check("3 components", store.components.count == 3)
        check("total units = 254", store.totalUnits == 254)
        check("total value = 12.80", abs(store.totalValue - (250 * 0.012 + 4 * 2.45)) < 0.0001,
              )
        check("low stock count = 1", store.lowStockCount == 1)
        check("out of stock count = 1", store.outOfStockCount == 1)

        print("\n== derived stock levels ==")
        let resistor = store.components.first { $0.partNumber.hasPrefix("RC0805") }!
        check("resistor is ok", resistor.stockLevel == .ok)
        let mcu = store.components.first { $0.partNumber.hasPrefix("ATMEGA") }!
        check("mcu is low", mcu.stockLevel == .low)
        check("led is out", d.stockLevel == .out)

        print("\n== take out / put back ==")
        let took = store.takeOut(mcu, count: 3)
        check("took 3", took == 3)
        check("mcu now 1", store.components.first { $0.id == mcu.id }!.quantity == 1)
        check("mcu still 'low' at qty 1", store.components.first { $0.id == mcu.id }!.stockLevel == .low)

        let clamped = store.takeOut(mcu, count: 99)
        check("clamped to available", clamped == 1)
        check("never negative", store.components.first { $0.id == mcu.id }!.quantity == 0)

        store.putBack(mcu, count: 6)
        check("put back 6 -> 6", store.components.first { $0.id == mcu.id }!.quantity == 6)
        store.adjustQuantity(mcu, by: -100)
        check("adjust floors at 0", store.components.first { $0.id == mcu.id }!.quantity == 0)

        print("\n== search & filter ==")
        store.section = .all
        store.searchText = "0805"
        check("search finds 0805", store.filtered.count == 1)
        store.searchText = "mouser"
        check("search hits supplier", store.filtered.count == 1)
        store.searchText = "zzzznope"
        check("no match -> empty", store.filtered.isEmpty)
        store.searchText = "10k 0805"
        check("multi-term AND", store.filtered.count == 1)
        store.searchText = "line follower"
        check("search hits project", store.filtered.count == 1)
        store.resetFilters()
        check("filters reset", store.filtered.count == 3)

        store.section = .lowStock
        check("lowStock section", store.filtered.allSatisfy { $0.isLowStock && !$0.isOutOfStock })
        store.section = .outOfStock
        check("outOfStock section", store.filtered.allSatisfy { $0.isOutOfStock })
        store.section = .categories
        store.categoryFilter = Categories.leds
        check("category filter", store.filtered.count == 1 &&
              store.filtered[0].category == Categories.leds)
        store.section = .all
        store.categoryFilter = nil

        print("\n== sorting ==")
        store.sortField = .quantity
        store.sortAscending = true
        store.sort()
        check("qty ascending", zip(store.components, store.components.dropFirst())
            .allSatisfy { $0.quantity <= $1.quantity })
        store.sortAscending = false
        store.sort()
        check("qty descending", zip(store.components, store.components.dropFirst())
            .allSatisfy { $0.quantity >= $1.quantity })
        store.sortField = .partNumber
        store.sortAscending = true
        store.sort()

        print("\n== edit & duplicate & delete ==")
        // Edit a specific part (not index 0 — the list is sorted by part number).
        var edited = store.components.first { $0.partNumber == "RC0805FR-0710KL" }!
        edited.quantity = 7
        edited.name = "renamed"
        store.update(edited)
        check("edit applied", store.components.first { $0.id == edited.id }!.quantity == 7)
        check("edit bumped updatedAt", store.components.first { $0.id == edited.id }!.updatedAt >= edited.createdAt)

        let before = store.components.count
        store.duplicate(store.components[0])
        check("duplicate adds one", store.components.count == before + 1)
        store.delete(store.components.first { $0.partNumber.contains("copy") }!)
        check("delete removes one", store.components.count == before)

        print("\n== CSV round trip ==")
        let csv = ExportService.csv(from: store.filtered)
        let parsed = ExportService.parseCSV(csv)
        check("csv row count", parsed.count == store.filtered.count)
        let back = parsed.first { $0.partNumber == "RC0805FR-0710KL" }!
        check("csv keeps part number", back.partNumber == "RC0805FR-0710KL")
        check("csv keeps name", back.name == "renamed")
        check("csv keeps qty", back.quantity == 7)
        check("csv keeps location", back.location == "Drawer A3 / Bin 12")
        check("csv keeps unit cost", abs(back.unitCost - 0.012) < 0.0001)
        check("csv keeps tolerance", back.tolerance == "±1%")
        check("csv keeps project", back.project == "Line Follower")

        var tricky = Component()
        tricky.partNumber = "X-1"
        tricky.name = "Has, a comma and \"quotes\""
        tricky.notes = "line1\nline2"
        tricky.quantity = 2
        let trickyCSV = ExportService.csv(from: [tricky])
        let trickyBack = ExportService.parseCSV(trickyCSV)
        check("csv survives commas+quotes", trickyBack.first?.name == tricky.name)
        check("csv survives newlines", trickyBack.first?.notes == tricky.notes)

        print("\n== JSON round trip ==")
        let json = ExportService.json(from: store.filtered)
        let jsonBack = ExportService.parseJSON(json)!
        check("json row count", jsonBack.count == store.filtered.count)
        check("json lossless name", jsonBack.first { $0.partNumber == "RC0805FR-0710KL" }?.name == "renamed")

        print("\n== merge ==")
        var incoming = Component()
        incoming.partNumber = "RC0805FR-0710KL"
        incoming.quantity = 3
        store.merge(imported: [incoming])
        let merged = store.components.first { $0.partNumber == "RC0805FR-0710KL" }!
        check("merge sums qty (7+3=10)", merged.quantity == 10)
        check("merge did not duplicate",
              store.components.filter { $0.partNumber == "RC0805FR-0710KL" }.count == 1)

        var fresh = Component()
        fresh.partNumber = "BRAND-NEW"
        fresh.quantity = 9
        store.merge(imported: [fresh])
        check("merge adds new part", store.components.contains { $0.partNumber == "BRAND-NEW" })

        print("\n== reload from disk ==")
        store.flush()
        let reopened = InventoryStore(storeURL: url)
        check("survives reload", reopened.components.count == store.components.count)
        check("qty persisted", reopened.components.first { $0.partNumber == "RC0805FR-0710KL" }?.quantity == 10)
        let reloadedR = reopened.components.first { $0.partNumber == "RC0805FR-0710KL" }
        check("date ordered persisted", reloadedR?.dateOrdered != nil)
        check("date received persisted", reloadedR?.dateReceived != nil)

        print("\n== currency (INR) ==")
        check("code is INR", Money.code == "INR")
        check("symbol is rupee", Money.symbol == "₹")

        // Indian grouping groups the last 3 digits, then pairs: 12,34,567.
        // This is the thing most likely to silently regress to 1,234,567.
        check("exact uses lakh grouping (12,34,567)", Money.exact(1234567) == "₹12,34,567.00")
        check("exact no grouping below 1000",      Money.exact(999) == "₹999.00")
        check("exact groups at 1000 (1,000)",      Money.exact(1000) == "₹1,000.00")
        check("exact groups at 1 lakh (1,00,000)",  Money.exact(100000) == "₹1,00,000.00")
        check("exact groups at 1 crore (1,00,00,000)", Money.exact(10000000) == "₹1,00,00,000.00")
        check("exact keeps 2dp",                    Money.exact(1.5) == "₹1.50")
        check("exact rounds to 2dp",                Money.exact(2.345) == "₹2.35" || Money.exact(2.345) == "₹2.34")

        check("compact plain below 1000",   Money.compact(999) == "₹999.00")
        check("compact K at 1,000",          Money.compact(1000) == "₹1.0K")
        check("compact K at 99,999",         Money.compact(99999) == "₹100.0K" || Money.compact(99999) == "₹99.9K")
        check("compact L at 1 lakh",         Money.compact(100000) == "₹1.0L")
        check("compact L at 99 lakh",        Money.compact(9999999) == "₹100.0L" || Money.compact(9999999) == "₹99.9L")
        check("compact Cr at 1 crore",       Money.compact(10000000) == "₹1.0Cr")
        check("compact zero",                Money.compact(0) == "₹0.00")

        // No rupee value should ever render with a dollar sign.
        let rendered = [Money.exact(0), Money.exact(1234.56), Money.exact(98765432.1),
                        Money.compact(0), Money.compact(12.5), Money.compact(5_00_000)]
            .joined(separator: " ")
        check("nothing renders a dollar sign", !rendered.contains("$"))

        print("\n== Pi shell quoting ==")
        // The bug this fixes: remoteDir was interpolated unquoted, so a folder
        // name containing a space made the remote script die with "Is a directory".
        check("plain path is quoted",      ShellQuote.path("/srv/ct") == "'/srv/ct'")
        check("tilde stays expandable",   ShellQuote.path("~/component-tracker") == "~/'component-tracker'")
        check("tilde with space is safe", ShellQuote.path("~/my tracker") == "~/'my tracker'")
        check("tilde only",               ShellQuote.path("~") == "~")
        check("~user form",               ShellQuote.path("~pi/backups") == "~'pi'/'backups'")
        check("no doubled slash",         !ShellQuote.path("~/x").contains("//"))
        check("tilde+path is exact",      ShellQuote.path("~/x") == "~/'x'")
        check("embedded quote is escaped", ShellQuote.single("it's") == "'it'\\''s'")
        check("space never leaks unquoted", !ShellQuote.path("~/a b/c d").contains(" a "))
        // A shell metacharacter is neutralised by being wrapped in single quotes,
        // not by being absent — the point is it can't terminate the quoting.
        check("metachar is wrapped, not bare",
              ShellQuote.single("a; rm -rf /").hasPrefix("'")
              && ShellQuote.single("a; rm -rf /").hasSuffix("'")
              && ShellQuote.single("a; rm -rf /").contains("'a; rm -rf /'"))

        // A tilde that got quoted would create a literal "~" directory on the Pi.
        check("leading tilde is never quoted", !ShellQuote.path("~/x").hasPrefix("'~"))

        print("\n== consumption log ==")
        // A fresh store, so the log checks are not entangled with the history
        // built up by the take-out tests above.
        let logURL = tmp.appendingPathComponent("log.json")
        let logStore = InventoryStore(storeURL: logURL)
        var part = Component()
        part.partNumber = "HC-SR04"
        part.name = "Ultrasonic distance sensor"
        part.quantity = 10
        part.minimumStock = 3
        logStore.add(part)

        check("log starts empty", logStore.consumed.isEmpty)
        check("net used starts at 0", logStore.totalConsumed == 0)

        logStore.takeOut(logStore.components[0], count: 4, project: "Line Follower")
        check("take-out decrements stock", logStore.components[0].quantity == 6)
        check("take-out writes one entry", logStore.consumed.count == 1)
        let e1 = logStore.consumed[0]
        check("entry is 'used'", e1.kind == .used)
        check("entry quantity", e1.quantity == 4)
        check("entry records project", e1.project == "Line Follower")
        check("entry stores resulting stock", e1.resultingStock == 6)
        check("entry denormalises part number", e1.partNumber == "HC-SR04")
        check("entry denormalises name", e1.name == "Ultrasonic distance sensor")
        check("entry links to component", e1.componentID == part.id)
        check("net used = 4", logStore.totalConsumed == 4)

        logStore.takeOut(logStore.components[0], count: 2, project: "Line Follower")
        logStore.takeOut(logStore.components[0], count: 1, project: "Sensor Board")
        check("three entries", logStore.consumed.count == 3)
        check("newest first", logStore.consumed[0].project == "Sensor Board")
        check("net used = 7", logStore.totalConsumed == 7)

        // A return must cancel the take-out, or the log would claim parts were
        // consumed when they are sitting back on the shelf.
        logStore.putBack(logStore.components[0], count: 2, project: "Line Follower")
        check("put-back writes an entry", logStore.consumed.count == 4)
        check("return is signed negative", logStore.consumed[0].signedQuantity == -2)
        check("return kind is 'returned'", logStore.consumed[0].kind == .returned)
        check("net used back to 5", logStore.totalConsumed == 5)

        // Newest first, so index 0 is the most recent entry. The sequence
        // below is: -4, -2, -1, +2, -1, +1, then a clamped -5, then a no-op.
        // Stock: 10 → 6 → 4 → 3 → 5 → 4 → 5 → 0 → 0.
        logStore.adjustQuantity(logStore.components[0], by: -1)
        check("adjust -1 logs a take-out", logStore.consumed[0].kind == .used)
        check("adjust -1 is newest", logStore.consumed.count == 5)
        logStore.adjustQuantity(logStore.components[0], by: 1)
        check("adjust +1 logs a return", logStore.consumed[0].kind == .returned)
        check("adjust +1 nets back to 5", logStore.totalConsumed == 5)

        // Clamped take-out: 5 remain, so asking for 99 must log 5, not 99.
        check("stock is 5 before the clamp", logStore.components[0].quantity == 5)
        let over = logStore.takeOut(logStore.components[0], count: 99)
        check("clamped take-out returns actual", over == 5)
        check("clamped take-out logs the real amount", logStore.consumed[0].quantity == 5)
        check("stock floors at 0", logStore.components[0].quantity == 0)

        let beforeNoOp = logStore.consumed.count
        check("take-out from empty returns 0", logStore.takeOut(logStore.components[0], count: 5) == 0)
        check("take-out from empty logs nothing", logStore.consumed.count == beforeNoOp)
        check("net used after draining", logStore.totalConsumed == 10, "actual \(logStore.totalConsumed)")

        let perProject = logStore.consumptionByProject
        check("per-project nets sum to net", perProject.reduce(0) { $0 + $1.net } == logStore.totalConsumed)
        check("per-project used is never negative", perProject.allSatisfy { $0.used >= 0 })
        check("per-project returned is never negative", perProject.allSatisfy { $0.returned >= 0 })
        check("projects sorted by usage",
              zip(perProject, perProject.dropFirst()).allSatisfy { $0.used >= $1.used })

        // Give the project buckets non-zero numbers to assert on. Stock is 0 at
        // this point, so put 20 back on "Bench PSU" then take 8 out again.
        logStore.putBack(logStore.components[0], count: 20, project: "Bench PSU")
        logStore.takeOut(logStore.components[0], count: 8, project: "Bench PSU")
        let pp = Dictionary(uniqueKeysWithValues: logStore.consumptionByProject.map { ($0.project, $0) })
        check("Bench PSU used = 8", pp["Bench PSU"]?.used == 8, "actual \(String(describing: pp["Bench PSU"]))")
        check("Bench PSU returned = 20", pp["Bench PSU"]?.returned == 20)
        check("Bench PSU net = 8 - 20", pp["Bench PSU"]?.net == -12)
        // adjust -1, adjust +1 and the clamped -5 all carried no project.
        check("unassigned used = 1 + 5", pp["Unassigned"]?.used == 6, "actual \(String(describing: pp["Unassigned"]?.used))")
        check("unassigned returned = 1", pp["Unassigned"]?.returned == 1)
        check("per-project nets still sum to net",
              logStore.consumptionByProject.reduce(0) { $0 + $1.net } == logStore.totalConsumed)

        check("history(for:) filters one part",
              logStore.history(for: part.id).count == logStore.consumed.count)
        check("history(for:) empty for unknown id",
              logStore.history(for: UUID()).isEmpty)

        let entriesBeforeDelete = logStore.consumed.count
        // History must outlive the record it points at — a log that vanishes
        // with its component is not a log.
        logStore.delete(logStore.components[0])
        check("log survives component deletion", logStore.consumed.count == entriesBeforeDelete)
        check("orphaned entry still readable", logStore.consumed.first?.partNumber == "HC-SR04")

        print("\n== consumption persistence ==")
        logStore.flush()
        let reopenedLog = InventoryStore(storeURL: logURL)
        check("log survives reload", reopenedLog.consumed.count == entriesBeforeDelete)
        check("entries keep their order",
              reopenedLog.consumed.first?.kind == .used)
        check("projects survive reload", reopenedLog.consumed.contains { $0.project == "Sensor Board" })
        check("net used survives reload", reopenedLog.totalConsumed == logStore.totalConsumed)

        print("\n== old data file still loads ==")
        // The regression this guards: Inventory gained a `consumed` key, and
        // Swift's synthesised decoder throws keyNotFound for an absent key even
        // when the property has a default. Every inventory.json written before
        // this version has no such key, so without the hand-written
        // init(from:) the store would treat a perfectly good file as corrupt,
        // move it aside and start from an empty inventory.
        let legacyURL = tmp.appendingPathComponent("legacy.json")
        let legacyJSON = """
        {
          "version": 1,
          "components": [
            {
              "id": "11111111-2222-3333-4444-555555555555",
              "partNumber": "LM358DR",
              "name": "Dual op-amp",
              "category": "ICs",
              "quantity": 22,
              "minimumStock": 10,
              "location": "Drawer B / Bin 02",
              "manufacturer": "",
              "supplier": "element14",
              "orderNumber": "",
              "unitCost": 22.0,
              "dateOrdered": null,
              "dateReceived": null,
              "project": "Sensor Board",
              "value": "",
              "footprint": "SOIC-8",
              "tolerance": "",
              "voltageRating": "",
              "datasheetURL": "",
              "notes": "",
              "createdAt": "2026-01-02T10:00:00Z",
              "updatedAt": "2026-01-02T10:00:00Z"
            }
          ]
        }
        """
        try? Data(legacyJSON.utf8).write(to: legacyURL)
        let legacy = InventoryStore(storeURL: legacyURL)
        check("pre-log file loads without error", legacy.components.count == 1)
        check("pre-log data intact", legacy.components.first?.partNumber == "LM358DR")
        check("pre-log qty intact", legacy.components.first?.quantity == 22)
        check("missing log key defaults to empty", legacy.consumed.isEmpty)
        check("pre-log file was not parked as corrupt",
              !((try? FileManager.default.contentsOfDirectory(
                    atPath: legacyURL.deletingLastPathComponent().path)) ?? [])
                .contains { $0.hasPrefix("inventory-corrupt-") })
        // And it must survive a write/read cycle, not just the first load.
        legacy.flush()
        let legacyAgain = InventoryStore(storeURL: legacyURL)
        check("pre-log file survives a save cycle", legacyAgain.components.count == 1)
        check("still no log entries", legacyAgain.consumed.isEmpty)

        // A file missing `components` entirely must not crash either.
        let bareURL = tmp.appendingPathComponent("bare.json")
        try? Data(#"{"version": 1}"#.utf8).write(to: bareURL)
        let bare = InventoryStore(storeURL: bareURL)
        check("missing components key -> empty, no crash", bare.components.isEmpty)

        print("\n== usage log CSV ==")
        let logCSV = ExportService.consumptionCSV(from: logStore.consumed)
        let logLines = logCSV.split(separator: "\n", omittingEmptySubsequences: true)
        check("csv header present", logCSV.hasPrefix("Date,Part Number,Name,Action,Quantity,Project,Stock After"))
        check("csv one row per entry + header",
              logLines.count == logStore.consumed.count + 1,
              "expected \(logStore.consumed.count + 1) lines, got \(logLines.count)")
        check("csv marks take-outs as Used", logCSV.contains(",Used,"))
        check("csv marks returns as Returned", logCSV.contains(",Returned,"))
        check("csv carries the project", logCSV.contains("Sensor Board"))

        // parseJSON only returns components — the log is carried in the
        // document, so assert on the decoded document instead.
        let docBack = ExportService.parseJSON(ExportService.json(from: [], consumed: logStore.consumed))
        check("json export of components parses", docBack != nil)

        print("\n== undo / redo ==")
        // Fresh store: the tests above have built up a deep history already.
        let undoURL = tmp.appendingPathComponent("undo.json")
        let us = InventoryStore(storeURL: undoURL)
        check("no undo on a fresh store", us.undoLabel == nil)
        check("no redo on a fresh store", us.redoLabel == nil)

        var u1 = Component()
        u1.partNumber = "AAA-1"
        u1.name = "First part"
        u1.quantity = 10
        us.add(u1)
        check("add enables undo", us.undoLabel == "Add AAA-1")
        check("still no redo", us.redoLabel == nil)

        us.undo()
        check("undo removed the part", us.components.isEmpty)
        check("undo label is now the next step back", us.undoLabel == nil)
        check("redo is offered", us.redoLabel == "Add AAA-1")

        us.redo()
        check("redo restored the part", us.components.count == 1)
        check("part number intact", us.components.first?.partNumber == "AAA-1")
        check("undo offered again", us.undoLabel == "Add AAA-1")
        check("redo exhausted", us.redoLabel == nil)

        print("\n-- undo crosses the usage log --")
        // The point of snapshots over inverse commands: a take-out is two
        // changes (stock and log entry) and undo has to take both back.
        let undoPart = us.components[0]
        us.takeOut(undoPart, count: 4, project: "Board A")
        check("take-out logged", us.consumed.count == 1)
        check("stock reduced", us.components[0].quantity == 6)
        check("undo label names the action", us.undoLabel == "Take 4 × AAA-1")
        us.undo()
        check("undo restored stock", us.components[0].quantity == 10)
        check("undo removed the log entry", us.consumed.isEmpty)
        us.redo()
        check("redo restored the log entry", us.consumed.count == 1)
        check("redo restored stock", us.components[0].quantity == 6)
        check("redo kept the project", us.consumed.first?.project == "Board A")

        print("\n-- repeated edits coalesce --")
        // Three quick +1 clicks on the same part must be one undo step, not
        // three — otherwise the first ⌘Z appears to do nothing.
        us.undo()               // back to 10; the redo branch now holds the take-out
        check("back to 10", us.components[0].quantity == 10)
        for _ in 0..<3 { us.adjustQuantity(us.components[0], by: -1) }
        check("three -1 clicks took 3", us.components[0].quantity == 7)
        check("three clicks share one undo step", us.undoLabel == "Take 1 × AAA-1")
        us.undo()
        check("one undo rewinds all three", us.components[0].quantity == 10)
        check("log rewound too", us.consumed.isEmpty)

        print("\n-- different parts do not coalesce --")
        var u2 = Component()
        u2.partNumber = "BBB-2"
        u2.quantity = 5
        us.add(u2)
        us.adjustQuantity(us.components[0], by: -1)
        check("second part is a separate step", us.undoLabel == "Take 1 × AAA-1")
        us.adjustQuantity(us.components[1], by: -1)
        check("adjust on the other part", us.undoLabel == "Take 1 × BBB-2")
        us.undo()
        check("undo only touched BBB-2", us.components[1].quantity == 5)
        us.undo()
        check("second undo touched AAA-1", us.components[0].quantity == 10)

        print("\n-- new edit invalidates redo --")
        // The two undos above left a redo branch behind. It has to be checked
        // here, *before* the next edit — recording any new step is what clears
        // it, so testing afterwards could never pass.
        check("redo branch survives the undos", us.redoLabel != nil,
              "expected a redo label, got \(String(describing: us.redoLabel))")
        us.takeOut(us.components[0], count: 1)
        check("a new edit clears the redo branch", us.redoLabel == nil)

        print("\n-- import is one step --")
        let baseline = us.components.count
        us.merge(imported: [Component(partNumber: "CCC-3", quantity: 4),
                            Component(partNumber: "DDD-4", quantity: 5)])
        check("merge added two", us.components.count == baseline + 2)
        check("merge is one undo step", us.undoLabel == "Merge 2 components")
        us.undo()
        check("one undo undoes the whole merge", us.components.count == baseline)

        let replaceTarget = [Component(partNumber: "EEE-5", quantity: 1)]
        us.replaceAll(with: replaceTarget)
        check("replace is one step", us.undoLabel == "Replace with 1 components")
        us.undo()
        check("undo restores the previous inventory", us.components.count == baseline)

        print("\n-- delete-all is reversible --")
        us.replaceAll(with: [])
        check("inventory emptied", us.components.isEmpty)
        check("label reads as a delete", us.undoLabel == "Delete everything")
        us.undo()
        check("undo brings it all back", us.components.count == baseline)

        print("\n-- undo survives a reload --")
        us.delete(ids: [us.components[0].id])
        us.flush()
        us.undo()
        us.flush()
        let reloadedUndo = InventoryStore(storeURL: undoURL)
        check("undone state is what got written", reloadedUndo.components.count == baseline)
        check("history is per-session, not persisted", reloadedUndo.undoLabel == nil)

        print("\n== clearing the log ==")
        let clearURL = tmp.appendingPathComponent("clear.json")
        let cs = InventoryStore(storeURL: clearURL)
        var cp = Component()
        cp.partNumber = "RES-10K"
        cp.quantity = 50
        cs.add(cp)
        cs.takeOut(cs.components[0], count: 5, project: "Bench")
        cs.takeOut(cs.components[0], count: 3, project: "Bench")
        check("two entries", cs.consumed.count == 2)

        cs.clearHistory(for: UUID())   // wrong part: must be a no-op
        check("clearing another part is a no-op", cs.consumed.count == 2)
        check("no undo step for a no-op",
              cs.undoLabel == "Take 3 × RES-10K",
              "expected the last real action, got \(String(describing: cs.undoLabel))")
        cs.clearHistory(for: cp.id)
        check("clearing this part empties its log", cs.consumed.isEmpty)
        check("stock untouched by a log clear", cs.components[0].quantity == 42)
        check("clear is one undo step", cs.undoLabel == "Clear 2 log entries")
        cs.undo()
        check("undo brings the log back", cs.consumed.count == 2)

        cs.clearAllHistory()
        check("clear all empties the log", cs.consumed.isEmpty)
        check("stock still untouched", cs.components[0].quantity == 42)
        cs.undo()
        check("undo restores the whole log", cs.consumed.count == 2)
        check("restored in order", cs.consumed[0].quantity == 3)

        print("\n-- deliberate take-outs do not coalesce --")
        // The opposite rule from adjustQuantity: two people-visible sheet
        // submissions are two intentions, even a second apart. Coalescing them
        // would make the first ⌘Z appear to swallow the first action.
        // The log currently holds both take-outs, newest first: 3 then 5.
        check("two entries before unwinding", cs.consumed.count == 2)
        cs.undo()
        check("one undo removes only the newest", cs.consumed.count == 1)
        check("the earlier take-out survives", cs.consumed[0].quantity == 5)
        check("undo label names the older step", cs.undoLabel == "Take 5 × RES-10K")
        cs.undo()
        check("a second undo removes it too", cs.consumed.isEmpty)
        check("stock fully restored", cs.components[0].quantity == 50)

        print("\n== corrupt file recovery ==")
        let badURL = tmp.appendingPathComponent("bad.json")
        try? Data("{ not json at all".utf8).write(to: badURL)
        let recovered = InventoryStore(storeURL: badURL)
        check("corrupt file -> empty, not crash", recovered.components.isEmpty)
        let parked = ((try? FileManager.default.contentsOfDirectory(
                        atPath: badURL.deletingLastPathComponent().path)) ?? [])
            .contains { $0.hasPrefix("inventory-corrupt-") }
        check("corrupt file preserved as backup", parked)

        try? FileManager.default.removeItem(at: tmp)

        print("\n== skins ==")

        check("three skins ship", Skin.all.count == 3)
        check("skin ids are unique",
              Set(Skin.all.map(\.id)).count == Skin.all.count)
        for s in Skin.all {
            check("\(s.name) has a dark and a light palette",
                  s.dark.isDark && !s.light.isDark)
            check("\(s.name) dark palette agrees with itself",
                  s.dark.isDark == true)
        }

        // Every one of the 6 palettes must have real contrast. A skin is added
        // by writing a literal block, and a typo in one hex lands as an
        // unreadable pair that no build error and no unit test would notice.
        var contrastFails: [String] = []
        for s in Skin.all {
            for (label, p) in [("dark", s.dark), ("light", s.light)] {
                let pairs: [(String, Color, Color)] = [
                    ("text on bg", p.textHi, p.bg),
                    ("textMid on bg", p.textMid, p.bg),
                    ("textLow on bg", p.textLow, p.bg),
                    ("accent on bg", p.accent, p.bg),
                    ("good on bg", p.good, p.bg),
                    ("warn on bg", p.warn, p.bg),
                    ("danger on bg", p.danger, p.bg),
                    ("text on panel", p.textHi, p.surface),
                ]
                for (what, fg, bgc) in pairs {
                    let cr = contrastRatio(fg, bgc)
                    let floor: Double = what.hasPrefix("textLow") ? 2.0 : 3.0
                    if cr < floor {
                        contrastFails.append("\(s.name)/\(label) \(what) = \(String(format: "%.2f", cr)):1")
                    }
                }
            }
        }
        check("all 6 palettes clear their contrast floors" +
              (contrastFails.isEmpty ? "" : " — " + contrastFails.joined(separator: "; ")),
              contrastFails.isEmpty)

        // Structural flags must differ where the design depends on them. Two
        // skins that end up with identical flags will render identically and the
        // switcher becomes a lie.
        check("graphite fills cards", Skin.graphite.cardFill)
        check("swiss does not fill cards (that is the whole style)", !Skin.swiss.cardFill)
        check("swiss is square", Skin.swiss.radius == 0)
        check("blueprint is square", Skin.blueprint.radius == 0)
        check("graphite has a radius", Skin.graphite.radius > 0)
        check("only blueprint has a grid", Skin.all.filter(\.gridBackdrop).count == 1)
        check("only blueprint has drafting marks", Skin.all.filter(\.draftingMarks).count == 1)
        check("only blueprint is monospaced", Skin.all.filter(\.monospaced).count == 1)
        check("swiss has the widest type range",
              Skin.swiss.figureSize / Skin.swiss.labelSize >
              Skin.graphite.figureSize / Skin.graphite.labelSize)

        // Switching must be total: every palette name moves, on every skin.
        var allMove = true
        for s in Skin.all {
            SkinController.set(skin: s, dark: true)
            let darkSet = PALETTE_NAMES.map { resolve($0) }
            SkinController.set(skin: s, dark: false)
            let lightSet = PALETTE_NAMES.map { resolve($0) }
            if darkSet == lightSet { allMove = false }
        }
        check("all \(PALETTE_NAMES.count) palette names follow the scheme on every skin", allMove)

        var skinsDistinct = true
        SkinController.set(skin: .graphite, dark: true)
        let g = PALETTE_NAMES.map { resolve($0) }
        SkinController.set(skin: .swiss, dark: true)
        if PALETTE_NAMES.map({ resolve($0) }) == g { skinsDistinct = false }
        SkinController.set(skin: .blueprint, dark: true)
        if PALETTE_NAMES.map({ resolve($0) }) == g { skinsDistinct = false }
        check("the three skins do not share a palette", skinsDistinct)

        // Metrics and fonts are structural, not just colour, so they have to
        // follow the skin too or the switch changes colour and nothing else.
        SkinController.set(skin: .graphite, dark: true)
        let gRadius = Metrics.corner, gPad = Metrics.pad
        SkinController.set(skin: .swiss, dark: true)
        check("radius follows the skin", Metrics.corner != gRadius)
        check("padding follows the skin", Metrics.pad != gPad)
        check("swiss radius is 0", Metrics.corner == 0)
        SkinController.set(skin: .blueprint, dark: true)
        check("blueprint radius is 0", Metrics.corner == 0)

        print("\n== theme persistence ==")

        // Seeded in init, because `didSet` does not fire for a property set
        // during initialisation — so without this the first frame renders the
        // previous run's theme and then corrects itself.
        let themeTmp = tmp.appendingPathComponent("theme.json")
        UserDefaults.standard.removeObject(forKey: Prefs.skinKey)
        UserDefaults.standard.removeObject(forKey: Prefs.darkKey)
        let t1 = InventoryStore(storeURL: themeTmp)
        check("default skin is graphite when nothing is stored", t1.skinID == "graphite")
        check("default scheme is dark when nothing is stored", t1.darkMode == true)
        check("init seeds the global skin",
              SkinController.skin.id == "graphite" && SkinController.dark == true)

        t1.skinID = "swiss"
        t1.darkMode = false
        check("setting skinID updates the global before returning",
              SkinController.skin.id == "swiss")
        check("setting darkMode updates the global before returning",
              SkinController.dark == false)
        check("skin persists", UserDefaults.standard.string(forKey: Prefs.skinKey) == "swiss")
        check("scheme persists", UserDefaults.standard.bool(forKey: Prefs.darkKey) == false)

        let t2 = InventoryStore(storeURL: themeTmp)
        check("a new store restores the skin", t2.skinID == "swiss")
        check("a new store restores the scheme", t2.darkMode == false)
        check("a new store applies the restored skin", SkinController.skin.id == "swiss")
        check("a new store applies the restored scheme", SkinController.dark == false)

        // An unknown id in defaults must fall back rather than leave the app
        // with no palette at all.
        UserDefaults.standard.set("does-not-exist", forKey: Prefs.skinKey)
        let t3 = InventoryStore(storeURL: themeTmp)
        check("unknown skin id falls back to graphite", t3.skinID == "graphite")
        check("unknown skin id still yields a working palette",
              SkinController.skin.id == "graphite")

        SkinController.set(skin: .graphite, dark: true)
        UserDefaults.standard.set(true, forKey: Prefs.darkKey)
        UserDefaults.standard.set("graphite", forKey: Prefs.skinKey)

        print("\n\(checks - failures)/\(checks) checks passed")
        if failures > 0 { print("\(failures) FAILURES"); exit(1) }
        print("all good")
    }

    // MARK: - Theme helpers
    //
    // Tests read the palette by name through a `Color` that only exists for
    // this purpose. `Palette` returns `Color`, which is opaque to string
    // comparison, so the harness resolves each name to a comparable value by
    // going through the same `Theme` struct the palette reads from. The point is
    // to catch a name that got hardcoded or forgotten during a refactor, not to
    // re-derive the colour maths.

    /// Every name `Palette` exposes. Enumerated rather than hand-listed per
    /// assertion, so adding a name to the palette and forgetting to test it is
    /// a compile error here instead of a silent gap.
    static let PALETTE_NAMES = ["bg", "panel", "panelHi", "line", "lineSoft",
                                "textHi", "textMid", "textLow",
                                "accent", "good", "warn", "danger"]

    static private func resolve(_ paletteName: String) -> String {
        let t = SkinController.palette
        switch paletteName {
        case "bg":      return hex(t.bg)
        case "panel":   return hex(t.surface)
        case "panelHi": return hex(t.raised)
        case "line":    return hex(t.rule)
        case "lineSoft":return hex(t.ruleSoft)
        case "textHi":  return hex(t.textHi)
        case "textMid": return hex(t.textMid)
        case "textLow": return hex(t.textLow)
        case "accent":  return hex(t.accent)
        case "good":    return hex(t.good)
        case "warn":    return hex(t.warn)
        case "danger":  return hex(t.danger)
        default:        return "?"
        }
    }

    /// WCAG relative contrast ratio, 1...21.
    ///
    /// Worth having as a real function rather than as a hand-kept table of
    /// expected ratios: a skin is added by typing hex literals, and a typo in
    /// one of them produces an unreadable pair that no build error and no
    /// snapshot would ever catch.
    static private func contrastRatio(_ a: Color, _ b: Color) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// Relative luminance in 0...1, using the sRGB coefficients. Only the
    /// ordering matters for these assertions, but a real number beats eyeballing
    /// when deciding whether a colour is "dark enough on paper".
    static private func luminance(_ c: Color) -> Double {
        let comps = nsColor(c).usingColorSpace(.sRGB) ?? .black
        func lin(_ v: CGFloat) -> Double {
            let x = Double(v)
            return x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(comps.redComponent)
             + 0.7152 * lin(comps.greenComponent)
             + 0.0722 * lin(comps.blueComponent)
    }

    static private func nsColor(_ c: Color) -> NSColor {
        NSColor(c)
    }

    static private func hex(_ c: Color) -> String {
        let n = nsColor(c).usingColorSpace(.sRGB) ?? .black
        return String(format: "%02X%02X%02X",
                      Int((n.redComponent * 255).rounded()),
                      Int((n.greenComponent * 255).rounded()),
                      Int((n.blueComponent * 255).rounded()))
    }
}
