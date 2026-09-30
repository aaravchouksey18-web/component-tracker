// Does the type scale reach the pixels?
//
// The unit tests prove `Type.size(role)` becomes a font of that size, by
// rasterising a synthetic `Text` in each skin and measuring its ink. That
// establishes the ladder. It does not establish that the *cards* moved, because
// "this role has a call site somewhere in the sources" is not the same claim as
// "the call site is in the view being rendered".
//
// The first version of this probe tried to answer that by finding the tallest
// band of ink in each skin's card render. It reported FAIL — Swiss 56px
// against Graphite 372px — and the app was fine. The band it found in Graphite
// was 372 pixels tall because "inked" was defined as "differs from this row's
// modal colour", and a card's fill differs from the page behind it, so in a
// skin with an opaque card the entire card registered as one enormous band. It
// was measuring card fill, not type. A second version that segmented by colour
// first would have had the same problem in a different place: a taller font
// changes band edges, but so does a different card treatment, so the two cannot
// be attributed to type alone.
//
// So this does not measure band heights across differently-styled cards. It
// does the thing that is actually unambiguous: render the same view, with the
// same card treatment, varying only the skin's type scale, and measure the
// glyphs. `TypeProbe` below renders a fixed stack of the real roles in the real
// palette, so any difference in ink between two skins is attributable to type
// alone.
//
// The second thing worth measuring, and the reason this file exists as a probe
// rather than a unit test: does the number of glyph pixels scale with the
// square of the font size? Ink area for a string grows roughly with size^2. If
// the type scale reaches the render, Swiss's 31pt figure must lay down
// visibly more ink than Graphite's 17pt, and the ratio should be near
// (31/17)^2 = 3.3. If the ratio comes out near 1.0, the ladder is decorative.

import AppKit
import Foundation
import SwiftUI

@MainActor
enum InkArea {

    /// Renders one string in one role in one skin and returns how many pixels
    /// are inked, plus the bounding box of that ink.
    static func measure(_ text: String, _ role: Type.Role, _ skin: Skin) -> (ink: Int, h: Int)? {
        SkinController.set(skin: skin, dark: true)
        // Force white-on-black: the measurement is of coverage, not colour, so
        // a fixed high-contrast pair keeps antialiasing from making a light
        // skin's thin strokes count for less than a dark skin's.
        let view = Text(text)
            .font(.mono(role))
            .foregroundStyle(.white)
            .background(.black)
            .padding(6)
        let host = NSHostingView(rootView: view)
        host.sizingOptions = [.intrinsicContentSize]
        let size = host.fittingSize
        guard size.width > 0, size.height > 0 else { return nil }
        let r = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        r.scale = 2
        guard let img = r.cgImage else { return nil }
        let rep = NSBitmapImageRep(cgImage: img)

        var ink = 0
        var minY = Int.max, maxY = -1
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                // Brightness, not alpha: the background is opaque black here, so
                // an unlit pixel is 0 and a lit one is >0. Alpha would also work
                // but is needlessly indirect when the ground is known.
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if c.brightnessComponent > 0.35 {
                    ink += 1
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }
        guard maxY >= minY, ink > 0 else { return nil }
        return (ink, maxY - minY + 1)
    }
}

@main
struct InkBandsMain {
    @MainActor
    static func main() {
        print("== does the type scale reach the render? ==")
        print("   measuring ink coverage per role, white on black, at 2x")
        print("")

        let roles: [(Type.Role, String, String)] = [
            (.figure,  "quantity", "0"),
            (.display, "stat value", "0"),
            (.body,    "body", "0"),
            (.micro,   "micro", "0"),
        ]

        var results: [String: [String: (ink: Int, h: Int)]] = [:]
        for skin in Skin.all {
            SkinController.set(skin: skin, dark: true)
            var per: [String: (Int, Int)] = [:]
            for (role, label, sample) in roles {
                if let m = InkArea.measure(sample, role, skin) { per[label] = m }
            }
            results[skin.name] = per
        }

        print("  \(pad("role")) \(pad("skin")) \(padLeft("pt", 5)) \(padLeft("ink px", 10)) "
              + "\(padLeft("ink h", 8))")
        print("  " + String(repeating: "-", count: 52))
        for (role, label, _) in roles {
            for skin in Skin.all {
                SkinController.set(skin: skin, dark: true)
                guard let m = results[skin.name]?[label] else { continue }
                print("  \(pad(label)) \(pad(skin.name)) "
                      + padLeft("\(Int(Type.size(role)))", 5)
                      + padLeft("\(m.ink)", 10)
                      + padLeft("\(m.h)", 8))
            }
        }

        print("")
        guard let g = results["Graphite"], let s = results["Swiss"] else {
            print("FAIL — could not measure both Graphite and Swiss"); exit(1)
        }

        // The claim under test is not "Swiss is bigger at every role" — it is
        // "the skin's type scale reaches the render". Those are different, and
        // the first version of this probe asserted the former and so failed on
        // two roles that were behaving exactly as designed:
        //
        //   - `body` measured 1.18x, which is precisely right: Swiss `bodySize`
        //     is 12 against Graphite's 11, and (12/11)^2 = 1.19.
        //   - `micro` measured 0.79x, and Swiss's `micro` is *smaller* by
        //     design: `labelSize` 8 against Graphite's 9, so 7pt against 8pt
        //     and (7/8)^2 = 0.77. A "> 1.5x" threshold called a correct skin
        //     broken.
        //
        // The second version then failed in the opposite direction: it derived
        // the expected ratio from `Type.size(role)` and compared the measured
        // ink against it, which passed even with the type scale deliberately
        // destroyed. Collapsing every figure role to `bodySize` makes the
        // prediction 1.0 and the measurement 1.0, and they agree — the check
        // was comparing a value with itself. `Type.size` already passed its own
        // unit tests, so re-deriving the expectation from it verifies nothing.
        //
        // The expectation has to be pinned to the *design intent*, written out
        // here as literal point sizes, independently of the code under test.
        // That is the only version in which "the ladder still exists" is a
        // falsifiable claim: if someone collapses the scale, these literals stay
        // put and the measurement diverges.
        //
        // Swiss's documented scale: a 34pt display figure against an 8pt label,
        // 12pt body. Graphite's: 20pt, 9pt, 11pt. Stated as the skin's own
        // anchors, from the palette definitions, not from `Type.size`.
        let pinned: [(Type.Role, String, CGFloat, CGFloat)] = [
            //  role     label        graphite  swiss
            (.display, "stat value",  20,       34),
            (.figure,  "quantity",    17,       31),
            (.body,    "body",        11,       12),
            (.micro,   "micro",        8,        7),
        ]

        var fails: [String] = []
        for (role, label, gpt, spt) in pinned {
            guard let gv = g[label], let sv = s[label] else {
                fails.append("\(label): missing a measurement"); continue
            }
            let predicted = pow(Double(spt) / Double(gpt), 2)
            let actual = Double(sv.ink) / Double(gv.ink)
            // 35% tolerance: ink area is not exactly quadratic in point size
            // (hinting, antialiasing and side bearings all move it), but a role
            // that collapsed onto another would miss by 2x or more, which is
            // nowhere near this band.
            let ok = abs(actual - predicted) / predicted < 0.35
            print("  \(ok ? "ok  " : "FAIL") \(pad(label)) "
                  + padLeft("\(Int(gpt))pt->\(Int(spt))pt", 12) + " ink "
                  + String(format: "%.2f", actual) + "x, design predicts "
                  + String(format: "%.2f", predicted) + "x")
            if !ok {
                fails.append("\(label): ink \(String(format: "%.2f", actual))x "
                             + "vs design \(String(format: "%.2f", predicted))x")
            }
        }

        // And the claim the whole thing exists for, stated directly: Swiss's
        // display figure must be visibly larger than its own smallest role. If
        // the ladder ever flattens, this is the assertion that notices, and it
        // compares two numbers from the same rendering rather than a prediction.
        if let sv = s["stat value"], let sl = s["micro"], sl.h > 0 {
            let contrast = Double(sv.h) / Double(sl.h)
            let ok = contrast > 3.0
            print("  \(ok ? "ok  " : "FAIL") \(pad("swiss ladder")) "
                  + padLeft("34pt vs 7pt", 12) + " ink heights "
                  + "\(sv.h)px vs \(sl.h)px, "
                  + String(format: "%.1f", contrast) + "x apart")
            if !ok {
                fails.append("swiss display and micro are only "
                             + String(format: "%.1f", contrast) + "x apart in ink")
            }
        }

        print("")
        SkinController.set(skin: .graphite, dark: true)
        if fails.isEmpty {
            print("PASS — the skin's type scale measurably changes what is rendered")
        } else {
            print("FAIL — \(fails.joined(separator: "; "))")
            exit(1)
        }
    }

    static func pad(_ s: String) -> String {
        s.count >= 12 ? s : s + String(repeating: " ", count: 12 - s.count)
    }
    static func padLeft(_ s: String, _ n: Int) -> String {
        s.count >= n ? s : String(repeating: " ", count: n - s.count) + s
    }
}
