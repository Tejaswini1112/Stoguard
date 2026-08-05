import Foundation

/// Validates paths before Trash so symlinks cannot redirect cleanup outside the home tree.
enum PathSafety {
    enum Failure: Error, Equatable {
        case missing
        case outsideHome
        case symlinkEscape
        case disallowedRoot

        var message: String {
            switch self {
            case .missing: return "Path no longer exists."
            case .outsideHome: return "Path resolves outside your home folder."
            case .symlinkEscape: return "Symlink points outside the intended location."
            case .disallowedRoot: return "Refusing to trash a protected system location."
            }
        }
    }

    /// Roots we never trash into, even if somehow reachable.
    private static let blockedPrefixes = [
        "/System",
        "/usr",
        "/bin",
        "/sbin",
        "/Library",
        "/private/var/db",
        "/private/etc",
    ]

    static func homeURL() -> URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL
    }

    /// Returns the URL to recycle if safe, otherwise a failure reason.
    /// - Parameter allowApplications: Permit `/Applications/*.app` (uninstall flow).
    static func validateForTrash(_ path: String, allowApplications: Bool = false) -> Result<URL, Failure> {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir) else {
            return .failure(.missing)
        }

        let url = URL(fileURLWithPath: path, isDirectory: isDir.boolValue)
        let standardized = url.standardizedFileURL
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        let home = homeURL()

        let inApps = isUnderApplications(standardized) && isUnderApplications(resolved)
        if allowApplications && inApps {
            // Uninstalling a user-facing .app is allowed; still block System.
        } else {
            guard isUnder(home, candidate: standardized) else {
                return .failure(.outsideHome)
            }
            guard isUnder(home, candidate: resolved) else {
                return .failure(.symlinkEscape)
            }
        }

        let resolvedPath = resolved.path
        for blocked in blockedPrefixes {
            if resolvedPath == blocked || resolvedPath.hasPrefix(blocked + "/") {
                return .failure(.disallowedRoot)
            }
        }

        if isSymlink(at: standardized), !isUnder(standardized.deletingLastPathComponent(), candidate: resolved) {
            let linkParent = standardized.deletingLastPathComponent().resolvingSymlinksInPath()
            if !isUnder(linkParent, candidate: resolved) && !isUnder(home.appendingPathComponent("Library"), candidate: resolved) {
                return .failure(.symlinkEscape)
            }
        }

        return .success(standardized)
    }

    static func filterSafeTrashURLs(_ paths: [String], allowApplications: Bool = false) -> (safe: [URL], rejected: [(String, Failure)]) {
        var safe: [URL] = []
        var rejected: [(String, Failure)] = []
        for path in paths {
            switch validateForTrash(path, allowApplications: allowApplications) {
            case .success(let url): safe.append(url)
            case .failure(let err): rejected.append((path, err))
            }
        }
        return (safe, rejected)
    }

    private static func isUnderApplications(_ url: URL) -> Bool {
        let p = url.path
        return p.hasPrefix("/Applications/") || (p.hasPrefix("/Users/") && p.contains("/Applications/"))
    }

    private static func isUnder(_ root: URL, candidate: URL) -> Bool {
        let r = root.path
        let c = candidate.path
        return c == r || c.hasPrefix(r.hasSuffix("/") ? r : r + "/")
    }

    private static func isSymlink(at url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
        return values?.isSymbolicLink == true
    }
}
