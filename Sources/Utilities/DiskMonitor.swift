import Foundation
import Combine

/// Polls mounted volumes for free space so the menu-bar watcher can show usage
/// at a glance and nudge when a disk runs low. macOS-only.
@MainActor
final class DiskMonitor: ObservableObject {
    static let shared = DiskMonitor()

    struct VolumeInfo: Identifiable {
        let id: String          // mount path
        let name: String
        let total: Int64
        let free: Int64
        let isInternal: Bool
        var used: Int64 { max(0, total - free) }
        var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
        var freeFraction: Double { total > 0 ? Double(free) / Double(total) : 1 }
    }

    @Published private(set) var volumes: [VolumeInfo] = []
    private var timer: Timer?

    private init() {
        refresh()
        #if os(macOS)
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        #endif
    }

    /// The volume that contains the user's home folder (the one people care about).
    var primary: VolumeInfo? {
        #if os(macOS)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return volumes.filter { home.hasPrefix($0.id) }.max { $0.id.count < $1.id.count }
            ?? volumes.first { $0.isInternal } ?? volumes.first
        #else
        return volumes.first { $0.isInternal } ?? volumes.first
        #endif
    }

    var isLow: Bool {
        guard let p = primary else { return false }
        return p.freeFraction < Double(AppSettings.shared.lowSpacePercent) / 100.0
    }

    func refresh() {
        #if os(macOS)
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeTotalCapacityKey,
                                      .volumeAvailableCapacityForImportantUsageKey,
                                      .volumeAvailableCapacityKey, .volumeIsBrowsableKey,
                                      .volumeIsInternalKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                         options: [.skipHiddenVolumes]) ?? []
        var out: [VolumeInfo] = []
        for url in urls {
            guard let v = try? url.resourceValues(forKeys: Set(keys)),
                  v.volumeIsBrowsable == true,
                  let total = v.volumeTotalCapacity, total > 0 else { continue }
            let free = v.volumeAvailableCapacityForImportantUsage ?? Int64(v.volumeAvailableCapacity ?? 0)
            out.append(VolumeInfo(id: url.path,
                                  name: v.volumeName ?? url.lastPathComponent,
                                  total: Int64(total),
                                  free: Int64(free),
                                  isInternal: v.volumeIsInternal ?? false))
        }
        // internal disks first, then largest
        volumes = out.sorted { ($0.isInternal ? 1 : 0, $0.total) > ($1.isInternal ? 1 : 0, $1.total) }
        #endif
    }
}
