import Foundation

/// Minimal lock-guarded atomics. The scanner touches these from many concurrent
/// workers; a small os_unfair_lock keeps them correct without pulling in Swift
/// Atomics as a package dependency.

final class ManagedAtomicFlag: @unchecked Sendable {
    private var lock = os_unfair_lock()
    private var flag = false
    var isSet: Bool { os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }; return flag }
    func set()   { os_unfair_lock_lock(&lock); flag = true;  os_unfair_lock_unlock(&lock) }
    func clear() { os_unfair_lock_lock(&lock); flag = false; os_unfair_lock_unlock(&lock) }
}

/// Combined files+bytes counter. One lock acquisition per file (`record`) instead
/// of two, which matters across many concurrent scan workers.
final class ManagedAtomicCounter: @unchecked Sendable {
    private var lock = os_unfair_lock()
    private var count: Int = 0
    private var bytes: Int64 = 0
    var value: Int     { os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }; return count }
    var value64: Int64 { os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }; return bytes }
    func record(bytes n: Int64) { os_unfair_lock_lock(&lock); count += 1; bytes += n; os_unfair_lock_unlock(&lock) }
    func reset() { os_unfair_lock_lock(&lock); count = 0; bytes = 0; os_unfair_lock_unlock(&lock) }
}

/// Concurrent set of inode numbers, used to dedupe physical blocks shared by
/// hard links and APFS clones. Sharded so concurrent workers rarely contend on
/// the same lock. `insert` returns true if the id was newly added.
final class InodeSet: @unchecked Sendable {
    private final class Shard {
        var lock = os_unfair_lock()
        var set = Set<UInt64>()
    }
    private let shards: [Shard]
    private let mask: UInt64

    init(shardCount: Int = 16) {
        // round up to a power of two so we can mask instead of modulo
        var n = 1
        while n < shardCount { n <<= 1 }
        shards = (0..<n).map { _ in Shard() }
        mask = UInt64(n - 1)
    }

    func insert(_ id: UInt64) -> Bool {
        let shard = shards[Int(id & mask)]
        os_unfair_lock_lock(&shard.lock)
        defer { os_unfair_lock_unlock(&shard.lock) }
        return shard.set.insert(id).inserted
    }

    func reset() {
        for shard in shards {
            os_unfair_lock_lock(&shard.lock)
            shard.set.removeAll(keepingCapacity: true)
            os_unfair_lock_unlock(&shard.lock)
        }
    }
}
