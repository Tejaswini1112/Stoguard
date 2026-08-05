import Foundation
import Darwin

/// Thin wrapper over `du` to get real on-disk sizes.
enum Shell {
    static func du(_ path: String, depth: Int? = nil) -> [(path: String, bytes: Int64)] {
        guard FileManager.default.fileExists(atPath: path) else { return [] }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        var args = ["-k"]
        if let depth { args += ["-d", "\(depth)"] } else { args += ["-s"] }
        args.append(path)
        proc.arguments = args

        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do { try proc.run() } catch { return [] }

        let data = out.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()

        let text = String(decoding: data, as: UTF8.self)
        var results: [(String, Int64)] = []
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2, let kb = Int64(parts[0].trimmingCharacters(in: .whitespaces))
            else { continue }
            results.append((String(parts[1]), kb * 1024))
        }
        return results
    }

    static func size(_ path: String) -> Int64 {
        du(path).first?.bytes ?? 0
    }

    /// Real on-disk allocation — critical for Docker sparse VM disks.
    static func allocatedSize(_ path: String) -> Int64 {
        let url = URL(fileURLWithPath: path)
        guard let vals = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]),
              let bytes = vals.totalFileAllocatedSize ?? vals.fileAllocatedSize
        else { return size(path) }
        return Int64(bytes)
    }
}

enum PathUtil {
    static func expand(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }
}

struct PathActivity {
    static func lastActivity(at path: String) -> Date? {
        let url = URL(fileURLWithPath: path)
        let keys: Set<URLResourceKey> = [
            .contentAccessDateKey,
            .contentModificationDateKey,
            .creationDateKey,
        ]
        guard let vals = try? url.resourceValues(forKeys: keys) else { return nil }
        let dates = [vals.contentAccessDate, vals.contentModificationDate, vals.creationDate].compactMap { $0 }
        return dates.max()
    }
}

struct Scanner {
    let rules: [Rule]

    /// Protected parents only — never scan `$HOME` root (that lists your projects as "unknown").
    static let discoveryParents = [
        "~/.cache",
        "~/Library/Caches",
        "~/Library/Application Support",
        "~/Library/Containers",
    ]
    static let discoveryThreshold: Int64 = 1_073_741_824  // 1 GB
    /// Only drill into children when the parent is at least this large.
    static let childDrillThreshold: Int64 = 400_000_000 // 400 MB
    static let maxChildren = 5

    static func loadRules() -> [Rule] {
        let bundled = loadBundledRules()
        let plugins = PluginLoader.loadRules(platform: "macos")
        return CloudRules.resolveRules(bundled: bundled, plugins: plugins)
    }

    static func loadBundledRules() -> [Rule] {
        for url in ruleSearchURLs() {
            guard let data = try? Data(contentsOf: url),
                  let rules = try? JSONDecoder().decode([Rule].self, from: data)
            else { continue }
            if !rules.isEmpty { return rules }
        }
        return embeddedFallback
    }

    private static func ruleSearchURLs() -> [URL] {
        var urls: [URL] = []
        if let u = Bundle.main.url(forResource: "rules", withExtension: "json") { urls.append(u) }
        let exeDir = Bundle.main.bundleURL.deletingLastPathComponent()
        urls.append(exeDir.appendingPathComponent("rules.json"))
        urls.append(Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/rules.json"))
        return urls
    }

    private static let embeddedFallback: [Rule] = [
        Rule(id: "puppeteer", name: "Puppeteer browsers", path: "~/.cache/puppeteer",
             category: "Browser Automation", safety: .safe,
             note: "Chromium downloaded by Puppeteer. Re-downloads when a script runs again."),
        Rule(id: "docker-desktop", name: "Docker Desktop data",
             path: "~/Library/Containers/com.docker.docker", category: "Containers & K8s",
             safety: .command,
             note: "Docker's VM disk. Reclaim with prune; never delete by hand.",
             command: "docker system prune -a --volumes"),
    ]

    func rules(for categories: Set<String>) -> [Rule] {
        rules.filter { categories.contains($0.category) }
    }

    /// Shared mutable scan state — safe across `concurrentPerform` workers.
    final class ScanSession: @unchecked Sendable {
        var cache: ScanFingerprintCache
        var profile: AdaptiveProfile
        private var _cacheHits = 0
        let lock = NSLock()

        init(cache: ScanFingerprintCache, profile: AdaptiveProfile) {
            self.cache = cache
            self.profile = profile
        }

        var cacheHits: Int {
            get { lock.withLock { _cacheHits } }
            set { lock.withLock { _cacheHits = newValue } }
        }

        func bumpCacheHits() {
            lock.withLock { _cacheHits += 1 }
        }

        /// Read hits after the parallel scan has finished (no concurrent writers).
        func snapshotCacheHits() -> Int {
            lock.withLock { _cacheHits }
        }
    }

    /// Parallel known-path scan with incremental cache + adaptive skipping.
    func scanKnownParallel(
        categories: Set<String>?,
        session: ScanSession,
        onItem: @escaping (ScanItem) -> Void
    ) -> (cacheHits: Int, skipped: Int) {
        let subset: [Rule]
        if let categories {
            subset = rules.filter { categories.contains($0.category) }
        } else {
            subset = rules
        }

        session.lock.lock()
        session.profile.beginScan()
        session.lock.unlock()

        var skipped = 0
        var toScan: [Rule] = []
        for rule in subset {
            session.lock.lock()
            let ok = session.profile.shouldScan(ruleID: rule.id)
            session.lock.unlock()
            if ok { toScan.append(rule) } else { skipped += 1 }
        }

        DispatchQueue.concurrentPerform(iterations: max(toScan.count, 0)) { idx in
            guard idx < toScan.count else { return }
            let rule = toScan[idx]
            guard let item = Self.measure(rule: rule, session: session) else { return }
            onItem(item)
        }

        return (session.snapshotCacheHits(), skipped)
    }

    /// Legacy sequential entry point (tests / callers that don't need parallelism).
    func scanKnown(categories: Set<String>?, onItem: @escaping (ScanItem) -> Void) {
        let session = ScanSession(cache: ScanFingerprintCache(), profile: AdaptiveProfile())
        _ = scanKnownParallel(categories: categories, session: session, onItem: onItem)
    }

    private static func measure(rule: Rule, session: ScanSession) -> ScanItem? {
        let abs = PathUtil.expand(rule.path)
        let fm = FileManager.default
        guard fm.fileExists(atPath: abs) else {
            session.lock.lock()
            session.profile.recordMiss(ruleID: rule.id)
            session.lock.unlock()
            return nil
        }

        let preferAllocated = rule.id == "docker-desktop"
        session.lock.lock()
        let cached = session.cache.cachedSize(forRuleID: rule.id, path: abs, preferAllocated: preferAllocated)
        session.lock.unlock()

        let bytes: Int64
        let fromCache: Bool
        if let cached {
            bytes = cached
            fromCache = true
            session.bumpCacheHits()
        } else {
            bytes = preferAllocated ? Shell.allocatedSize(abs) : Shell.size(abs)
            fromCache = false
            session.lock.lock()
            session.cache.store(
                ruleID: rule.id,
                path: abs,
                sizeBytes: preferAllocated ? Shell.size(abs) : bytes,
                allocatedHint: preferAllocated ? bytes : nil
            )
            session.lock.unlock()
        }

        guard bytes > 0 else {
            session.lock.lock()
            session.profile.recordMiss(ruleID: rule.id)
            session.lock.unlock()
            return nil
        }

        session.lock.lock()
        session.profile.recordHit(ruleID: rule.id)
        session.lock.unlock()

        let activity = PathActivity.lastActivity(at: abs)
        let children: [LargeChild]
        if bytes >= childDrillThreshold {
            children = largestChildren(of: abs, limit: maxChildren)
        } else {
            children = []
        }

        return ScanItem(
            id: rule.id, name: rule.name, path: abs, category: rule.category,
            safety: rule.safety, note: rule.note, command: rule.command,
            sizeBytes: bytes, known: true,
            lastActivity: activity,
            largestChildren: children,
            fromCache: fromCache
        )
    }

    static func largestChildren(of path: String, limit: Int) -> [LargeChild] {
        let rows = Shell.du(path, depth: 1)
            .filter { $0.path != path && $0.bytes > 0 }
            .sorted { $0.bytes > $1.bytes }
            .prefix(limit)
        return rows.map { row in
            LargeChild(
                name: (row.path as NSString).lastPathComponent,
                path: row.path,
                sizeBytes: row.bytes
            )
        }
    }

    /// Only runs when Full Disk Access is granted — otherwise macOS TCC spams per folder.
    func scanUnknown(knownPaths: Set<String>, onItem: @escaping (ScanItem) -> Void) {
        var seen = knownPaths
        for parent in Scanner.discoveryParents {
            let absParent = PathUtil.expand(parent)
            for child in Shell.du(absParent, depth: 1) {
                if child.path == absParent { continue }
                if child.bytes < Scanner.discoveryThreshold { continue }
                if Scanner.overlaps(child.path, with: seen) { continue }
                seen.insert(child.path)
                let name = (child.path as NSString).lastPathComponent
                let activity = PathActivity.lastActivity(at: child.path)
                let kids = child.bytes >= Scanner.childDrillThreshold
                    ? Self.largestChildren(of: child.path, limit: Scanner.maxChildren)
                    : []
                onItem(ScanItem(
                    id: "unknown:\(child.path)", name: name, path: child.path,
                    category: "Unknown heavy folders", safety: .check,
                    note: "Large folder not in Stoguard's rules database. Reveal in Finder and confirm what it is before removing.",
                    command: nil, sizeBytes: child.bytes, known: false,
                    lastActivity: activity, largestChildren: kids, fromCache: false
                ))
            }
        }
    }

    static func overlaps(_ path: String, with set: Set<String>) -> Bool {
        for p in set where path == p || path.hasPrefix(p + "/") || p.hasPrefix(path + "/") {
            return true
        }
        return false
    }
}

enum DiskInfo {
    /// Whole-disk stats aligned with **System Settings → Storage** (APFS container level).
    static func homeVolume() -> (free: Int64, total: Int64) {
        if let c = containerStats() { return c }
        if let sv = statVolume(at: "/System/Volumes/Data") { return sv }
        if let sv = statVolume(at: NSHomeDirectory()) { return sv }
        let home = NSHomeDirectory()
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: home),
              let free = attrs[.systemFreeSize] as? NSNumber,
              let total = attrs[.systemSize] as? NSNumber
        else { return (0, 0) }
        return (free.int64Value, total.int64Value)
    }

    /// `diskutil info` reports APFS container size — matches System Settings (245 GB disk, not 228 GB volume).
    private static func containerStats() -> (free: Int64, total: Int64)? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        proc.arguments = ["info", "-plist", "/System/Volumes/Data"]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do { try proc.run() } catch { return nil }
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let total = plist["APFSContainerSize"] as? NSNumber,
              let free = plist["APFSContainerFree"] as? NSNumber,
              total.int64Value > 0
        else { return nil }
        return (free.int64Value, total.int64Value)
    }

    private static func statVolume(at path: String) -> (free: Int64, total: Int64)? {
        var stats = statvfs()
        let rc = path.withCString { statvfs($0, &stats) }
        guard rc == 0 else { return nil }
        let block = Int64(stats.f_frsize)
        guard block > 0 else { return nil }
        let total = Int64(stats.f_blocks) * block
        let free = Int64(stats.f_bavail) * block
        guard total > 0 else { return nil }
        return (free, total)
    }
}
