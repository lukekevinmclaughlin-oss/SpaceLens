import Foundation
import SwiftUI
#if os(macOS)
import AppKit
import Quartz
#endif

/// Cross-platform wrappers for the OS integrations the app needs. On macOS these
/// are the real Finder / Quick Look / Trash actions; on iOS they degrade to what
/// the sandbox permits (Trash → move item, Reveal → share sheet upstream).
enum PlatformActions {

    /// A record of one trashed item, enough to restore it (undo).
    struct TrashedItem {
        let node: FileNode
        let original: URL
        let trashed: URL?
    }

    /// Move items to the Trash (reversible — never a hard delete). Returns the
    /// count, bytes reclaimed, and per-item records so the move can be undone.
    static func moveToTrash(_ nodes: [FileNode]) -> (trashed: Int, bytes: Int64, items: [TrashedItem]) {
        var bytes: Int64 = 0
        var items: [TrashedItem] = []
        for node in nodes {
            do {
                var resulting: NSURL?
                try FileManager.default.trashItem(at: node.url, resultingItemURL: &resulting)
                items.append(TrashedItem(node: node, original: node.url, trashed: resulting as URL?))
                bytes += node.allocatedSize > 0 ? node.allocatedSize : node.size
            } catch {
                #if os(macOS)
                NSLog("SpaceLens: could not trash \(node.url.path): \(error.localizedDescription)")
                #endif
            }
        }
        return (items.count, bytes, items)
    }

    /// Restore previously trashed items to their original locations (undo).
    @discardableResult
    static func restore(_ items: [TrashedItem]) -> Int {
        var restored = 0
        for item in items {
            guard let trashed = item.trashed else { continue }
            do {
                try FileManager.default.moveItem(at: trashed, to: item.original)
                restored += 1
            } catch {
                #if os(macOS)
                NSLog("SpaceLens: could not restore \(item.original.path): \(error.localizedDescription)")
                #endif
            }
        }
        return restored
    }

    static func revealInFinder(_ node: FileNode) {
        #if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting([node.url])
        #endif
    }

    static func quickLook(_ node: FileNode) {
        #if os(macOS)
        let panel = QLPreviewPanel.shared()
        QuickLookCoordinator.shared.url = node.url
        panel?.dataSource = QuickLookCoordinator.shared
        panel?.makeKeyAndOrderFront(nil)
        #endif
    }

    static func open(_ node: FileNode) {
        #if os(macOS)
        NSWorkspace.shared.open(node.url)
        #endif
    }
}

#if os(macOS)
final class QuickLookCoordinator: NSObject, QLPreviewPanelDataSource {
    static let shared = QuickLookCoordinator()
    var url: URL?
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { url == nil ? 0 : 1 }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        url as NSURL?
    }
}
#endif
