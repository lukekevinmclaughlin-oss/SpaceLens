#if DEBUG
import Foundation

extension ScanViewModel {
    func seedDemoIfRequested() {
        guard ProcessInfo.processInfo.environment["SPACELENS_DEMO"] == "1", root == nil else { return }
        let gb: Int64 = 1_073_741_824
        var inode: UInt64 = 100

        func file(_ name: String, _ size: Double, _ ageDays: Int = 12) -> FileNode {
            inode += 1
            let node = FileNode(name: name, url: URL(fileURLWithPath: "/Users/luke/\(name)"),
                                isDirectory: false, size: Int64(size * Double(gb)),
                                allocatedSize: Int64(size * Double(gb)), fileID: inode,
                                modificationDate: Calendar.current.date(byAdding: .day, value: -ageDays, to: Date()),
                                accessDate: Calendar.current.date(byAdding: .day, value: -ageDays / 2, to: Date()))
            node.dominantCategory = FileCategory.of(node.url.pathExtension)
            return node
        }

        func directory(_ name: String, _ files: [(String, Double, Int)]) -> FileNode {
            inode += 1
            let dir = FileNode(name: name, url: URL(fileURLWithPath: "/Users/luke/\(name)"),
                               isDirectory: true, size: 0, allocatedSize: 0, fileID: inode,
                               modificationDate: Date(), accessDate: Date())
            let children = files.map { file($0.0, $0.1, $0.2) }
            children.forEach { $0.parent = dir }
            dir.children = children
            dir.size = children.reduce(0) { $0 + $1.size }
            dir.allocatedSize = children.reduce(0) { $0 + $1.allocatedSize }
            dir.fileCount = children.count
            dir.dominantCategory = children.max(by: { $0.size < $1.size })?.dominantCategory ?? .other
            return dir
        }

        let groups: [FileNode] = [
            directory("Photos", [("Lightroom Library.photoslibrary", 48, 9), ("RAW Archive 2025.zip", 27, 180), ("Family Videos.mov", 16, 32)]),
            directory("Applications", [("Xcode.app", 28, 5), ("Logic Pro.app", 19, 22), ("Creative Suite.app", 15, 18), ("Utilities.app", 8, 30)]),
            directory("Developer", [("DerivedData", 24, 16), ("iOS Simulators", 21, 8), ("node_modules", 12, 45), ("Docker Images", 7, 25)]),
            directory("Documents", [("Client Projects", 20, 14), ("Research Dataset.xlsx", 11, 7), ("Presentations.pdf", 9, 61), ("Archive.zip", 8, 420)]),
            directory("System Data", [("Application Support", 18, 4), ("Caches", 12, 2), ("Mail Attachments", 8, 85)]),
            directory("Downloads", [("Video Export.mp4", 12, 74), ("Installer.dmg", 8, 160), ("Assets.zip", 7, 25)]),
            directory("Music", [("Studio Sessions.wav", 10, 11), ("Lossless Library.flac", 8, 36)])
        ]
        inode += 1
        let rootNode = FileNode(name: "Macintosh HD", url: URL(fileURLWithPath: "/"),
                                isDirectory: true, size: 0, allocatedSize: 0, fileID: inode,
                                modificationDate: Date(), accessDate: Date())
        groups.forEach { $0.parent = rootNode }
        rootNode.children = groups
        rootNode.size = groups.reduce(0) { $0 + $1.size }
        rootNode.allocatedSize = groups.reduce(0) { $0 + $1.allocatedSize }
        rootNode.fileCount = groups.reduce(0) { $0 + $1.fileCount }
        rootNode.dominantCategory = .other

        root = rootNode
        current = rootNode
        breadcrumb = [rootNode]
        scannedURL = rootNode.url
        volumeTotal = 512 * gb
        volumeFree = 154 * gb
        state = .complete(duration: 1.84)

        // Deterministic local history for Simulator/App Store screenshot QA.
        if RecentScans.shared.entries.filter({ $0.path == rootNode.url.path }).count < 3 {
            RecentScans.shared.record(url: rootNode.url, size: 310 * gb,
                                      volumeTotal: volumeTotal, volumeFree: 176 * gb,
                                      at: Calendar.current.date(byAdding: .day, value: -14, to: Date())!)
            RecentScans.shared.record(url: rootNode.url, size: 335 * gb,
                                      volumeTotal: volumeTotal, volumeFree: 165 * gb,
                                      at: Calendar.current.date(byAdding: .day, value: -7, to: Date())!)
            RecentScans.shared.record(url: rootNode.url, size: rootNode.size,
                                      volumeTotal: volumeTotal, volumeFree: volumeFree, at: Date())
        }
    }
}
#endif
