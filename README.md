# SpaceLens

**See what's eating your Mac's storage in seconds, then reclaim it with one click.**

A modern disk visualiser + cleaner for macOS, iPadOS and iOS. Native SwiftUI,
built from scratch. The wedge against DaisyDisk / GrandPerspective is speed +
a modern, animated UI + a cleanup-basket workflow.

## Build

```bash
xcodegen generate
open SpaceLens.xcodeproj
```

Universal target (`supportedDestinations: [macOS, iOS]`), so one scheme builds
the Mac app, the iPad app and the iPhone app.

```bash
# macOS
xcodebuild -scheme SpaceLens -destination 'platform=macOS' build
# iOS
xcodebuild -scheme SpaceLens -destination 'generic/platform=iOS Simulator' build
```

## Architecture

| Piece | File | Notes |
|-------|------|-------|
| Scanner engine | `Sources/Scanner/DiskScanner.swift` | `getattrlistbulk` bulk enumeration — hundreds of entries per syscall. Top-level subtrees walked concurrently. Measured ~166k files/sec. |
| Concurrency-safe counters | `Sources/Scanner/Atomics.swift` | `os_unfair_lock`-guarded flag / counter / inode set. |
| Tree model | `Sources/Models/FileNode.swift` | Reference-type node; aggregates size, alloc size, file count, inode. |
| Finders | `Sources/Finders/SmartFinders.swift` | Largest, Old & Unopened, Dev Junk, and 3-stage Duplicates (size → partial hash → SHA-256). |
| Charts | `Sources/Views/SunburstView.swift`, `TreemapView.swift` | Canvas-rendered, interactive drill-down, hover, squarified treemap. |
| Cleanup basket | `Sources/ViewModels/ScanViewModel.swift`, `Views/BasketBar.swift` | Collect → running total → move to Trash (reversible), then live re-aggregate. |

### Accuracy wins
- **Symlinks are never followed or counted** (avoids loops + double counting).
- **Hard links & APFS clones counted once** — physical `allocsize` is deduped by
  inode (`fileID`), so the "space you'll reclaim" number is honest. Verified:
  1000 KB file + hard link → logical 2000 KB, physical 1000 KB.
- Logical vs physical (on-disk) size shown separately in the inspector.

## Two-build strategy (the core decision)

- **Mac App Store (sandboxed):** ship with `SpaceLens.entitlements`
  (`app-sandbox = true` + user-selected + app-scope bookmarks). User grants a
  folder via the open panel; access persists via a security-scoped bookmark.
  Scans the user's files. Price €8,99. Category: Utilities.
- **Direct-download "Pro" (notarized, non-sandboxed):** no sandbox entitlement;
  request Full Disk Access at runtime to scan the whole startup volume + system
  caches + dev junk. Price €14,99. Avoids Apple's cut.

The launch screen frames this honestly — "your files" (MAS) vs "everything" (Pro).

## Safety / App Review notes
- **Trash only, user-initiated.** Deletion uses `trashItem` (reversible). Never a
  hard delete. No scare-tactic "your Mac is at risk" alarms — a cleaner app gets
  rejected for those.
- Duplicate "Add all to basket" keeps the first copy and baskets the rest.

## Design — holographic HUD ("JARVIS")

The whole app is a dark holographic HUD, keyed to the app icon:

- **Icon** (`scripts/make_icon.py`): an arc-reactor core (triangle reticle +
  glowing bloom) inside concentric segmented scan rings, a data-node
  constellation with amber accents, and a radar sweep. Full-bleed for iOS,
  squircle for macOS, in `Resources/Assets.xcassets/AppIcon.appiconset`.
- **Liquid Glass** (`Sources/Views/LiquidGlass.swift`): uses the real system
  `.glassEffect` on macOS 26 / iOS 26, with a hand-built material+specular
  fallback on earlier OSes so panels look glassy everywhere. `LiquidGlass`
  modifier, `GlassButtonStyle`, `HolographicBackground`, and `HoloReticle`
  (the animated arc-reactor mark, reused as the scan indicator).
- **Motion**: `HolographicBackground` drifts cyan/amber light blooms over a HUD
  grid; the launch reticle rotates and pulses; the scan screen spins up a radar
  sweep with live `numericText`-morphing counters; sunburst/treemap arcs get a
  blurred cyan glow on hover; the basket's "You'll free X" pulses in amber.
- **Palette** (`Sources/Utilities/Theme.swift`): holographic cyan on deep navy,
  amber accents. The app forces `.dark` — the HUD look is its identity.

## Interaction model (v1.1 audit pass)

- **Sticky selection vs. hover**: the inspector is driven by a *pinned selection*
  (`model.inspected`), so it never flickers as you sweep the chart. Hover instead
  surfaces a cursor-following glass **tooltip** (`HoverTooltip`). Clicking a folder
  drills; clicking a file pins it (`model.activate`). Selected node gets an amber
  ring, hovered gets a cyan glow.
- **Memoized chart geometry**: sunburst arcs and treemap tiles are rebuilt only
  when the node or size changes (`onChange(of: key)`), not on every hover — so
  deep trees stay smooth. Sunburst also labels large/shallow arcs in place.
- **Navigation**: header **Back** button + breadcrumb; `⌘↑` go up; `⌘R` rescan;
  `⌘N` new scan. The **Selection** menu adds `⌘D` add/remove basket, `⌘Y` Quick
  Look, `⇧⌘R` reveal — all acting on the pinned selection.
- **Right-click context menus** everywhere (charts + finder rows): add/remove
  basket, open/show in chart, reveal, Quick Look, open.
- **Disk-capacity bar** (`CapacityBar`) in the sidebar: real used/free on the
  scanned volume with this scan highlighted — the low-disk emotional payoff.
- **Finders**: live search/filter field, branded `HoloReticle` spinner, and the
  duplicate hasher is cancellable (`isCancelled` closure + `ManagedAtomicFlag`).
- **Glass `ChartToggle`** replaces the stock segmented control.

## Features added in the round-2 pass

- **Recent scans** (`RecentScans`) — the launch screen remembers recent locations
  (security-scoped bookmarks) for one-click rescans across launches.
- **File-type breakdown** (`FileCategory`, `CategoryBreakdownView`) — space by
  category with a stacked bar + legend in the inspector, plus a **Colour by type**
  chart mode. Directories take the colour of their **dominant** descendant
  category (`FileNode.dominantCategory`, computed bottom-up post-scan).
- **Undo cleanup** — `moveToTrash` captures each item's `resultingItemURL`; the
  basket bar + `⌘Z` restore files from Trash and re-attach them to the tree.
- **Projected free space** — the basket shows `free → free-after` on the volume.
- **Settings** (`⌘,`, `AppSettings`) — configurable old-file age, duplicate
  min-size, and dev-junk toggle; finders read them live.
- **Finder search + sort** (size / name / date) and a **result cache** so
  switching tabs (esp. Duplicates) doesn't re-hash.
- **Animated chart reveal** (fade + scale) on scan and drill.

### Bugs fixed while auditing
- **Glass buttons only tapped on their text/icon** — `.glassEffect(.regular,…)`
  without a tint left `Spacer()` gaps non-hittable; `LiquidGlass` now applies
  `.contentShape(shape)` so the whole row forwards taps. (Fixed Recent + quick
  location buttons.)
- **Charts memoized via a reference cache in `body`** instead of
  `onChange(of:key,initial:true)`, which could latch onto a transient size and
  leave the chart empty. Cache key now includes the tree epoch so the chart
  refreshes after a Trash/undo.
- Animating a Canvas's *internals* from `@State` is unreliable — entrance
  animation now drives the container's opacity/scale, not the draw closure.

## Features added in the round-3 pass

- **Menu-bar storage watcher** (`DiskMonitor` + `MenuBarView` + `MenuBarExtra`):
  a live per-volume capacity dashboard in the menu bar with a low-space nudge and
  quick "Scan Home / Open / Settings" actions. Toggle + threshold in Settings.
- **Chart keyboard navigation** (macOS): arrows move the selection across the
  current ring, Return opens a folder, Escape goes up, Space Quick Looks, Delete
  baskets — all via `.focusable().onKeyPress`.
- **Sunburst hover focus**: hovering a wedge highlights its whole lineage
  (ancestors + descendants) and dims the rest.
- **Global file search** (`⌘F`): a header popover that finds any file/folder by
  name across the whole scan and jumps the chart to it.
- **Accessibility**: VoiceOver labels + hints on the chart, finder rows, and the
  capacity bar.

### Scanner optimizations (re-verified vs `du` and `find`)
- Sharded 16-way inode set (power-of-two mask, not modulo) to cut lock contention.
- One combined files+bytes counter (single lock per file instead of two).
- A reusable per-worker `getattrlistbulk` buffer instead of allocating one per
  directory. Result: **~230k files/sec warm** (was ~166k), correctness unchanged.

### Regression fixed
- A StoreKit **paywall** (`PurchaseManager` / `PaywallView`) was added in a
  separate pass. Its view-swap left `LaunchView`'s `onAppear`-driven reveal flag
  unfired, rendering the launch screen **blank**. Fixed by making the launch
  content visible by default — never gate visibility on a lifecycle callback.
  (DEBUG bypass for testing: `SPACELENS_DEMO=1` env, or
  `defaults write com.lukemclaughlin.spacelens debug.forcePurchased -bool YES`.)
