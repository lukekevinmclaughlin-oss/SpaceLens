import Foundation

/// A node in the scanned file tree. Reference type so subtrees can be shared,
/// mutated during the scan, and referenced from finders/basket without copying.
final class FileNode: Identifiable, @unchecked Sendable {
    let id = UUID()
    let name: String
    let url: URL
    let isDirectory: Bool

    /// Logical size in bytes (for files). For directories this is the aggregated
    /// size of all descendants, computed after the scan.
    var size: Int64

    /// Physical bytes on disk (allocation size). Used for accurate "space you'll
    /// reclaim" numbers and hard-link / APFS-clone dedup.
    var allocatedSize: Int64

    /// APFS/HFS file identifier (inode). Used to detect hard links and clones so
    /// the same physical blocks are not double-counted.
    let fileID: UInt64

    var modificationDate: Date?
    var accessDate: Date?

    /// The file category that occupies the most bytes under this node (for a file
    /// it is its own category). Powers the "colour by type" chart mode. Computed
    /// once after the scan.
    var dominantCategory: FileCategory = .other

    /// Immediate children (directories only). nil for files.
    var children: [FileNode]?

    /// Number of files contained (self + descendants).
    var fileCount: Int

    weak var parent: FileNode?

    init(name: String,
         url: URL,
         isDirectory: Bool,
         size: Int64,
         allocatedSize: Int64,
         fileID: UInt64,
         modificationDate: Date?,
         accessDate: Date?) {
        self.name = name
        self.url = url
        self.isDirectory = isDirectory
        self.size = size
        self.allocatedSize = allocatedSize
        self.fileID = fileID
        self.modificationDate = modificationDate
        self.accessDate = accessDate
        self.fileCount = isDirectory ? 0 : 1
    }

    /// Children sorted largest-first, for stable visualisation ordering.
    var sortedChildren: [FileNode] {
        (children ?? []).sorted { $0.size > $1.size }
    }

    /// Fraction of the parent's size this node occupies (0...1).
    func fraction(of total: Int64) -> Double {
        guard total > 0 else { return 0 }
        return Double(size) / Double(total)
    }

    var isLeaf: Bool { children?.isEmpty ?? true }

    /// Depth-first flatten of every file leaf under this node.
    func flattenedFiles(into out: inout [FileNode]) {
        if isDirectory {
            for c in children ?? [] { c.flattenedFiles(into: &out) }
        } else {
            out.append(self)
        }
    }
}
