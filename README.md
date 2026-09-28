# Component Tracker

A minimalistic black desktop app for tracking your electronics components — built as a
native macOS app (Swift + SwiftUI), no Xcode required.

```
Open it from Launchpad or Spotlight, or:   /Applications/ComponentTracker.app
```

This is the **only** installed copy. There is no Desktop duplicate on purpose — two
bundles of the same app invite accidental double-launch, and the app hands off to an
already-running instance anyway if you try.

---

## What it does

| | |
|---|---|
| **Add / Edit / Delete** | Full editor for every field, or right-click a card for quick actions |
| **Rapid entry** | ⌘N opens a blank editor with the cursor already in the part-number field. **⌘↩** adds and closes, **⌘⇧↩** adds and opens the next blank one — a run of parts keyed without touching the mouse |
| **Duplicate warning** | Typing a part number that already exists says so inline, with a one-click jump to that record instead |
| **Take Out** | Deduct parts from stock with a dedicated sheet (quick amounts 1/5/10/25/all), warns when it drops to or below the minimum, and records what it was used for |
| **Put Back** | `+` on any row returns a unit to stock |
| **Usage History** | Every take-out and put-back is logged as it happens — date, quantity, project, stock left. Per-project totals, an "all entries" log, and a per-part summary inside the editor |
| **Undo / Redo** | ⌘Z and ⇧⌘Z, labelled with the action — "Undo Take 4 × HC-SR04". Covers stock *and* the usage log together |
| **Duplicate** | Right-click ▸ Duplicate to clone a part |
| **Search** | Instant filtering across part number, name, value, footprint, location, supplier, project and notes. Multiple words are ANDed |
| **Filters** | Dashboard, All, Low Stock, Out of Stock, Usage History, plus per-category filtering from the sidebar |
| **Two layouts** | Dense sortable table, or a card grid — toggle in the top-right |
| **Dashboard** | Totals, inventory value, low/out-of-stock counts, a units-by-category chart, and a "needs reordering" list |
| **Export / Import** | CSV (opens in Excel/Numbers), a separate usage-log CSV, and JSON (lossless backup including the log). Import can merge (sums quantities) or replace |
| **Raspberry Pi backup** | Optional one-tap snapshot of your inventory to your Pi over SSH |
| **Search + filters + export** | All fully offline; no account, no network required |

### Tracked fields

- **Identity** — part number, name, category (23 types), manufacturer
- **Stock** — quantity, minimum (alert threshold), location / bin
- **Electrical** — value, package/footprint, tolerance, voltage rating, datasheet URL
- **Procurement** — supplier, order number, unit cost, date ordered, date received, project
- **Notes**

Low-stock logic: a part is **low** when quantity ≤ minimum (and minimum > 0), and
**out** when quantity is 0. The sidebar and dashboard badge both reflect this.

### Currency

Everything is in **Indian Rupees (₹ / INR)**, with Indian digit grouping — the last
three digits grouped, then pairs, so 1234567 reads **₹12,34,567.00**, not ₹1,234,567.

| | |
|---|---|
| Card, editor | `₹1,23,456.78` — full precision, always 2 decimals |
| Table, dashboard | Compact: `₹999.00` · `₹12.3K` · `₹1.2L` · `₹1.2Cr` (lakh/crore) |
| CSV export | Bare numbers, no symbol — so Excel/Numbers can still sort and total them |

No currency symbol is hardcoded anywhere except `Money` in `Design.swift`. Change
`Money.code` / `Money.symbol` there to switch currency and the whole app follows.

> Amounts are stored as plain numbers and are **not** converted — the app just labels
> them. Anything you enter is taken to be rupees.

---

## Where your data lives

```
~/Library/Application Support/ComponentTracker/inventory.json
```

Plain, human-readable JSON. Every change is written automatically (debounced ~0.35 s),
on ⌘S, and again when the app quits.

A copy also lives **inside this project** at `Data/inventory.json`, so the folder is
self-contained — code, docs and data in one place. Keep it in sync with:

```bash
./backup.sh            # live data  ->  Data/inventory.json
./backup.sh restore    # Data/inventory.json  ->  live data (on another Mac)
```

> **What is and isn't in git.** Your inventory is personal data — real quantities,
> suppliers, prices, even a device serial number in one row. It is git-excluded
> (see `.gitignore`), so it never leaves this machine. The repository ships
> `Data/inventory.json.example` instead — a no-data sample generated from the app's
> own seed components, so a fresh checkout always has something documented to load.

If the file is ever unreadable, the app **moves it aside** as
`inventory-corrupt-<timestamp>.json` and starts clean rather than losing your data.
`./backup.sh` refuses to overwrite a good backup with a corrupt one.

Reveal the file anytime from **Settings ▸ Data ▸ Reveal in Finder**.

---

## Raspberry Pi backup

Local-first: the app is fully functional with no network. The Pi integration only
copies a snapshot for redundancy.

Your Pi: set it in **Settings ▸ Raspberry Pi backup** — host, SSH port, user and remote
folder are all editable and remembered. The defaults are neutral placeholders
(`pi.local`/`22`); the repository ships no machine-specific address or username.

**Settings ▸ Raspberry Pi backup** → enable **Pi sync** → **Test Connection** → **Back Up Now**.

Each backup writes `~/component-tracker/inventory-YYYY-MM-DD-HHMMSS.json` and updates an
`inventory-latest.json` symlink. Host, port, user, remote folder and retention are all
editable and remembered. The toolbar button and **⌘B** both do it.

> Uses `ssh` with `BatchMode=yes`, so the app never hangs waiting for a password prompt.
> It needs your SSH key to already be set up for the Pi.

### A push is verified, not assumed

The old version printed "Backed up to …" as soon as the shell script reached its final
`echo` — which proves nothing about the file. A WiFi hiccup that truncated the upload
still reported success. **A backup you can't verify is a rumour.**

Now the app hashes the payload with SHA-256, hands the expected hash to the Pi, and the
Pi hashes what it *actually received*. The file is only `mv`'d into place, and the
`inventory-latest.json` symlink only updated, if they match. Otherwise you get a distinct
red **checksum mismatch** (not a generic network error) and nothing is published.

| | |
|---|---|
| Reported on success | byte count + the first 12 hex of the hash |
| On mismatch | red warning, no file published, temp file removed |
| **Keep last N backups** | prunes old snapshots *as part of the same push*, so the button stays the only action while the Pi never fills. `0` = keep everything |
| Timeout | 90 s overall, so a Pi that answers then wedges can never leave the UI stuck on "Working…" |

Remote paths are POSIX-quoted (`ShellQuote.path`), with a leading `~` deliberately left
unquoted so it still expands — a folder named `my tracker` used to break the script.

The Pi is a **backup target only**. A push never reads, restores or overwrites anything
already there; it only adds a new timestamped file. Your Mac is always authoritative.

### Testing it

```bash
./pisync-test.sh    # drives the real controller against the real Pi
```

Builds the actual `PiSyncController`, pushes, and asserts the bytes on the Pi are
byte-identical, no temp files remain, the symlink is correct, and back-to-back pushes
don't collide. Needs the Pi reachable — it's an integration test. Point it at your Pi with
the environment: `PI_TEST_HOST` / `PI_TEST_PORT` / `PI_TEST_USER` (defaults `pi.local`,
`22`, user `pi`). `./test.sh` covers the pure logic (including the shell quoting) with no
network and no environment.

---

## Usage log

Every take-out and put-back writes an entry the moment it happens, with the date,
quantity, project, and how much stock was left afterwards. **Usage History** in the
sidebar is that log.

Entries live at the **top level** of the document, not inside a component:

```json
{
  "components": [ … ],
  "consumed": [
    {
      "id": "…", "componentID": "…",
      "partNumber": "HC-SR04", "name": "Ultrasonic distance sensor",
      "quantity": 2, "date": "2026-09-27T14:32:11Z",
      "project": "Line Follower", "resultingStock": 2,
      "kind": "used"
    }
  ],
  "version": 2
}
```

Three decisions worth knowing about:

| | |
|---|---|
| **Entries outlive their component** | A log entry is a historical fact, so deleting a part does not delete what you recorded about it. Such rows are marked *deleted* and their jump link is disabled. The part number and name are copied into the entry for the same reason — a later rename must not rewrite history. |
| **Returns are logged too** | `kind` is `used` or `returned`, so a put-back cancels a take-out instead of the log claiming parts were consumed when they are back on the shelf. Per-project figures show used and returned separately, because a project that returned more than it took would otherwise have a negative bar. |
| **Old files still load** | `consumed` is absent from every file written before this version. Swift's *synthesised* decoder treats a missing key as fatal even when the property has a default, which would have made the store declare a perfectly good file corrupt, move it aside and start from empty. `Inventory` therefore has a hand-written `init(from:)` using `decodeIfPresent(…) ?? []`. There is a test that loads a real v1 file. |

The `+`/`−` buttons in the list route through take-out and put-back rather than
adjusting the number directly, so a correction made there stays consistent with the log.
Clear it from **Usage History ▸ Clear**; undo puts it back.

---

## Undo / redo

⌘Z and ⇧⌘Z, in the Edit menu, labelled with the action they will reverse.

```
Undo Take 4 × HC-SR04        ⌘Z
Redo Take 4 × HC-SR04        ⇧⌘Z
```

Implemented as a **40-deep stack of snapshots** (components + log) rather than inverse
commands. Every mutation here changes two things at once — a take-out moves stock *and*
appends a log entry — and keeping a correctly paired inverse for each is far more code
than copying two small arrays. A take-out that wrongly un-does the stock but not the log
would be worse than no undo at all.

- **Rapid clicks coalesce.** Holding the row `+`/`−` is one gesture, keyed per part, so
  it collapses into a single undo step. Two deliberate *Take Out* sheet submissions never
  coalesce, however quickly they follow each other — that would make the first ⌘Z appear
  to swallow the first action.
- **Imports are one step.** Merging or replacing 40 rows is "Undo Merge 40 components",
  not 40 steps.
- **Any new edit drops the redo branch**, or redo could replay a history you already
  stepped away from.
- **The stack is per-session.** It starts empty at launch and is not written to disk; a
  restart is a clean slate.
- **"Delete Everything" is now reversible.** ⌘Z brings the whole inventory back.

---

## Project layout

```
ComponentTracker/
├── build.sh            # compile → bundle → icon → codesign
├── install.sh          # install to /Applications (single location)
├── clean.sh            # delete build/ and any stray copies → source-only
├── backup.sh           # save / restore inventory between live data and Data/
├── test.sh             # 198 headless logic checks
├── pisync-test.sh      # end-to-end Pi push against the real Pi
├── render.sh           # offscreen UI renders + pixel census
├── make-icon.sh        # draws the app icon into Assets/
├── Sources/
│   ├── Model.swift         Component, categories, ConsumptionEntry, on-disk Inventory
│   ├── Store.swift         state, JSON persistence, search/sort/filter, CRUD, undo, seed data
│   ├── ExportService.swift CSV/JSON serialise + parse, usage-log CSV
│   ├── PiSync.swift        SSH snapshot backup
│   ├── Design.swift        currency (INR), black palette, fonts, buttons, pills, tiles
│   ├── MainView.swift      app entry, window, toolbar, sheets, menu commands
│   ├── Sidebar.swift       navigation
│   ├── ComponentListViews.swift  table + card grid
│   ├── DashboardView.swift stats, chart, reorder list
│   ├── HistoryView.swift   the usage log: tiles, per-project bars, entry list
│   ├── EditorSheet.swift   add/edit + take-out
│   ├── SettingsSheets.swift settings, export/import
│   └── UIState.swift       view state holders
├── Tests/              headless tests + render harness
├── Tools/IconGen.swift icon generator
├── Assets/AppIcon.icns app icon
├── Data/inventory.json your inventory (copy, via ./backup.sh)
└── build/                disposable output — safe to delete, ./clean.sh does it
```

### Rebuilding

```bash
./build.sh      # → build/ComponentTracker.app
./install.sh    # → /Applications/ComponentTracker.app   (only install location)
./clean.sh      # → back to source-only, deletes build/
./backup.sh     # → Data/inventory.json
./test.sh       # 198 logic checks
./render.sh     # → build/renders/*.png
```

`INSTALL_PREFIX=~/Applications ./install.sh` installs per-user instead.

---

## Notes on this machine's toolchain

Full Xcode is not installed, only Command Line Tools (Swift 6.4, macOS 27 SDK).
Two consequences are already handled in the code:

1. **No SwiftData.** The CLT toolchain ships `libSwiftMacros` and `libObservationMacros`
   but **not** `libSwiftDataMacros`, so `@Model`/`@Query` cannot compile. Storage is a
   hand-rolled JSON layer instead — which also means your data stays readable and
   hand-editable.
2. **No `@State`.** In the macOS 27 SDK, `State` is declared as both a struct *and* a
   macro, and the macro shadows the struct. That macro lives in `SwiftUIMacros`, which
   is likewise absent, so `@State` fails to expand. All view-local state therefore lives
   in small `ObservableObject` holders used via `@StateObject` (see `UIState.swift`),
   which are ordinary property wrappers and work fine.

Both are documented in-code. If you later install full Xcode, neither workaround is
load-bearing — the app builds and runs identically.

The app is ad-hoc signed, so macOS Gatekeeper may ask you to confirm the first launch
(right-click ▸ **Open** if it does). It is a local, offline, self-built binary with no
network or privileged access.

> Changes since the app was first installed: the bundle identifier is now
> `com.componenttracker.ComponentTracker` (it used to embed a username). Reinstall with
> `./build.sh && ./install.sh` — this resets remembered *settings* (UserDefaults are keyed
> by bundle ID), so re-enter your Pi-sync settings once. Your inventory data file is
> untouched.

---

## Verification performed

- **198/198 headless logic checks** (`./test.sh`) — persistence, JSON round-trip, search
  (incl. multi-term), filters, sorting, take-out clamping, put-back, duplicate, delete,
  CSV round-trip with embedded commas/quotes/newlines, merge-by-part-number, corrupt-file
  recovery, INR grouping, shell quoting, and:
  - **usage log** — entry contents, denormalised part data, newest-first ordering,
    clamped amounts logged as the *real* amount, no entry for a no-op, per-project
    used/returned split, log surviving component deletion and an app restart.
  - **backward compatibility** — a real version-1 `inventory.json` (no `consumed` key)
    loads without error, is not parked as corrupt, and survives a save cycle.
  - **undo/redo** — add/edit/delete/take-out/put-back/import/clear all reversible,
    labels correct, log entries rewound and replayed with their stock, click-spam
    coalescing, deliberate actions *not* coalescing, redo branch invalidated correctly.
- **13/13 Pi end-to-end checks** (`./pisync-test.sh`) — byte-identical remote copy, the
  remote file really contains the `consumed` key and the log entries and project names
  (a matching hash alone would not prove the payload was complete), no temp files left,
  symlink correct, back-to-back pushes don't collide.
- **Offscreen UI renders** (`./render.sh`) — sidebar, cards, editor, take-out, settings,
  export and four usage-history states all rasterise with the expected dark palette and
  non-zero text/accent pixels.
- **Live app** — launches, stays idle at 0 % CPU, loads a version-1 `inventory.json`
  without treating it as corrupt, and exposes the new commands in the menu bar
  (File ▸ New Component / Save Now / Back Up to Pi; Edit ▸ Undo / Redo, correctly
  disabled until something has been edited).

### Known limits of the current setup

`Table` and `Chart` are backed by AppKit view classes that `ImageRenderer` cannot
rasterise without a window host, so those two are exercised by the live app rather than
the render harness. `ScrollView`-rooted views also rasterise empty offline; render
`9-probe-scrollview` exists in the harness to demonstrate that this is a harness limit
rather than a layout bug. `HistoryView` therefore has a `scrollable` flag used only by
the harness, so it can be checked like everything else.

**Screenshots of the running app are not possible from an agent shell.** Screen Recording
is not granted, and — separately — an app launched from a shell never gets its window
ordered on screen: a twelve-line bare SwiftUI app behaves identically (`onscreen=false`
in the window list), while a window belongs to a terminal launched from your login
session. To look at the UI, launch **/Applications/ComponentTracker.app** yourself by
double-clicking it.
