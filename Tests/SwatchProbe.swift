// Pixel probe: does the sidebar's Themes section actually draw all three
// skin swatches, in their own colours?
//
// Why a probe and not a string search: `strings` on a Swift binary misses
// literals under ~16 bytes, because the compiler bakes them into the
// instruction stream as immediates. So "Graphite" not appearing in the
// binary says nothing about whether the app can display it. Pixels do.
//
// The test: each skin's swatch contains a 7x5pt band filled with that skin's
// own accent colour. If all three accents are present in the sidebar render,
// the switcher is on screen and each row is previewing itself. If one is
// missing, a row is not drawing — which is the failure that a unit test on
// `Skin.all.count == 3` cannot see, because the data is right and the view is
// not.

import AppKit

let path = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "build/renders/S-gd-sidebar.png"

// Decode the PNG bytes directly. The first version of this probe went through
// `NSImage(contentsOf:).tiffRepresentation`, and that round-trip re-encodes the
// bitmap — the resulting rep had a different layout, so every pixel offset was
// wrong and all three swatches read as absent. They were on screen the whole
// time; the probe was looking at garbage.
//
// The lesson generalises past this file: a probe that reports a confident
// "ABSENT" is more dangerous than no probe, because it looks like a finding.
guard let bytes = FileManager.default.contents(atPath: path),
      let rep = NSBitmapImageRep(data: bytes),
      let data = rep.bitmapData else {
    FileHandle.standardError.write("could not decode \(path)\n".data(using: .utf8)!)
    exit(1)
}
guard rep.samplesPerPixel >= 3 else {
    FileHandle.standardError.write("unexpected samplesPerPixel \(rep.samplesPerPixel)\n".data(using: .utf8)!)
    exit(1)
}

// Pulled from the palette literals in Design.swift. Hardcoded here on purpose:
// if these drift from the source, the probe fails loudly instead of quietly
// confirming whatever the binary happens to be doing.
// Written as hex bytes and normalised here, rather than as decimal fractions.
// Hand-typed decimals are where a probe quietly stops matching its own target:
// 0x4C written as 76 and compared against a 0...1 sample can never be within
// tolerance, and the result is a confident "ABSENT" for a colour that is on
// screen. The first version of this file did exactly that and reported all
// three swatches missing while the pixels were plainly there.
let accentBytes: [(String, (UInt32, UInt32, UInt32))] = [
    ("Graphite   #4C8DF6", (0x4C, 0x8D, 0xF6)),
    ("Swiss      #FF3B30", (0xFF, 0x3B, 0x30)),
    ("Blueprint  #4FC3F7", (0x4F, 0xC3, 0xF7)),
]
let accents: [(String, (Double, Double, Double))] = accentBytes.map {
    ($0.0, (Double($0.1.0) / 255, Double($0.1.1) / 255, Double($0.1.2) / 255))
}

let bpp = rep.bitsPerPixel, bpr = rep.bytesPerRow
var counts = [String: Int]()

for y in 0..<rep.pixelsHigh {
    let row = data.advanced(by: y * bpr)
    for x in 0..<rep.pixelsWide {
        let o = x * (bpp / 8)
        let p = (Double(row[o]) / 255.0,
                 Double(row[o + 1]) / 255.0,
                 Double(row[o + 2]) / 255.0)
        for (name, want) in accents {
            // Tolerance 0.02: the swatch is a flat fill, but the render is
            // scaled 2x and the band is 7pt wide, so edge pixels are blended.
            if abs(p.0 - want.0) <= 0.02 && abs(p.1 - want.1) <= 0.02
                && abs(p.2 - want.2) <= 0.02 {
                counts[name, default: 0] += 1
            }
        }
    }
}

let total = rep.pixelsWide * rep.pixelsHigh
print("probe: \(path)  \(rep.pixelsWide)x\(rep.pixelsHigh)")
var missing: [String] = []
for (name, _) in accents {
    let n = counts[name] ?? 0
    let pct = 100.0 * Double(n) / Double(total)
    // A 7x5pt band at 2x is 14x10 = 140px, so anything under ~40 pixels means
    // the band is not being drawn at all rather than drawn small.
    let ok = n >= 40
    if !ok { missing.append(name) }
    print(String(format: "  %@  %6d px  %6.3f%%  %@",
                 name as NSString, n, pct,
                 (ok ? "present" : "ABSENT") as NSString))
}
print(missing.isEmpty
      ? "PASS — all three skin swatches are drawn in the sidebar"
      : "FAIL — not drawn: \(missing.joined(separator: ", "))")

// ---------------------------------------------------------------- backdrop leak
//
// The second check, and the one that would have caught the defect this probe
// was written after: a card sitting on a ruled field must be opaque, or the
// field runs through the text.
//
// Blueprint set `cardFill: false` and put a 24pt grid behind the content.
// "Not filled" was being read as "transparent", so the grid drew straight
// through every part number. Nothing caught it: the palette was correct, the
// card's layout size was correct, the card rendered, and the ink percentage
// went *up*, because grid lines are ink. Every signal the harness had said
// fine.
//
// COUNT LINES, DON'T COUNT COLOURS. The first version of this check counted
// pixels matching the grid's composite colour and used a tolerance. After the
// fix it still reported 529 — and zero of them were the grid colour. They were
// the card's own antialiased hairlines, which blend to within 0.035 of it. The
// only way to make that check pass was to raise the threshold until the
// hairlines stopped tripping it, which is tuning a test to agree with itself.
//
// The defect has a far better signature than a colour: a leaked field is a set
// of *continuous vertical lines crossing the card from top to bottom*. An
// opaque card has none, and its own hairlines run horizontally. So this counts
// near-full-height vertical line segments inside a card-sized window.
//
// The threshold is 3. A leak produces ~11. Zero produces 0. The gap is wide and
// the measurement is a count of a topological feature, not a colour
// coincidence, so nothing here needs calibrating.

func loadRep(_ path: String) -> NSBitmapImageRep? {
    guard let b = FileManager.default.contents(atPath: path) else { return nil }
    return NSBitmapImageRep(data: b)
}

func gridish(_ row: UnsafeMutablePointer<UInt8>, _ o: Int) -> Bool {
    let p = (Double(row[o]) / 255, Double(row[o + 1]) / 255, Double(row[o + 2]) / 255)
    let g = (0x0F / 255.0, 0x2E / 255.0, 0x4E / 255.0)
    return abs(p.0 - g.0) <= 0.035 && abs(p.1 - g.1) <= 0.035 && abs(p.2 - g.2) <= 0.035
}

if let cardArg = CommandLine.arguments.dropFirst().first(where: { $0.hasSuffix("-cards.png") }),
   let r = loadRep(cardArg), let d = r.bitmapData {
    let bpp = r.bitsPerPixel, bpr = r.bytesPerRow
    // A card is 285x188pt; renders are at scale 2, so 570x376px.
    let w = 570, h = 376
    let x0 = max(0, min(r.pixelsWide / 2 - w / 2, r.pixelsWide - w))
    let y0 = max(0, min(r.pixelsHigh / 2 - h / 2, r.pixelsHigh - h))

    // For each column, what fraction of the window's height is grid-coloured?
    // A field line runs the full height; a hairline inside a card is a
    // horizontal rule and so lights up only a couple of columns' worth of rows.
    var fullHeightCols: [Int] = []
    for x in x0..<(x0 + w) {
        var n = 0
        for y in y0..<(y0 + h) where gridish(d.advanced(by: y * bpr), x * (bpp / 8)) {
            n += 1
        }
        if Double(n) / Double(h) > 0.75 { fullHeightCols.append(x - x0) }
    }
    // Collapse adjacent columns into single lines.
    var lines: [[Int]] = []
    for x in fullHeightCols {
        if var last = lines.last, x - last.last! <= 2 {
            last.append(x); lines[lines.count - 1] = last
        } else {
            lines.append([x])
        }
    }

    let leak = lines.count >= 3
    print("")
    print("backdrop leak: \(cardArg)")
    print("  full-height vertical lines inside a card: \(lines.count)  (limit 2)")
    if let f = lines.first?.first, let l = lines.last?.last, lines.count > 1 {
        print("  spanning x \(f)...\(l) at \((l - f) / (lines.count - 1))px pitch"
              + "  (48px = the 24pt field)")
    }
    print(leak
          ? "FAIL — the ruled field is drawing through the card"
          : "PASS — cards are opaque; the field stops at the card edge")
    if !missing.isEmpty || leak { exit(1) }
}
exit(0)
