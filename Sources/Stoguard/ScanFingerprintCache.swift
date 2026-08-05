import Foundation

/// Incremental scan cache — skip `du` when a folder's fingerprint is unchanged.
struct ScanFingerprint: Codable, Hashable, Sendable {
    var sizeBytes: Int64
    var mtime: TimeInterval
    var inode: UInt64
    var allocatedHint: Int64?
    var updatedAt: TimeInterval
}

struct ScanFingerprintCache: Codable, Sendable {
    var entries: [String: ScanFingerprint] = [:]

    private static var fileURL: URL {
        SupportPaths.directory.appendingPathComponent("scan-cache.json")
    }

    static func load() -> ScanFingerprintCache {
        guard let data = try? Data(contentsOf: fileURL),
              let cache = try? JSONDecoder().decode(ScanFingerprintCache.self, from: data)
        else { return ScanFingerprintCache() }
        return cache
    }

    func save() {
        SupportPaths.ensureDirectory()
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }

    /// Live fingerprint of a path (mtime + inode + quick allocated size for files).
    static func fingerprint(of path: String) -> (mtime: TimeInterval, inode: UInt64)? {
        let url = URL(fileURLWithPath: path)
        guard let vals = try? url.resourceValues(forKeys: [
            .contentModificationDateKey,
            .fileResourceIdentifierKey,
        ]) else { return nil }

        let mtime = vals.contentModificationDate?.timeIntervalSince1970 ?? 0
        var inode: UInt64 = 0
        if let id = vals.fileResourceIdentifier as? NSObject {
            // Stable-enough digest of the resource identifier.
            inode = UInt64(bitPattern: Int64(id.hash))
        } else {
            var st = stat()
            if path.withCString({ stat($0, &st) }) == 0 {
                inode = UInt64(st.st_ino)
            }
        }
        return (mtime, inode)
    }

    mutating func cachedSize(forRuleID id: String, path: String, preferAllocated: Bool) -> Int64? {
        guard let live = Self.fingerprint(of: path),
              let entry = entries[id],
              entry.mtime == live.mtime,
              entry.inode == live.inode
        else { return nil }
        if preferAllocated, let hint = entry.allocatedHint, hint > 0 { return hint }
        return entry.sizeBytes
    }

    mutating func store(ruleID: String, path: String, sizeBytes: Int64, allocatedHint: Int64? = nil) {
        guard let live = Self.fingerprint(of: path) else { return }
        entries[ruleID] = ScanFingerprint(
            sizeBytes: sizeBytes,
            mtime: live.mtime,
            inode: live.inode,
            allocatedHint: allocatedHint,
            updatedAt: Date().timeIntervalSince1970
        )
    }

    mutating func invalidate(ids: Set<String>) {
        for id in ids { entries.removeValue(forKey: id) }
    }
}

enum SupportPaths {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Stoguard", isDirectory: true)
    }

    static func ensureDirectory() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
