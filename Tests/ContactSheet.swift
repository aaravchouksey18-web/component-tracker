// Build a contact sheet from render PNGs. Run via ./sheet.sh.
//
// The point is comparison. Three PNGs in three Preview windows means three
// window-switches and three memories, and the eye compares poorly across
// windows — a layout that looks airy next to the window behind it and cramped
// on its own. One image with the three options adjacent makes the differences
// obvious, which is the only reason to render them at all.
//
// Written as a separate single-file program rather than folded into the render
// harness because it has no compile-time relationship to the app: it takes
// paths, not views. Keeping it independent means it survives a change to the
// design system, which is the thing most likely to change again.

import AppKit

struct Entry {
    let url: URL
    let label: String
}

let outPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "build/renders/_sheet.png"

let args = Array(CommandLine.arguments.dropFirst(2))
var entries: [Entry] = []
for a in args {
    // `name=path` or bare `path` (label defaults to the basename).
    if let eq = a.firstIndex(of: "=") {
        let label = String(a[a.startIndex..<eq])
        let p = String(a[a.index(after: eq)...])
        entries.append(Entry(url: URL(fileURLWithPath: p), label: label))
    } else {
        entries.append(Entry(url: URL(fileURLWithPath: a),
                             label: a.split(separator: "/").last.map(String.init) ?? a))
    }
}

guard !entries.isEmpty else {
    FileHandle.standardError.write("usage: sheet.sh <out.png> [label=path ...]\n".data(using: .utf8)!)
    exit(1)
}

func load(_ url: URL) -> NSImage? {
    guard let d = try? Data(contentsOf: url) else { return nil }
    return NSImage(data: d)
}

var images: [(NSImage, String)] = []
for e in entries {
    if let img = load(e.url) { images.append((img, e.label)) } else {
        FileHandle.standardError.write("missing: \(e.url.path)\n".data(using: .utf8)!)
    }
}
guard !images.isEmpty else { exit(1) }

// Every cell is the same size, whichever aspect ratio its image is, so a tall
// sidebar next to a wide card grid does not silently get more room.
// CGFloat throughout: `NSRect` has both an Int and a CGFloat initialiser, so a
// mixed-type sheet compiles up to the first rect and then fails with a message
// about a type that has nothing to do with the bug. One type, no ambiguity.
let cellW: CGFloat = 900, cellH: CGFloat = 560
let pad: CGFloat = 18, labelH: CGFloat = 44
let cols = 2
let rows = Int(ceil(Double(images.count) / Double(cols)))
let W = pad + CGFloat(cols) * (cellW + pad)
let H = pad + CGFloat(rows) * (cellH + labelH + pad)

let sheet = NSImage(size: NSSize(width: W, height: H))
sheet.lockFocus()
// 0.09 luminance, so the sheet itself is neutral and does not tint the
// comparison toward whichever skin happens to be dark.
NSColor(srgbRed: 0.09, green: 0.09, blue: 0.09, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: W, height: H).fill()

let para = NSMutableParagraphStyle()
para.alignment = .center
let labelAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.monospacedDigitSystemFont(ofSize: 22, weight: .semibold),
    .foregroundColor: NSColor(srgbRed: 0.92, green: 0.92, blue: 0.92, alpha: 1),
    .paragraphStyle: para,
]
let subAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 14),
    .foregroundColor: NSColor(srgbRed: 0.55, green: 0.55, blue: 0.55, alpha: 1),
    .paragraphStyle: para,
]

for (i, item) in images.enumerated() {
    let col = i % cols, row = i / cols
    let x = pad + CGFloat(col) * (cellW + pad)
    // Origin is bottom-left, so row 0 must be flipped or the grid comes out
    // upside down relative to the order the files were passed in.
    let y = H - pad - CGFloat(row) * (cellH + labelH + pad) - cellH - labelH

    // Aspect fit inside the cell, centred, never upscaled: enlarging a render
    // does not add detail, it only makes the same pixels larger and easier to
    // mistake for a different layout.
    let src = item.0.size
    let scale = min(cellW / src.width, cellH / src.height)
    let dw = src.width * scale, dh = src.height * scale
    let dx = x + (cellW - dw) / 2
    let dy = y + (cellH - dh) / 2

    NSColor.black.setFill()
    NSRect(x: x, y: y, width: cellW, height: cellH).fill()
    item.0.draw(in: NSRect(x: dx, y: dy, width: dw, height: dh),
                from: .zero, operation: .copy, fraction: 1)
    NSColor(srgbRed: 0.22, green: 0.22, blue: 0.22, alpha: 1).setStroke()
    let b = NSBezierPath(rect: NSRect(x: x, y: y, width: cellW, height: cellH))
    b.lineWidth = 1
    b.stroke()

    let parts: [String] = item.1
        .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        .map(String.init)
    let name = parts.first ?? item.1
    let ns = NSAttributedString(string: name.uppercased(), attributes: labelAttrs)
    ns.draw(in: NSRect(x: x, y: y + labelH - 26, width: cellW, height: 24))
    if parts.count > 1 {
        let ss = NSAttributedString(string: parts[1], attributes: subAttrs)
        ss.draw(in: NSRect(x: x, y: y + 4, width: cellW, height: 20))
    }
}

sheet.unlockFocus()

guard let tiff = sheet.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("failed to encode sheet\n".data(using: .utf8)!)
    exit(1)
}
let out = URL(fileURLWithPath: outPath)
try? FileManager.default.createDirectory(at: out.deletingLastPathComponent(),
                                         withIntermediateDirectories: true)
do {
    try png.write(to: out)
    print("wrote \(out.path) — \(images.count) tiles, \(Int(W))x\(Int(H))")
} catch {
    FileHandle.standardError.write("failed to write: \(error)\n".data(using: .utf8)!)
    exit(1)
}
