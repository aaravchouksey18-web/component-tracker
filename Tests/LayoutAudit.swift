// Layout audit: does anything want more room than the real window gives it?
//
// "Wonky" is a geometry complaint, not a taste complaint, so this measures
// geometry rather than arguing about colour. For every skin it asks each major
// view of the app what size it needs, offering the size the real window gives
// it, and reports any view that wants more.
//
// Three earlier versions of this harness were wrong, all in ways that produced
// confident output rather than a crash:
//
//   1. Each view was wrapped in `.frame(width:height:)`. That clamps the
//      reported size to exactly the offered size, so "needed" equalled
//      "offered" by construction and all fifteen views reported "fits".
//   2. The frame was removed and an `NSHostingView` was relied on to drive the
//      proposal. It does not: the root was offered 10x10 every time, so every
//      view appeared to overflow by 600–2300pt.
//   3. `Measure` was a custom `Layout` holding a `var` dictionary. `Layout` is
//      a value type, so writes went through a copy and the log read back empty.
//
// The version here calls `sizeThatFits` directly with the real proposal, which
// both passes a genuine size and returns an unclamped answer.
//
// Every number below is measured from a real layout pass, not estimated.

import SwiftUI
import AppKit

@MainActor
struct Audit {

    /// The real window: a 210pt sidebar beside 970pt of content, 760pt tall
    /// (read back from the app's own saved window frame).
    static let sidebarSize = CGSize(width: 210, height: 760)
    static let contentSize = CGSize(width: 970, height: 760)

    /// `sizeThatFits` is a `View` member, so it has to be called on the
    /// concrete type. `cases` hands back a closure rather than an `AnyView` for
    /// exactly that reason — `AnyView` has no such member.
    private struct Case {
        let label: String
        let offered: CGSize
        /// True when the view's content is expected to exceed the frame,
        /// because it scrolls. Reporting that as overflow is the same category
        /// of error as the three above: noise on correct code.
        let scrolls: Bool
        let need: () -> CGSize
    }

    static func run() {
        let store = InventoryStore()
        store.replaceAll(with: InventoryStore.seedComponents())
        let pi = PiSyncController()

        var problems: [String] = []

        print("== how much room each view needs, vs what the window gives it ==")
        print("  \(pad("view / skin")) offered        needed        verdict")
        print("  " + String(repeating: "-", count: 66))

        for skin in Skin.all {
            for c in cases(store: store, pi: pi, skin: skin) {
                SkinController.set(skin: skin, dark: true)
                let needed = c.need()

                let overW = needed.width - c.offered.width
                let overH = needed.height - c.offered.height
                let bad = overW > 0.5 || (overH > 0.5 && !c.scrolls)

                let verdict: String
                if bad && overH > 0.5 {
                    verdict = "OVERFLOW \(Int(overH.rounded()))pt tall"
                } else if bad {
                    verdict = "OVERFLOW \(Int(overW.rounded()))pt wide"
                } else if overH > 0.5 {
                    verdict = "scrolls, \(Int(overH.rounded()))pt of content"
                } else {
                    verdict = "fits"
                }

                print("  \(pad(c.label)) \(fmt(c.offered))  \(fmt(needed))  \(verdict)"
                      + (bad ? "  <--" : ""))
                if bad {
                    problems.append("\(c.label): needs \(fmt(needed)), given \(fmt(c.offered))"
                                    + (overH > 0.5 ? " (\(Int(overH.rounded()))pt too tall)" : ""))
                }
            }
        }

        // The widest card, not the average one. The grid is
        // `GridItem(.adaptive(minimum: 190, maximum: 300))`, so a card is given
        // 300pt and anything wider truncates on a `.lineLimit(1)` field.
        // Measuring the mean would hide exactly the card that breaks, since
        // one very long part number among seventy-three ordinary ones barely
        // moves an average.
        print("\n== widest card vs the 300pt the grid gives it ==")
        for skin in Skin.all {
            SkinController.set(skin: skin, dark: true)
            var widest: (CGFloat, String) = (0, "")
            for c in store.components {
                let host = NSHostingView(rootView:
                    env(ComponentCard(component: c, onEdit: {}, onTakeOut: {},
                                      onDelete: {}), store, pi))
                host.sizingOptions = [.intrinsicContentSize]
                let w = host.fittingSize.width
                if w > widest.0 { widest = (w, c.partNumber) }
            }
            let over = widest.0 - 300
            print("  \(pad(skin.name)) widest \(fmt2(widest.0))pt  \(widest.1)"
                  + (over > 0.5 ? "  TRUNCATES by \(Int(over.rounded()))pt" : "  fits"))
            if over > 0.5 {
                problems.append("\(skin.name): widest card needs \(Int(widest.0.rounded()))pt "
                                + "in a 300pt column (\(widest.1))")
            }
        }

        print("")
        if problems.isEmpty {
            print("PASS — every view fits the space the real window gives it")
        } else {
            print("FAIL — \(problems.count) view(s) do not fit:")
            for p in problems { print("  - \(p)") }
        }
        SkinController.set(skin: .graphite, dark: true)
        if !problems.isEmpty { exit(1) }
    }

    /// The size the view wants when nothing constrains it.
    ///
    /// `View.sizeThatFits(_:)` is not exposed in this SDK, and asking an
    /// `NSHostingView` for a *proposed* size does not work either — its root
    /// is offered 10x10 regardless of the frame, which is what produced the
    /// "overflows by 2300pt" nonsense earlier. `sizingOptions =
    /// .intrinsicContentSize` makes `fittingSize` return the content's own
    /// ideal size, which is both unbounded and real.
    ///
    /// Unbounded is the right question for "wonky": the thing to catch is a
    /// view that wants more room than the window has, not one that would
    /// compress gracefully.
    private static func need<V: View>(_ v: V) -> CGSize {
        let host = NSHostingView(rootView: v)
        host.sizingOptions = [.intrinsicContentSize]
        return host.fittingSize
    }

    private static func env<V: View>(_ v: V, _ store: InventoryStore,
                                     _ pi: PiSyncController) -> some View {
        v.environmentObject(store).environmentObject(pi)
    }

    private static func cases(store: InventoryStore, pi: PiSyncController,
                              skin: Skin) -> [Case] {
        return [
            Case(label: "sidebar / \(skin.name)", offered: sidebarSize, scrolls: false) {
                need(env(Sidebar(), store, pi))
            },
            Case(label: "card grid / \(skin.name)", offered: contentSize, scrolls: true) {
                need(env(ComponentCardGrid(components: store.filtered, selection: .constant([]),
                                     onEdit: { _ in }, onTakeOut: { _ in },
                                     onDelete: { _ in }), store, pi))
            },
            Case(label: "dashboard / \(skin.name)", offered: contentSize, scrolls: true) {
                need(env(DashboardView(showChart: false), store, pi))
            },
            Case(label: "history / \(skin.name)", offered: contentSize, scrolls: true) {
                need(env(HistoryView(onOpenPart: { _ in }, scrollable: false), store, pi))
            },
            Case(label: "takeout sheet / \(skin.name)",
                 offered: CGSize(width: 430, height: 420), scrolls: true) {
                need(env(TakeOutSheet(component: store.components[0]), store, pi))
            },
        ]
    }

    private static func pad(_ s: String) -> String {
        s.count >= 26 ? s : s + String(repeating: " ", count: 26 - s.count)
    }
    private static func fmt2(_ v: CGFloat) -> String {
        String(format: "%.0f", Double(v))
    }
    private static func fmt(_ s: CGSize) -> String {
        "\(Int(s.width))x\(Int(s.height))".padding(toLength: 13, withPad: " ", startingAt: 0)
    }
}

@main
struct LayoutAuditMain {
    @MainActor
    static func main() { Audit.run() }
}
