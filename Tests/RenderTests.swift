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
            size: CGSize(width: 1000, height: 720), to: outDir, name: "4-dashboard")

        // 5. Add/Edit sheet. Needs the store injected: the editor reads it for
        //    the duplicate-part-number check.
        render(ComponentEditor(component: demo.first)
                .environmentObject(store)
                .frame(width: 620, height: 640),
               size: CGSize(width: 620, height: 640), to: outDir, name: "5-editor")

        // 6. Take out sheet
        render(TakeOutSheet(component: demo.first!).environmentObject(store),
               size: CGSize(width: 430, height: 420), to: outDir, name: "6-takeout")

        // 7. Settings + export
        render(SettingsSheet().environmentObject(store)
            .environmentObject(PiSyncController())
            .frame(width: 540, height: 560),
               size: CGSize(width: 540, height: 560), to: outDir, name: "7-settings")
        render(ExportSheet().environmentObject(store).frame(width: 540, height: 500),
               size: CGSize(width: 540, height: 500), to: outDir, name: "8-export")

        // 9/A. Probe: does a ScrollView rasterise offscreen at all? This tells us
        //      whether a blank dashboard render is a harness artefact or a real bug.
        render(ScrollView { VStack { Text("PROBE SCROLLVIEW"); Text("second line") } }
            .frame(width: 400, height: 200).background(Palette.bg),
            size: CGSize(width: 400, height: 200), to: outDir, name: "9-probe-scrollview")
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
            size: CGSize(width: 1000, height: 900), to: outDir, name: "B-history")

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

        log("renders written to \(outDir.path)")
    }

    @MainActor
    static func render<V: View>(_ view: V, size: CGSize, to dir: URL, name: String) {
        log("rendering \(name)…")
        let renderer = ImageRenderer(content:
            view
                .frame(width: size.width, height: size.height)
                .environment(\.colorScheme, .dark)
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
        let url = dir.appendingPathComponent("\(name).png")
        try? data.write(to: url)

        // Full-resolution pixel census so a blank or mis-themed render is obvious.
        // Reads the raw bitmap rather than colorAt(), which is far too slow per-pixel.
        let bmp = NSBitmapImageRep(cgImage: img)
        var dark = 0, light = 0, coloured = 0, total = 0
        var maxLum = 0.0
        let bpp = bmp.bitsPerPixel
        let bpr = bmp.bytesPerRow
        if let data = bmp.bitmapData {
            for y in 0..<bmp.pixelsHigh {
                let row = data.advanced(by: y * bpr)
                for x in 0..<bmp.pixelsWide {
                    let o = x * (bpp / 8)
                    let r = Double(row[o]) / 255.0
                    let g = Double(row[o + 1]) / 255.0
                    let b = Double(row[o + 2]) / 255.0
                    total += 1
                    let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
                    if lum > maxLum { maxLum = lum }
                    if r < 0.12 && g < 0.12 && b < 0.12 { dark += 1 }
                    else if r > 0.55 && g > 0.55 && b > 0.55 { light += 1 }
                    else { coloured += 1 }
                }
            }
        }
        let pct = { (n: Int) in total > 0 ? Int(100 * n / total) : 0 }
        let line = String(format: "  %-18@ %4dx%-4d  dark %3d%%  text %4d%%  accent %3d%%  maxLum %.2f",
                          name as NSString, img.width, img.height,
                          pct(dark), pct(light), pct(coloured), maxLum)
        log(line)
    }
}
