import Foundation
import CryptoKit

/// The finders that turn a viewer into a buyer: they surface the reclaimable
/// stuff directly instead of asking the user to hunt through a chart.
enum SmartFinders {

    // MARK: Largest files

    static func largestFiles(in root: FileNode, limit: Int = 200) -> [FileNode] {
        var files: [FileNode] = []
        root.flattenedFiles(into: &files)
        return Array(files.sorted { $0.size > $1.size }.prefix(limit))
    }

    // MARK: Old & unopened files

    /// Files not modified (and, when available, not accessed) in over `days` days.
    static func oldFiles(in root: FileNode, days: Int = 365, minSize: Int64 = 5 * 1024 * 1024, limit: Int = 300) -> [FileNode] {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        var files: [FileNode] = []
        root.flattenedFiles(into: &files)
        return files
            .filter { $0.size >= minSize }
            .filter { node in
                let ref = node.accessDate ?? node.modificationDate
                guard let ref else { return false }
                return ref < cutoff
            }
            .sorted { $0.size > $1.size }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: Dev junk

    struct JunkRule: Identifiable {
        let id = UUID()
        let label: String
        let matchesDir: (String) -> Bool
    }

    static let junkRules: [JunkRule] = [
        JunkRule(label: "node_modules") { $0 == "node_modules" },
        JunkRule(label: "DerivedData")  { $0 == "DerivedData" },
        JunkRule(label: ".venv / venv") { $0 == ".venv" || $0 == "venv" || $0 == "env" },
        JunkRule(label: "__pycache__")  { $0 == "__pycache__" },
        JunkRule(label: "target (Rust/Java)") { $0 == "target" },
        JunkRule(label: "build")        { $0 == "build" || $0 == ".build" },
        JunkRule(label: ".gradle")      { $0 == ".gradle" },
        JunkRule(label: "Pods")         { $0 == "Pods" },
        JunkRule(label: ".next / .nuxt / dist") { $0 == ".next" || $0 == ".nuxt" || $0 == "dist" },
    ]

    struct JunkHit: Identifiable {
        let id = UUID()
        let node: FileNode
        let rule: String
    }

    /// Finds dev-junk directories. Does not descend into a match once found
    /// (a node_modules inside a node_modules is already counted by its parent).
    static func devJunk(in root: FileNode, limit: Int = 400) -> [JunkHit] {
        var hits: [JunkHit] = []
        func walk(_ node: FileNode) {
            guard node.isDirectory, let children = node.children else { return }
            for child in children where child.isDirectory {
                if let rule = junkRules.first(where: { $0.matchesDir(child.name) }) {
                    hits.append(JunkHit(node: child, rule: rule.label))
                    // do not descend — the whole folder is the reclaimable unit
                } else {
                    walk(child)
                }
            }
        }
        walk(root)
        return Array(hits.sorted { $0.node.size > $1.node.size }.prefix(limit))
    }

    // MARK: Duplicate detection

    struct DuplicateGroup: Identifiable {
        let id = UUID()
        let size: Int64
        let files: [FileNode]
        var reclaimable: Int64 { size * Int64(max(0, files.count - 1)) }
    }

    /// Three-stage dedup to avoid hashing everything:
    /// 1. group by identical logical size (cheap),
    /// 2. within a size group, hash the first + last 64 KB (fast partial hash),
    /// 3. confirm partial-hash collisions with a full SHA-256.
    static func duplicates(in root: FileNode,
                           minSize: Int64 = 1024 * 1024,
                           isCancelled: () -> Bool = { false },
                           progress: ((String) -> Void)? = nil) -> [DuplicateGroup] {
        var files: [FileNode] = []
        root.flattenedFiles(into: &files)

        // Stage 1 — bucket by size, drop uniques and tiny files.
        var bySize: [Int64: [FileNode]] = [:]
        for f in files where f.size >= minSize {
            bySize[f.size, default: []].append(f)
        }
        let sizeGroups = bySize.filter { $0.value.count > 1 }

        var groups: [DuplicateGroup] = []

        for (size, candidates) in sizeGroups {
            if isCancelled() { break }
            // Stage 2 — partial hash.
            var byPartial: [String: [FileNode]] = [:]
            for f in candidates {
                if isCancelled() { break }
                guard let ph = partialHash(f.url) else { continue }
                byPartial[ph, default: []].append(f)
            }
            for (_, partialMatched) in byPartial where partialMatched.count > 1 {
                // Stage 3 — full hash to confirm true duplicates.
                var byFull: [String: [FileNode]] = [:]
                for f in partialMatched {
                    if isCancelled() { break }
                    progress?(f.name)
                    guard let fh = fullHash(f.url) else { continue }
                    byFull[fh, default: []].append(f)
                }
                for (_, confirmed) in byFull where confirmed.count > 1 {
                    groups.append(DuplicateGroup(size: size, files: confirmed))
                }
            }
        }
        return groups.sorted { $0.reclaimable > $1.reclaimable }
    }

    private static func partialHash(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        let chunk = 64 * 1024
        if let head = try? handle.read(upToCount: chunk) { hasher.update(data: head) }
        if let end = try? handle.seekToEnd(), end > UInt64(chunk) {
            try? handle.seek(toOffset: end - UInt64(chunk))
            if let tail = try? handle.read(upToCount: chunk) { hasher.update(data: tail) }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func fullHash(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let block = try? handle.read(upToCount: 1024 * 1024), !block.isEmpty {
            hasher.update(data: block)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
