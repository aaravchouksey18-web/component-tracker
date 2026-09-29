// Layout probe: what size is each card actually offered, in each skin?
//
// The suspicion is structural, not aesthetic. `CardChrome` puts a `Canvas`
// inside a `ZStack` in the Blueprint branch, and a `Canvas` is greedy in both
// axes — it accepts whatever proposal it is given rather than proposing its own
// size. Inside a `ZStack` that means it competes with the card's real content
// for the space the parent is offering, which is exactly the failure the lint's
// greedy-child rule was written to catch. The rule skipped `CardChrome` because
// it is used in one file, and the usage-derived set is what let a greedy
// Canvas through the only check that would have seen it.
//
// So: measure. `Probe` is a `Layout` that records the size its child is
// handed. Run it per skin and the answer is a number rather than an opinion.

import SwiftUI
import AppKit

/// Records the size its subtree was offered, then behaves exactly like a
/// passthrough so the measurement does not change the thing measured.
struct Probe: Layout {
    let tag: String
    static var sizes: [String: [CGSize]] = [:]

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // Measure against the proposal as offered, including nil dimensions —
        // the point is to see what the parent actually hands a greedy child.
        let s = subviews[0].sizeThatFits(proposal)
        Probe.sizes[tag, default: []].append(s)
        return s
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for sv in subviews {
            sv.place(at: bounds.origin, anchor: .topLeading,
                     proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
        }
    }
}

@MainActor
enum LayoutProbe {
    static func run() {
        let store = InventoryStore()
        store.replaceAll(with: InventoryStore.seedComponents())
        let cards = Array(store.filtered.prefix(4))

        print("size offered to a single card, by skin:")
        for skin in Skin.all {
            for dark in [true, false] {
                SkinController.set(skin: skin, dark: dark)
                let tag = "\(skin.name)/\(dark ? "dark" : "light")"
                Probe.sizes[tag] = []

                // Same shape the render harness uses: a plain HStack, because
                // LazyVGrid is a lazy container and reports nothing offscreen.
                let view = HStack(alignment: .top, spacing: 8) {
                    ForEach(cards, id: \.id) { c in
                        Probe(tag: tag) {
                            ComponentCard(component: c, onEdit: {}, onTakeOut: {}, onDelete: {})
                        }
                        .frame(width: 285)
                    }
                }
                // 10_000 is "as much as you like", which is what a grid row
                // offers in the vertical direction.
                _ = view.frame(width: 1200, height: 10_000, alignment: .top)
                _ = NSHostingView(rootView: view.environmentObject(store))
                    .fittingSize

                let got = Probe.sizes[tag] ?? []
                let hs = got.map { "\(Int($0.width))x\(Int($0.height))" }
                print("  \(tag.padding(toLength: 22, withPad: " ", startingAt: 0))  \(hs.joined(separator: "  "))")
            }
        }

        print("")
        print("size offered to the whole card field (ScrollView background Canvas):")
        for skin in Skin.all {
            SkinController.set(skin: skin, dark: true)
            let tag = "\(skin.name)/field"
            Probe.sizes[tag] = []
            // ComponentCardGrid takes components, not the store.
            let field = ComponentCardGrid(components: store.filtered,
                                          selection: .constant([]),
                                          onEdit: { _ in }, onTakeOut: { _ in },
                                          onDelete: { _ in })
                .frame(width: 1000, height: 10_000, alignment: .top)
            _ = NSHostingView(rootView: field.environmentObject(store)).fittingSize
            let got = Probe.sizes[tag] ?? []
            print("  \(tag.padding(toLength: 22, withPad: " ", startingAt: 0))  "
                  + (got.isEmpty ? "(no probe reached — grid is lazy)" :
                     got.map { "\(Int($0.width))x\(Int($0.height))" }.joined(separator: "  ")))
        }
        SkinController.set(skin: .graphite, dark: true)
    }
}

@main
struct LayoutProbeMain {
    @MainActor
    static func main() { LayoutProbe.run() }
}
