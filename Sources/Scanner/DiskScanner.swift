import Foundation

/// High-throughput directory scanner built on `getattrlistbulk` — the same
/// low-level bulk-enumeration primitive fast scanners use to read hundreds of
/// entries per syscall instead of one `stat` per file.
///
/// The scanner builds an in-memory `FileNode` tree. Immediate children of the
/// scan root are walked concurrently (one worker per top-level subtree); deeper
/// levels are walked serially inside each worker, which gives strong parallelism
/// on real home folders without any risk of thread-pool deadlock.
final class DiskScanner: @unchecked Sendable {

    struct Progress {
        var filesScanned: Int
        var bytesScanned: Int64
        var currentPath: String
    }

    private let cancelled = ManagedAtomicFlag()
    private let progressCounter = ManagedAtomicCounter()   // files + bytes, one lock

    /// Tracks inodes already counted so hard links and APFS clones that point at
    /// the same physical blocks are not added to the reclaimable total twice.
    private let seenInodes = InodeSet()

    private var progressCallback: ((Progress) -> Void)?
    private var lastProgressReport: Int = 0

    func cancel() { cancelled.set() }

    /// Scan `url` and return the root node, or nil if cancelled / inaccessible.
    func scan(url: URL, progress: @escaping (Progress) -> Void) -> FileNode? {
        cancelled.clear()
        progressCounter.reset()
        lastProgressReport = 0
        seenInodes.reset()
        progressCallback = progress

        guard let root = makeNode(for: url, isDirectoryHint: true) else { return nil }
        guard root.isDirectory else { return root }

        // One reusable getattrlistbulk buffer for this thread's serial recursion;
        // concurrent top-level workers each allocate their own below.
        let bufSize = 256 * 1024
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufSize, alignment: 16)
        defer { buffer.deallocate() }
        scanDirectory(root, parallelTopLevel: true, buffer: buffer, bufSize: bufSize)
        if cancelled.isSet { return nil }
        _ = computeDominant(root)
        return root
    }

    /// Bottom-up pass assigning each node the file category that fills the most
    /// bytes beneath it. Returns the per-category byte totals for the subtree.
    @discardableResult
    private func computeDominant(_ node: FileNode) -> [FileCategory: Int64] {
        if !node.isDirectory {
            let cat = FileCategory.of(node.url.pathExtension)
            node.dominantCategory = cat
            return [cat: node.size]
        }
        var totals: [FileCategory: Int64] = [:]
        for child in node.children ?? [] {
            for (cat, bytes) in computeDominant(child) {
                totals[cat, default: 0] += bytes
            }
        }
        node.dominantCategory = totals.max { $0.value < $1.value }?.key ?? .other
        return totals
    }

    // MARK: - Directory walk

    private func scanDirectory(_ node: FileNode, parallelTopLevel: Bool,
                               buffer: UnsafeMutableRawPointer, bufSize: Int) {
        if cancelled.isSet { return }

        let path = node.url.path
        let dirfd = open(path, O_RDONLY)
        guard dirfd >= 0 else { node.children = []; return }
        defer { close(dirfd) }

        var children: [FileNode] = []

        // Attribute request: returned-attrs (always), name, object type,
        // mod/access times, file id (inode), logical size, physical size.
        var attrList = attrlist()
        attrList.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        attrList.commonattr = attrgroup_t(
            AttrConst.returnedAttrs | AttrConst.name | AttrConst.objType |
            AttrConst.modTime | AttrConst.accTime | AttrConst.fileID)
        attrList.fileattr = attrgroup_t(AttrConst.fileTotalSize | AttrConst.fileAllocSize)

        // The buffer is only used within this directory's read loop (before we
        // recurse), so a single per-worker buffer can be reused safely.
        while true {
            if cancelled.isSet { return }
            let count = withUnsafeMutablePointer(to: &attrList) { alistPtr -> Int in
                Int(getattrlistbulk(dirfd, alistPtr, buffer, bufSize, 0))
            }
            if count <= 0 { break } // 0 = done, <0 = error (skip remainder)

            var entry = UnsafeRawPointer(buffer)
            for _ in 0..<count {
                if let child = parseEntry(entry, parentURL: node.url) {
                    children.append(child)
                }
                let entryLength = entry.loadUnaligned(as: UInt32.self)
                entry = entry.advanced(by: Int(entryLength))
            }
        }

        node.children = children
        for c in children { c.parent = node }

        // Recurse into subdirectories.
        let subdirs = children.filter { $0.isDirectory }
        if parallelTopLevel && subdirs.count > 1 {
            DispatchQueue.concurrentPerform(iterations: subdirs.count) { i in
                // Each concurrent worker owns its own buffer for its subtree.
                let buf = UnsafeMutableRawPointer.allocate(byteCount: bufSize, alignment: 16)
                defer { buf.deallocate() }
                self.scanDirectory(subdirs[i], parallelTopLevel: false, buffer: buf, bufSize: bufSize)
            }
        } else {
            for sub in subdirs {
                scanDirectory(sub, parallelTopLevel: false, buffer: buffer, bufSize: bufSize)
            }
        }

        // Aggregate sizes and file counts up from children.
        var total: Int64 = 0
        var alloc: Int64 = 0
        var fileCount = 0
        for c in children {
            total += c.size
            alloc += c.allocatedSize
            fileCount += c.fileCount
        }
        node.size = total
        node.allocatedSize = alloc
        node.fileCount = fileCount
    }

    // MARK: - Entry parsing

    /// Parse one `getattrlistbulk` entry laid out as:
    /// `[u32 length][attribute_set_t returned][name ref][objtype][modtime]
    ///  [acctime][fileid][file total size][file alloc size]`
    /// Fields appear only when the per-entry `returned` bitmap flags them, in
    /// ascending attribute-bit order (common group before file group).
    private func parseEntry(_ entry: UnsafeRawPointer, parentURL: URL) -> FileNode? {
        var cursor = entry
        _ = cursor.loadUnaligned(as: UInt32.self)          // entry length
        cursor = cursor.advanced(by: MemoryLayout<UInt32>.size)

        // returned attribute set (5 × u32); we only need the common + file words.
        let returnedCommon = cursor.loadUnaligned(as: UInt32.self)
        let returnedFile = cursor.advanced(by: 3 * MemoryLayout<UInt32>.size)
            .loadUnaligned(as: UInt32.self)
        cursor = cursor.advanced(by: 5 * MemoryLayout<UInt32>.size)

        var name = ""
        var objType: UInt32 = 0
        var modTime: Date?
        var accTime: Date?
        var fileID: UInt64 = 0
        var logicalSize: Int64 = 0
        var allocSize: Int64 = 0

        if returnedCommon & AttrConst.name != 0 {
            // attrreference_t { s32 dataoffset; u32 length }, name at cursor+offset.
            let dataOffset = cursor.loadUnaligned(as: Int32.self)
            let strPtr = cursor.advanced(by: Int(dataOffset))
            name = String(cString: strPtr.assumingMemoryBound(to: CChar.self))
            cursor = cursor.advanced(by: 8)
        }
        if returnedCommon & AttrConst.objType != 0 {
            objType = cursor.loadUnaligned(as: UInt32.self)
            cursor = cursor.advanced(by: MemoryLayout<UInt32>.size)
        }
        if returnedCommon & AttrConst.modTime != 0 {
            let sec = cursor.loadUnaligned(as: Int.self)
            modTime = Date(timeIntervalSince1970: TimeInterval(sec))
            cursor = cursor.advanced(by: MemoryLayout<timespec>.size)
        }
        if returnedCommon & AttrConst.accTime != 0 {
            let sec = cursor.loadUnaligned(as: Int.self)
            accTime = Date(timeIntervalSince1970: TimeInterval(sec))
            cursor = cursor.advanced(by: MemoryLayout<timespec>.size)
        }
        if returnedCommon & AttrConst.fileID != 0 {
            fileID = cursor.loadUnaligned(as: UInt64.self)
            cursor = cursor.advanced(by: MemoryLayout<UInt64>.size)
        }
        if returnedFile & AttrConst.fileTotalSize != 0 {
            logicalSize = cursor.loadUnaligned(as: Int64.self)
            cursor = cursor.advanced(by: MemoryLayout<Int64>.size)
        }
        if returnedFile & AttrConst.fileAllocSize != 0 {
            allocSize = cursor.loadUnaligned(as: Int64.self)
            cursor = cursor.advanced(by: MemoryLayout<Int64>.size)
        }

        if name.isEmpty || name == "." || name == ".." { return nil }

        let isDir = objType == AttrConst.vdir
        let isSymlink = objType == AttrConst.vlnk
        if isSymlink { return nil } // never follow or count symlinks

        let childURL = parentURL.appendingPathComponent(name, isDirectory: isDir)

        // Physical dedup: only count a file's blocks once across hard links/clones.
        var countedAlloc = allocSize
        if !isDir && fileID != 0 && !seenInodes.insert(fileID) {
            countedAlloc = 0
        }

        if !isDir {
            progressCounter.record(bytes: logicalSize)
            reportProgressIfNeeded(path: childURL.path)
        }

        return FileNode(
            name: name,
            url: childURL,
            isDirectory: isDir,
            size: isDir ? 0 : logicalSize,
            allocatedSize: isDir ? 0 : countedAlloc,
            fileID: fileID,
            modificationDate: modTime,
            accessDate: accTime)
    }

    // MARK: - Root node

    private func makeNode(for url: URL, isDirectoryHint: Bool) -> FileNode? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
            return nil
        }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .fileAllocatedSizeKey, .contentModificationDateKey])
        return FileNode(
            name: url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent,
            url: url,
            isDirectory: isDir.boolValue,
            size: Int64(values?.fileSize ?? 0),
            allocatedSize: Int64(values?.fileAllocatedSize ?? 0),
            fileID: 0,
            modificationDate: values?.contentModificationDate,
            accessDate: nil)
    }

    private func reportProgressIfNeeded(path: String) {
        let n = progressCounter.value
        if n - lastProgressReport >= 2000 {
            lastProgressReport = n
            let p = Progress(filesScanned: n, bytesScanned: progressCounter.value64, currentPath: path)
            DispatchQueue.main.async { [progressCallback] in progressCallback?(p) }
        }
    }
}

// MARK: - Attribute constants (from <sys/attr.h> / <sys/vnode.h>)

private enum AttrConst {
    static let returnedAttrs: UInt32 = 0x8000_0000
    static let name: UInt32          = 0x0000_0001
    static let objType: UInt32       = 0x0000_0008
    static let modTime: UInt32       = 0x0000_0400
    static let accTime: UInt32       = 0x0000_1000
    static let fileID: UInt32        = 0x0200_0000

    static let fileTotalSize: UInt32 = 0x0000_0002
    static let fileAllocSize: UInt32 = 0x0000_0004

    static let vreg: UInt32 = 1
    static let vdir: UInt32 = 2
    static let vlnk: UInt32 = 5
}
