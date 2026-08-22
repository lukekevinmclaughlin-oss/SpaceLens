import Foundation
import Combine

/// Persists recently scanned locations so they reappear on the launch screen and
/// survive relaunch. On macOS we store security-scoped bookmarks so access is
/// retained across launches (needed for the sandboxed MAS build).
final class RecentScans: ObservableObject {
    static let shared = RecentScans()

    struct Entry: Identifiable, Codable {
        var id: String { path }
        let path: String
        let name: String
        var bookmark: Data?
        var lastScanned: Double     // referenceDate seconds
        var lastSize: Int64
    }

    @Published private(set) var entries: [Entry] = []
    private let key = "recentScans.v1"
    private let maxEntries = 6

    private init() { load() }

    func record(url: URL, size: Int64, at time: Date) {
        var bookmark: Data?
        #if os(macOS)
        bookmark = try? url.bookmarkData(options: [.withSecurityScope],
                                         includingResourceValuesForKeys: nil, relativeTo: nil)
        #else
        bookmark = try? url.bookmarkData()
        #endif
        let entry = Entry(path: url.path, name: url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent,
                          bookmark: bookmark, lastScanned: time.timeIntervalSinceReferenceDate, lastSize: size)
        entries.removeAll { $0.path == entry.path }
        entries.insert(entry, at: 0)
        if entries.count > maxEntries { entries = Array(entries.prefix(maxEntries)) }
        save()
    }

    /// Resolve an entry back to a usable URL, starting security-scoped access.
    func resolve(_ entry: Entry) -> URL? {
        guard let data = entry.bookmark else {
            let u = URL(fileURLWithPath: entry.path)
            return FileManager.default.fileExists(atPath: u.path) ? u : nil
        }
        var stale = false
        #if os(macOS)
        let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope],
                           relativeTo: nil, bookmarkDataIsStale: &stale)
        #else
        let url = try? URL(resolvingBookmarkData: data, relativeTo: nil, bookmarkDataIsStale: &stale)
        #endif
        return url
    }

    func remove(_ entry: Entry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func clear() { entries = []; save() }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data) else { return }
        entries = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
