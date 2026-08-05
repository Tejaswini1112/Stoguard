import Foundation
import Darwin

/// Maps trashed item paths → original paths so Put Back works for Stoguard-deleted items.
/// Finder only restores items it trashed itself; NSWorkspace.recycle does not write that metadata.
enum TrashOriginStore {
    private static let xattrName = "com.stoguard.originalPath"

    private static var storeURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Stoguard", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("trash-origins.json")
    }

    static func recordRecycleResult(_ result: [URL: URL]) {
        guard !result.isEmpty else { return }
        var dict = load()
        for (original, trashed) in result {
            dict[trashed.path] = original.path
            setXattr(trashedPath: trashed.path, originalPath: original.path)
        }
        save(dict)
    }

    static func originalPath(forTrashedPath path: String) -> String? {
        if let fromXattr = readXattr(trashedPath: path) { return fromXattr }
        return load()[path]
    }

    static func remove(trashedPath: String) {
        var dict = load()
        dict.removeValue(forKey: trashedPath)
        save(dict)
    }

    static func remove(trashedPaths: [String]) {
        guard !trashedPaths.isEmpty else { return }
        var dict = load()
        for path in trashedPaths { dict.removeValue(forKey: path) }
        save(dict)
    }

    // MARK: - Persistence

    private static func load() -> [String: String] {
        guard let data = try? Data(contentsOf: storeURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return dict
    }

    private static func save(_ dict: [String: String]) {
        guard let data = try? JSONEncoder().encode(dict) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    // MARK: - xattr (survives if JSON is cleared)

    private static func setXattr(trashedPath: String, originalPath: String) {
        guard let data = originalPath.data(using: .utf8) else { return }
        trashedPath.withCString { path in
            xattrName.withCString { name in
                data.withUnsafeBytes { buf in
                    _ = setxattr(path, name, buf.baseAddress, buf.count, 0, 0)
                }
            }
        }
    }

    private static func readXattr(trashedPath: String) -> String? {
        var value: String?
        trashedPath.withCString { path in
            xattrName.withCString { name in
                let size = getxattr(path, name, nil, 0, 0, 0)
                guard size > 0 else { return }
                var buf = [UInt8](repeating: 0, count: size)
                guard getxattr(path, name, &buf, size, 0, 0) == size else { return }
                value = String(bytes: buf, encoding: .utf8)
            }
        }
        return value
    }
}
