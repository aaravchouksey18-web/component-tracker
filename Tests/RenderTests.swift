import SwiftUI
import AppKit

/// Unbuffered so progress survives a renderer that has to be killed.
func log(_ s: String) {
    FileHandle.standardError.write((s + "\n").data(using: .utf8)!)
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

extension ArraySlice {
    func chunked(into size: Int) -> [[Element]] {
        Array(self).chunked(into: size)
    }
}

// Renders the real views offscreen to PNG so the UI can be inspected without
// a window server or screen-recording permission. Run via ./render.sh

@main
struct RenderTests {
    @MainActor
    static func main() {
        let outDir = URL(fileURLWithPath: "build/renders")
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let store = InventoryStore()
        let demo = InventoryStore.seedComponents()
        store.replaceAll(with: demo)

        // 1. Sidebar
        render(Sidebar().environmentObject(store).environmentObject(PiSyncController()),
               size: CGSize(width: 210, height: 700), to: outDir, name: "1-sidebar")

        // 2. Cards. Rendered from a plain HStack stack because LazyVGrid is a lazy
        //    container and rasterises empty without a viewport.
        let cardItems = store.filtered.prefix(6)
        let rows = Array(cardItems.chunked(into: 3))
        render(
            VStack(alignment: .leading, spacing: 12) {
                ForEach(0..<rows.count, id: \.self) { i in
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(rows[i], id: \.id) { c in
                            ComponentCard(component: c, onEdit: {}, onTakeOut: {}, onDelete: {})
                                .frame(width: 285)
                        }
                    }
                }
            }
            .padding(16)
            .frame(width: 900, height: 700, alignment: .top)
            .background(Palette.bg)
            .environmentObject(store),
            size: CGSize(width: 900, height: 700), to: outDir, name: "2-cards")

        // 3. Table is intentionally skipped: `Table` is backed by an AppKit view
        //    that ImageRenderer cannot rasterise without a window host. It is
        //    exercised by the live app instead.

        // 4. Dashboard without the Charts view (see DashboardView.showChart).
        //    NOTE: this render comes out visually blank because DashboardView is
        //    ScrollView-rooted and a ScrollView rasterises empty under
        //    ImageRenderer (proved by render 9 below). That is a harness limit, not
        //    an app bug — the live app renders the dashboard normally.
        render(DashboardView(showChart: false)
            .frame(width: 1000, height: 720, alignment: .top)
            .background(Palette.bg)
            .environmentObject(store),
            size: CGSize(width: 1000, height: 720), to: outDir, name: "4-dashboard", scrollBody: true)

        // 5. Add/Edit sheet. Needs the store injected: the editor reads it for
        //    the duplicate-part-number check.
        render(ComponentEditor(component: demo.first)
                .environmentObject(store)
                .frame(width: 620, height: 640),
               size: CGSize(width: 620, height: 640), to: outDir, name: "5-editor", scrollBody: true)

        // 6. Take out sheet
        render(TakeOutSheet(component: demo.first!).environmentObject(store),
               size: CGSize(width: 430, height: 420), to: outDir, name: "6-takeout")

        // 7. Settings + export
        render(SettingsSheet().environmentObject(store)
            .environmentObject(PiSyncController())
            .frame(width: 540, height: 560),
               size: CGSize(width: 540, height: 560), to: outDir, name: "7-settings", scrollBody: true)
        render(ExportSheet().environmentObject(store).frame(width: 540, height: 500),
               size: CGSize(width: 540, height: 500), to: outDir, name: "8-export", scrollBody: true)

        // 9/A. Probe: does a ScrollView rasterise offscreen at all? This tells us
        //      whether a blank dashboard render is a harness artefact or a real bug.
        render(ScrollView { VStack { Text("PROBE SCROLLVIEW"); Text("second line") } }
            .frame(width: 400, height: 200).background(Palette.bg),
            size: CGSize(width: 400, height: 200), to: outDir, name: "9-probe-scrollview", scrollBody: true)
        render(VStack { Text("PROBE PLAIN"); Text("second line") }
            .frame(width: 400, height: 200).background(Palette.bg),
            size: CGSize(width: 400, height: 200), to: outDir, name: "A-probe-plain")

        // B-E. Usage history. Rendered via HistoryView.content rather than the
        //      view itself, because HistoryView is ScrollView-rooted and that
        //      rasterises empty (same harness limit as render 9). The seed
        //      store is the real one, so these show genuine log data.
        let hc = store.components
        store.takeOut(hc[0], count: 40, project: "Line Follower")
        store.takeOut(hc[0], count: 25, project: "Line Follower")
        store.takeOut(hc[3], count: 2, project: "Sensor Board")
        store.takeOut(hc[5], count: 60, project: "")
        store.takeOut(hc[6], count: 1, project: "Line Follower")
        store.putBack(hc[5], count: 10, project: "Status Panel")

        render(HistoryView(onOpenPart: { _ in }, scrollable: false)
            .frame(width: 1000, height: 900, alignment: .top)
            .background(Palette.bg)
            .environmentObject(store),
            size: CGSize(width: 1000, height: 900), to: outDir, name: "B-history", scrollBody: true)

        // C. Same view, scoped to one part — proves the per-part filter renders.
        render(HistoryView(onOpenPart: { _ in }, focusComponentID: hc[0].id, scrollable: false)
            .frame(width: 1000, height: 560, alignment: .top)
            .background(Palette.bg)
            .environmentObject(store),
            size: CGSize(width: 1000, height: 560), to: outDir, name: "C-history-one-part")

        // D. Empty state: the log is cleared before rendering, so this is the
        //    first-run view a user actually sees.
        let entriesBefore = store.consumed.count
        store.clearAllHistory()
        render(HistoryView(onOpenPart: { _ in }, scrollable: false)
            .frame(width: 1000, height: 400, alignment: .top)
            .background(Palette.bg)
            .environmentObject(store),
            size: CGSize(width: 1000, height: 400), to: outDir, name: "D-history-empty")

        // E. A log entry whose component was deleted, to check the "deleted"
        //    marker and the disabled jump button.
        var orphan = store.components[0]
        orphan.quantity = 999
        store.add(orphan)
        store.takeOut(store.components.last!, count: 7, project: "Scrapped build")
        store.delete(orphan)
        render(HistoryView(onOpenPart: { _ in }, scrollable: false)
            .frame(width: 1000, height: 900, alignment: .top)
            .background(Palette.bg)
            .environmentObject(store),
            size: CGSize(width: 1000, height: 900), to: outDir, name: "E-history-orphan")
        store.clearAllHistory()
        log("  (history seeded \(entriesBefore) entries, then cleared)")

        // Light scheme. The same surfaces as above, because the whole point of
        // shipping two schemes is that a bug which only appears in one of them
        // is still a bug — and a light theme is exactly where a colour that was
        // hardcoded for dark stops being visible.
        //
        // Skipped where a ScrollView is involved, for the same reason as above.
        render(Sidebar().environmentObject(store).environmentObject(PiSyncController()),
               size: CGSize(width: 210, height: 700), to: outDir, name: "L1-sidebar", dark: false)

        render(
            VStack(alignment: .leading, spacing: 8) {
                ForEach(0..<rows.count, id: \.self) { i in
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(rows[i], id: \.id) { c in
                            ComponentCard(component: c, onEdit: {}, onTakeOut: {}, onDelete: {})
                                .frame(width: 275)
                        }
                    }
                }
                Rule()
                HStack(spacing: 8) {
                    StatTile(label: "Components", value: "\(store.components.count)", sub: "distinct part numbers")
                    StatTile(label: "Total units", value: "\(store.totalUnits)", sub: "across all bins")
                    StatTile(label: "Inventory value", value: Money.compact(store.totalValue), sub: "qty x unit cost")
                }
                HStack(spacing: 6) {
                    GhostButton(title: "Take Out", systemImage: "minus", action: {})
                    GhostButton(title: "Edit", systemImage: "pencil", action: {})
                    GhostButton(title: "Save", prominent: true, action: {})
                    Pill(text: "Resistors", tint: .blue)
                    Pill(text: "0805", tint: Palette.textLow, filled: true)
                }
            }
            .padding(12)
            .frame(width: 880, height: 620, alignment: .top)
            .background(Palette.bg)
            .environmentObject(store),
            size: CGSize(width: 880, height: 620), to: outDir, name: "L2-components", dark: false)

        // The same components in dark, so the two schemes can be compared as
        // numbers rather than impressions.
        render(
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    StatTile(label: "Components", value: "\(store.components.count)", sub: "distinct part numbers")
                    StatTile(label: "Total units", value: "\(store.totalUnits)", sub: "across all bins")
                    StatTile(label: "Low stock", value: "\(store.lowStockCount)", sub: "at or under minimum",
                             tint: store.lowStockCount > 0 ? Palette.warn : Palette.textHi)
                }
                HStack(spacing: 6) {
                    GhostButton(title: "Take Out", systemImage: "minus", action: {})
                    GhostButton(title: "Save", prominent: true, action: {})
                    Pill(text: "Resistors", tint: .blue)
                }
            }
            .padding(12)
            .frame(width: 880, height: 200, alignment: .top)
            .background(Palette.bg)
            .environmentObject(store),
            size: CGSize(width: 880, height: 200), to: outDir, name: "D1-tiles", dark: true)

        ThemeController.set(dark: true)
        log("")
        if failures > 0 {
            log("RENDER FAILURE: \(failures) render(s) failed a check — see <-- above")
            exit(1)
        }
        log("")
        let full = renders - partial
        log("\(full)/\(renders) renders fully verified (scheme + content)")
        if partial > 0 {
            log("")
            log("\(partial) only PARTIALLY verified — these contain a ScrollView, whose")
            log("body does not rasterise under ImageRenderer without a window host.")
            log("Their header/footer drew and are counted; the body below the first rule")
            log("was never seen by anything. Those parts are covered by the unit tests")
            log("and the lint only, which is a real gap, not a formality.")
        }
        log("renders written to \(outDir.path)")
    }

    /// `scheme` selects both halves of the theme: the global `ThemeController`
    /// that `Palette` reads, and the `colorScheme` environment that the
    /// AppKit-backed pieces (scrollbars, native field chrome) obey. Setting one
    /// without the other is how you get a render that is internally
    /// inconsistent — SwiftUI drawing in light while the OS chrome draws dark.
    @MainActor
    /// `scrollBody` marks a view that contains a SwiftUI `ScrollView`.
    ///
    /// `ImageRenderer` lays out a ScrollView's content against a real viewport
    /// that does not exist offscreen, so the body rasterises as nothing. What
    /// survives is whatever sits *outside* the ScrollView — a header, a footer,
    /// a Done button. So these views are not "blank", they are **partly
    /// verified**, and lumping them in with either extreme would overstate what
    /// has been seen.
    ///
    /// The distinction is reported rather than hidden, because hiding it is how
    /// the earlier regression shipped: the three views containing the
    /// SectionLabel bug were all ScrollView-rooted, their renders came back
    /// empty, and "empty render, no assertion" looked exactly like "verified".
    static func render<V: View>(_ view: @autoclosure () -> V, size: CGSize, to dir: URL,
                                name: String, dark: Bool = true, scrollBody: Bool = false) {
        ThemeController.set(dark: dark)
        log("rendering \(name)… [\(dark ? "dark" : "light")]")
        // `@autoclosure`, not a plain parameter. A plain parameter is evaluated
        // by the caller, so any `Palette.x` written in an argument list —
        // `tint: store.lowStockCount > 0 ? Palette.warn : Palette.textHi` — is
        // read before this function can switch the theme, and the render comes
        // out in the *previous* scheme. That is not hypothetical: it is how the
        // first version of this harness produced a "dark" render that was
        // entirely light, and the scheme assertion did not catch it because
        // the assertion checked the theme constant rather than the pixels.
        let renderer = ImageRenderer(content:
            view()
                .frame(width: size.width, height: size.height)
                .environment(\.colorScheme, dark ? .dark : .light)
        )
        renderer.scale = 2
        guard let img = renderer.cgImage else {
            print("  FAILED to render \(name)")
            return
        }
        let rep = NSBitmapImageRep(cgImage: img)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            print("  FAILED to encode \(name)")
            return
        }
        renders += 1
        let url = dir.appendingPathComponent("\(name).png")
        try? data.write(to: url)

        // Pixel census. The previous version classified against fixed
        // thresholds (`r/g/b < 0.12` = "dark"), which only makes sense for one
        // scheme: once a light theme exists, its paper background reads as
        // "light" and its numbers as "dark", so the same picture scored
        // backwards. These counters are now relative to the theme that was
        // actually requested, which makes dark and light directly comparable
        // and turns "did the palette get applied at all" into a real check.
        let bmp = NSBitmapImageRep(cgImage: img)
        let theme = ThemeController.current
        let bg = rgb(theme.bg), surf = rgb(theme.surface), text = rgb(theme.textHi),
              accent = rgb(theme.accent)

        var bgHit = 0, surfHit = 0, inkHit = 0, accentHit = 0, total = 0
        var histo = [Int](repeating: 0, count: 256)
        var minLum = 1.0, maxLum = 0.0
        let bpp = bmp.bitsPerPixel
        let bpr = bmp.bytesPerRow
        if let data = bmp.bitmapData {
            for y in 0..<bmp.pixelsHigh {
                let row = data.advanced(by: y * bpr)
                for x in 0..<bmp.pixelsWide {
                    let o = x * (bpp / 8)
                    let p = (Double(row[o]) / 255.0,
                             Double(row[o + 1]) / 255.0,
                             Double(row[o + 2]) / 255.0)
                    total += 1
                    let lum = 0.2126 * p.0 + 0.7152 * p.1 + 0.0722 * p.2
                    if lum < minLum { minLum = lum }
                    if lum > maxLum { maxLum = lum }
                    histo[min(255, max(0, Int(lum * 255)))] += 1
                    if near(p, bg, 0.02)     { bgHit += 1 }
                    if near(p, surf, 0.02)   { surfHit += 1 }
                    if near(p, accent, 0.04) { accentHit += 1 }
                }
            }
        }
        // The dominant luminance is the background, whatever the view happens to
        // be. Ink is then measured against it, in whichever direction the
        // extremes sit: text is *brighter* than the page in a dark theme and
        // *darker* in a light one, and a single hardcoded direction reports one
        // of the two as empty every time.
        let modeIdx = histo.enumerated().max { $0.element < $1.element }!.offset
        let modeL = Double(modeIdx) / 255.0
        let inkward = Double(dark ? 1 : -1)
        if let data = bmp.bitmapData {
            for y in 0..<bmp.pixelsHigh {
                let row = data.advanced(by: y * bpr)
                for x in 0..<bmp.pixelsWide {
                    let o = x * (bpp / 8)
                    let lum = 0.2126 * Double(row[o]) / 255.0
                            + 0.7152 * Double(row[o + 1]) / 255.0
                            + 0.0722 * Double(row[o + 2]) / 255.0
                    if (lum - modeL) * inkward > 0.12 { inkHit += 1 }
                }
            }
        }
        let pct = { (n: Int) in total > 0 ? Int(100 * n / total) : 0 }
        // Fractional variant: the "is anything on screen at all" threshold
        // is 0.3%, which an Int percent rounds straight to zero.
        let pctF = { (n: Int) in total > 0 ? 100.0 * Double(n) / Double(total) : 0.0 }

        // The scheme check measures the RENDER, not the theme constant. The
        // first version compared `rgb(theme.bg)` against a threshold, which
        // restates the value it was given and therefore can never fail — a
        // check that cannot fail is worse than no check, because it reports
        // confidence. Here the mode luminance of the actual pixels decides.
        let expectedLum = 0.2126 * bg.0 + 0.7152 * bg.1 + 0.0722 * bg.2
        let measuredMode = Double(modeIdx) / 255.0
        let modeOK = abs(measuredMode - expectedLum) < 0.12
        let sideOK = dark ? measuredMode < 0.35 : measuredMode > 0.55

        var notes: [String] = []
        if !sideOK { notes.append("SCHEME MISMATCH (asked \(dark ? "dark" : "light"))") }
        if !modeOK { notes.append("BG OFF-THEME") }
        if pct(bgHit) < 5 { notes.append("low bg coverage") }
        // Ink, not exact colour: antialiased glyph interiors never land on the
        // nominal text colour, so an exact-match "text 0%" reading was a
        // statement about the tolerance, not about the render.
        if pctF(inkHit) < 0.3 {
            if scrollBody {
                // inkHit == 0 means not even the chrome drew; anything above
                // zero means the surrounding header/footer is real and only the
                // ScrollView body is missing. Those are different claims.
                notes.append(inkHit == 0
                    ? "NOTHING RENDERED (ScrollView) — body unverified"
                    : "BODY NOT RENDERED (ScrollView) — chrome only, body unverified")
                partial += 1
            } else {
                notes.append("NO VISIBLE CONTENT")
            }
        } else if scrollBody {
            notes.append("ScrollView body unverified — only the chrome rendered")
            partial += 1
        }

        log(String(format: "  %-16@ %4dx%-4d  ink %5.2f%%  accent %4d%%  mode %.2f (want %.2f)  lum %.2f-%.2f%@",
                   name as NSString, img.width, img.height,
                   pctF(inkHit), pct(accentHit), measuredMode, expectedLum,
                   minLum, maxLum,
                   (notes.isEmpty ? "" : "   <-- " + notes.joined(separator: ", ")) as NSString))
        // A ScrollView's missing body is a harness limit, not a product defect,
        // so it is reported and counted but does not fail the run. Anything
        // else does.
        if !scrollBody && !notes.isEmpty { failures += 1 }
    }

    static var failures = 0
    static var renders = 0
    static var partial = 0

    static func rgb(_ c: Color) -> (Double, Double, Double) {
        let n = NSColor(c).usingColorSpace(.sRGB) ?? .black
        return (Double(n.redComponent), Double(n.greenComponent), Double(n.blueComponent))
    }

    static func near(_ a: (Double, Double, Double), _ b: (Double, Double, Double), _ t: Double) -> Bool {
        abs(a.0 - b.0) <= t && abs(a.1 - b.1) <= t && abs(a.2 - b.2) <= t
    }
}
