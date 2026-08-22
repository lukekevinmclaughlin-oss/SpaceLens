import Foundation
import SwiftUI

@MainActor
final class ScanViewModel: ObservableObject {

    enum ScanState: Equatable {
        case idle
        case scanning(files: Int, bytes: Int64)
        case complete(duration: TimeInterval)
        case failed(String)
    }

    enum ChartMode: String, CaseIterable {
        case sunburst = "Sunburst"
        case treemap  = "Treemap"
    }

    // Scan
    @Published var state: ScanState = .idle
    @Published var root: FileNode?
    @Published var current: FileNode?          // node currently drilled into
    @Published var breadcrumb: [FileNode] = []
    @Published var scannedURL: URL?

    // Volume context (used/free on the scanned volume) — the low-disk payoff.
    @Published var volumeTotal: Int64 = 0
    @Published var volumeFree: Int64 = 0

    // UI
    @Published var section: SidebarSection = .explore
    @Published var chartMode: ChartMode = .sunburst
    @Published var colorByType = false         // colour chart by file category vs name
    @Published var hovered: FileNode?          // transient, drives chart highlight + tooltip
    @Published var selected: FileNode?         // sticky, drives the inspector

    // Undo of the most recent cleanup.
    @Published private(set) var lastTrash: [PlatformActions.TrashedItem] = []

    // Finder result cache — keyed by section+epoch+settings so switching tabs
    // (especially back to Duplicates) doesn't re-hash. Invalidated on any change
    // to the tree via `bumpFinders()`.
    enum FinderResult {
        case files([FileNode])
        case junk([SmartFinders.JunkHit])
        case dups([SmartFinders.DuplicateGroup])
    }
    private(set) var finderEpoch = 0
    var finderCache: [String: FinderResult] = [:]
    func bumpFinders() { finderEpoch += 1; finderCache.removeAll() }

    /// Free space we'd have after emptying the current basket — the payoff number.
    var projectedFree: Int64 { volumeFree + basketTotal }

    /// The node the inspector should describe: the sticky selection, else the
    /// folder currently being explored. Hover no longer hijacks the inspector.
    var inspected: FileNode? { selected ?? current }
    var canGoUp: Bool { breadcrumb.count > 1 }

    // Basket
    @Published private(set) var basket: [FileNode] = []
    private var basketIDs = Set<UUID>()

    var basketTotal: Int64 {
        basket.reduce(0) { $0 + ($1.allocatedSize > 0 ? $1.allocatedSize : $1.size) }
    }
    var basketLogicalTotal: Int64 { basket.reduce(0) { $0 + $1.size } }

    private var scanner: DiskScanner?
    private var scanStart: Date = .init()

    // MARK: - Scanning

    func startScan(url: URL) {
        // Persist access on macOS via security-scoped bookmark where relevant.
        let accessing = url.startAccessingSecurityScopedResource()
        scannedURL = url
        state = .scanning(files: 0, bytes: 0)
        root = nil
        current = nil
        breadcrumb = []
        selected = nil
        scanStart = Date()

        let scanner = DiskScanner()
        self.scanner = scanner

        Task.detached(priority: .userInitiated) { [weak self] in
            let node = scanner.scan(url: url) { progress in
                Task { @MainActor in
                    guard let self else { return }
                    if case .scanning = self.state {
                        self.state = .scanning(files: progress.filesScanned, bytes: progress.bytesScanned)
                    }
                }
            }
            let vals = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
            await MainActor.run {
                guard let self else { if accessing { url.stopAccessingSecurityScopedResource() }; return }
                if let node {
                    self.root = node
                    self.current = node
                    self.breadcrumb = [node]
                    self.volumeTotal = Int64(vals?.volumeTotalCapacity ?? 0)
                    self.volumeFree = Int64(vals?.volumeAvailableCapacityForImportantUsage ?? Int64(vals?.volumeAvailableCapacity ?? 0))
                    self.lastTrash = []
                    self.bumpFinders()
                    RecentScans.shared.record(url: url, size: node.size, at: Date())
                    self.state = .complete(duration: Date().timeIntervalSince(self.scanStart))
                } else {
                    self.state = .failed("Scan was cancelled or the location could not be read.")
                }
            }
        }
    }

    func cancelScan() {
        scanner?.cancel()
    }

    func rescan() {
        guard let url = scannedURL else { return }
        startScan(url: url)
    }

    /// Tear down the current scan and return to the launch screen.
    func newScan() {
        scanner?.cancel()
        clearBasket()
        root = nil
        current = nil
        breadcrumb = []
        selected = nil
        hovered = nil
        scannedURL = nil
        state = .idle
    }

    // MARK: - Navigation

    func drill(into node: FileNode) {
        guard node.isDirectory, !(node.children?.isEmpty ?? true) else { return }
        current = node
        // rebuild breadcrumb from root to node
        var path: [FileNode] = []
        var n: FileNode? = node
        while let cur = n { path.append(cur); n = cur.parent }
        breadcrumb = path.reversed()
        selected = nil
    }

    func navigateTo(breadcrumbIndex index: Int) {
        guard breadcrumb.indices.contains(index) else { return }
        let node = breadcrumb[index]
        current = node
        breadcrumb = Array(breadcrumb.prefix(index + 1))
        selected = nil
    }

    func goUp() {
        guard breadcrumb.count > 1 else { return }
        navigateTo(breadcrumbIndex: breadcrumb.count - 2)
    }

    /// A click on a node: drill into folders, pin-select files.
    func activate(_ node: FileNode) {
        if node.isDirectory && !(node.children?.isEmpty ?? true) {
            drill(into: node)
        } else {
            selected = node
        }
    }

    func select(_ node: FileNode) { selected = node }

    /// Move the selection across the current ring (children of `current`).
    func selectSibling(offset: Int) {
        let sibs = (current?.sortedChildren ?? []).filter { $0.size > 0 }
        guard !sibs.isEmpty else { return }
        if let sel = selected, let idx = sibs.firstIndex(where: { $0.id == sel.id }) {
            selected = sibs[((idx + offset) % sibs.count + sibs.count) % sibs.count]
        } else {
            selected = offset >= 0 ? sibs.first : sibs.last
        }
    }

    /// Drill into the selected folder (keyboard Return).
    func drillIntoSelected() {
        if let s = selected, s.isDirectory, !(s.children?.isEmpty ?? true) { drill(into: s) }
    }

    /// Find files/folders anywhere in the scanned tree whose name matches, biggest
    /// first. Powers the header's global "find a file" search.
    func searchTree(_ query: String, limit: Int = 40) -> [FileNode] {
        guard let root, query.count >= 2 else { return [] }
        var out: [FileNode] = []
        func walk(_ n: FileNode) {
            if n !== root && n.name.localizedCaseInsensitiveContains(query) { out.append(n) }
            for c in n.children ?? [] { walk(c) }
        }
        walk(root)
        return Array(out.sorted { $0.size > $1.size }.prefix(limit))
    }

    /// Jump the Explore chart to a node found via a finder: drill into its parent
    /// so the node is on screen, then select it.
    func showInChart(_ node: FileNode) {
        section = .explore
        if let parent = node.parent { drill(into: parent) }
        selected = node
        hovered = nil
    }

    // Command / shortcut targets (operate on the sticky selection).
    func revealSelected()    { if let n = inspected { PlatformActions.revealInFinder(n) } }
    func quickLookSelected() { if let n = inspected { PlatformActions.quickLook(n) } }
    func toggleSelectedInBasket() { if let n = inspected { toggleBasket(n) } }

    // MARK: - Basket

    func isInBasket(_ node: FileNode) -> Bool { basketIDs.contains(node.id) }

    func toggleBasket(_ node: FileNode) {
        if basketIDs.contains(node.id) { removeFromBasket(node) }
        else { addToBasket(node) }
    }

    func addToBasket(_ node: FileNode) {
        guard !basketIDs.contains(node.id) else { return }
        basketIDs.insert(node.id)
        basket.append(node)
    }

    func removeFromBasket(_ node: FileNode) {
        basketIDs.remove(node.id)
        basket.removeAll { $0.id == node.id }
    }

    func clearBasket() {
        basket.removeAll()
        basketIDs.removeAll()
    }

    /// Move everything in the basket to Trash, then prune the deleted nodes from
    /// the tree and re-aggregate sizes so the chart updates live.
    @discardableResult
    func emptyBasketToTrash() -> (trashed: Int, bytes: Int64) {
        let result = PlatformActions.moveToTrash(basket)
        let deletedIDs = Set(result.items.map { $0.node.id })
        for item in result.items { detach(item.node) }
        if let s = selected, deletedIDs.contains(s.id) { selected = nil }
        if let h = hovered, deletedIDs.contains(h.id) { hovered = nil }
        lastTrash = result.items
        volumeFree += result.bytes              // reflect reclaimed space at once
        clearBasket()
        reaggregate(from: root)
        bumpFinders()
        objectWillChange.send()
        return (result.trashed, result.bytes)
    }

    /// Undo the most recent cleanup: restore files from Trash and re-attach nodes.
    @discardableResult
    func undoLastTrash() -> Int {
        guard !lastTrash.isEmpty else { return 0 }
        let restored = PlatformActions.restore(lastTrash)
        var bytesBack: Int64 = 0
        for item in lastTrash {
            reattach(item.node)
            bytesBack += item.node.allocatedSize > 0 ? item.node.allocatedSize : item.node.size
        }
        volumeFree = max(0, volumeFree - bytesBack)
        lastTrash = []
        reaggregate(from: root)
        bumpFinders()
        objectWillChange.send()
        return restored
    }

    // MARK: - Tree mutation after delete

    private func detach(_ node: FileNode) {
        guard let parent = node.parent else { return }
        parent.children?.removeAll { $0.id == node.id }
    }

    private func reattach(_ node: FileNode) {
        guard let parent = node.parent else { return }
        if parent.children == nil { parent.children = [] }
        if !(parent.children?.contains { $0.id == node.id } ?? false) {
            parent.children?.append(node)
        }
    }

    private func reaggregate(from node: FileNode?) {
        guard let node, node.isDirectory else { return }
        var size: Int64 = 0, alloc: Int64 = 0, count = 0
        for c in node.children ?? [] {
            if c.isDirectory { reaggregate(from: c) }
            size += c.size; alloc += c.allocatedSize; count += c.fileCount
        }
        node.size = size; node.allocatedSize = alloc; node.fileCount = count
    }
}
