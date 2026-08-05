import Foundation
import AppKit

/// Finds installed apps and their related Library files — PureMac-style grouping.
enum AppScanner {
    private nonisolated(unsafe) static let fm = FileManager.default
    private static let home = NSHomeDirectory()

    static let protectedPrefixes = ["com.apple."]

    private static func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return fm.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    private static func entry(
        path: String, name: String? = nil, kind: FileGroupKind,
        bytes: Int64, confirm: Bool = false
    ) -> FileEntry {
        FileEntry(
            id: path,
            name: name ?? (path as NSString).lastPathComponent,
            path: path,
            sizeBytes: bytes,
            kind: kind,
            requiresConfirm: confirm || (kind == .application),
            isDirectory: isDirectory(path)
        )
    }

    static func listApps() -> [InstalledApp] {
        var seen = Set<String>()
        var apps: [InstalledApp] = []

        for base in ["/Applications", "\(home)/Applications"] {
            walkForApps(in: base, seen: &seen, apps: &apps)
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Finds `.app` bundles in /Applications and one level of subfolders (TeX/, Python/, Adobe/, etc.).
    /// Skips helper bundles nested inside another app’s Contents/ folder.
    private static func walkForApps(in dir: String, seen: inout Set<String>, apps: inout [InstalledApp]) {
        guard let names = try? fm.contentsOfDirectory(atPath: dir) else { return }
        for name in names {
            let path = (dir as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { continue }

            if name.hasSuffix(".app") {
                guard !path.contains("/Contents/"), seen.insert(path).inserted else { continue }
                let bundleID = bundleIdentifier(at: path)
                let size = Shell.size(path)
                apps.append(InstalledApp(
                    id: path, name: name.replacingOccurrences(of: ".app", with: ""),
                    bundleID: bundleID, appPath: path,
                    totalBytes: size, fileCount: 1,
                    isSystemApp: bundleID.map { isProtected($0) } ?? false
                ))
            } else if !name.hasSuffix(".appex") && !name.hasSuffix(".plugin") && !name.hasSuffix(".framework") {
                walkForApps(in: path, seen: &seen, apps: &apps)
            }
        }
    }

    /// Full related-file scan for the detail panel.
    static func relatedFiles(appPath: String, bundleID: String?, appName: String) -> [FileGroup] {
        var groups: [FileGroupKind: [FileEntry]] = [:]
        let bid = bundleID ?? ""
        let sys = isProtected(bid)

        func add(_ kind: FileGroupKind, _ path: String, confirm: Bool = false) {
            guard fm.fileExists(atPath: path) else { return }
            let bytes = Shell.size(path)
            guard bytes > 0 else { return }
            groups[kind, default: []].append(entry(path: path, kind: kind, bytes: bytes, confirm: confirm))
        }

        add(.application, appPath, confirm: true)

        if !bid.isEmpty {
            add(.containers, "\(home)/Library/Containers/\(bid)")
            add(.preferences, "\(home)/Library/Preferences/\(bid).plist")
            add(.savedState, "\(home)/Library/Saved Application State/\(bid).savedState")
            add(.webKit, "\(home)/Library/WebKit/\(bid)")
            add(.caches, "\(home)/Library/Caches/\(bid)")
        }

        // Name-based paths (many apps use display name, not bundle id).
        for base in ["\(home)/Library/Caches", "\(home)/Library/Application Support",
                     "\(home)/Library/Logs"] {
            add(kindForBase(base), "\(base)/\(appName)")
        }
        if !bid.isEmpty {
            add(.applicationSupport, "\(home)/Library/Application Support/\(bid)")
        }

        // Preference plists matching bundle id prefix (com.docker.* etc.)
        if let prefs = try? fm.contentsOfDirectory(atPath: "\(home)/Library/Preferences") {
            let prefix = bid.split(separator: ".").prefix(2).joined(separator: ".")
            for f in prefs where f.hasSuffix(".plist") {
                let stem = f.replacingOccurrences(of: ".plist", with: "")
                if stem == bid || (!prefix.isEmpty && stem.hasPrefix(prefix)) {
                    add(.preferences, "\(home)/Library/Preferences/\(f)")
                }
            }
        }

        // Container group folders that contain bundle id
        if !bid.isEmpty, let containers = try? fm.contentsOfDirectory(atPath: "\(home)/Library/Containers") {
            for c in containers where c.contains(bid) || bid.contains(c) {
                add(.containers, "\(home)/Library/Containers/\(c)")
            }
        }

        if sys {
            // Strip application bundle from selectable groups for Apple apps.
            groups[.application] = groups[.application]?.map {
                FileEntry(
                    id: $0.id, name: $0.name, path: $0.path, sizeBytes: $0.sizeBytes,
                    kind: $0.kind, requiresConfirm: true, isDirectory: $0.isDirectory
                )
            }
        }

        return FileGroupKind.allCases.compactMap { kind in
            guard kind != .contents, let entries = groups[kind], !entries.isEmpty else { return nil }
            return FileGroup(kind: kind, entries: entries.sorted { $0.sizeBytes > $1.sizeBytes })
        }
    }

    /// Folder drill-down for cache scan rows. DerivedData gets per-project breakdown.
    static func folderContents(path: String, ruleID: String? = nil) -> [FileGroup] {
        if ruleID == "xcode-deriveddata" || path.hasSuffix("DerivedData") {
            return derivedDataBreakdown(path: path)
        }
        let children = Shell.du(path, depth: 1).filter { $0.path != path && $0.bytes > 0 }
        let entries = children.map { child in
            entry(
                path: child.path,
                name: friendlyName(for: child.path) ?? (child.path as NSString).lastPathComponent,
                kind: .contents,
                bytes: child.bytes
            )
        }.sorted { $0.sizeBytes > $1.sizeBytes }
        guard !entries.isEmpty else { return [] }
        return [FileGroup(kind: .contents, entries: entries)]
    }

    /// ClearDisk-style per-project sizes inside Xcode DerivedData.
    static func derivedDataBreakdown(path: String) -> [FileGroup] {
        guard let names = try? fm.contentsOfDirectory(atPath: path) else { return [] }
        var entries: [FileEntry] = []
        for name in names {
            let child = (path as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: child, isDirectory: &isDir), isDir.boolValue else { continue }
            let bytes = Shell.size(child)
            guard bytes > 0 else { continue }
            let label = projectName(in: child) ?? name
            entries.append(entry(
                path: child, name: label, kind: .contents, bytes: bytes
            ))
        }
        entries.sort { $0.sizeBytes > $1.sizeBytes }
        guard !entries.isEmpty else { return folderContentsFlat(path: path) }
        return [FileGroup(kind: .contents, entries: entries)]
    }

    private static func folderContentsFlat(path: String) -> [FileGroup] {
        let children = Shell.du(path, depth: 1).filter { $0.path != path && $0.bytes > 0 }
        let entries = children.map { child in
            entry(
                path: child.path,
                name: friendlyName(for: child.path) ?? (child.path as NSString).lastPathComponent,
                kind: .contents,
                bytes: child.bytes
            )
        }.sorted { $0.sizeBytes > $1.sizeBytes }
        guard !entries.isEmpty else { return [] }
        return [FileGroup(kind: .contents, entries: entries)]
    }

    private static func projectName(in derivedFolder: String) -> String? {
        let plist = (derivedFolder as NSString).appendingPathComponent("info.plist")
        guard let data = fm.contents(atPath: plist),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return dict["ProjectName"] as? String
            ?? dict["WorkspaceName"] as? String
    }

    /// VS Code extension folders — show displayName from package.json.
    private static func friendlyName(for path: String) -> String? {
        let pkg = (path as NSString).appendingPathComponent("package.json")
        guard let data = fm.contents(atPath: pkg),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if let display = json["displayName"] as? String, !display.isEmpty { return display }
        return json["name"] as? String
    }

    static func appIcon(for path: String) -> NSImage {
        NSWorkspace.shared.icon(forFile: path)
    }

    static func isProtected(_ bundleID: String) -> Bool {
        protectedPrefixes.contains { bundleID.hasPrefix($0) }
    }

    private static func bundleIdentifier(at appPath: String) -> String? {
        let plist = (appPath as NSString).appendingPathComponent("Contents/Info.plist")
        guard let data = fm.contents(atPath: plist),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return dict["CFBundleIdentifier"] as? String
    }

    private static func kindForBase(_ base: String) -> FileGroupKind {
        if base.hasSuffix("Caches") { return .caches }
        if base.hasSuffix("Logs") { return .logs }
        return .applicationSupport
    }
}
