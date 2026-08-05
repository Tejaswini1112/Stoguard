import Foundation
import AppKit

struct TrashItem: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    let sizeBytes: Int64
    let kind: String
    let isDirectory: Bool
    let dateAdded: Date?

    var sizeText: String { ByteText.string(sizeBytes) }
}

struct TrashRestoreOutcome: Equatable {
    let restored: Int
    let failed: Int
    let automationDenied: Bool

    var message: String? {
        guard failed > 0 else { return nil }
        if automationDenied {
            return "Put Back needs Automation permission for Finder. Open System Settings → Privacy & Security → Automation, allow Stoguard to control Finder, then try again."
        }
        if restored > 0 {
            return "\(restored) restored, \(failed) could not be put back. Items deleted outside Finder may not have a saved original location."
        }
        return "Could not put back the selected items. If Stoguard moved them to Trash before this update, the original path was not recorded. Use Finder’s Put Back, or restore manually from ~/.Trash."
    }
}

/// Reads and manages the macOS user Trash (~/.Trash).
enum TrashScanner {
    private nonisolated(unsafe) static let fm = FileManager.default

    static var trashDirectory: String {
        fm.homeDirectoryForCurrentUser.appendingPathComponent(".Trash").path
    }

    static func listItems() -> [TrashItem] {
        let dir = trashDirectory
        guard let names = try? fm.contentsOfDirectory(atPath: dir) else { return [] }
        return names.compactMap { name in
            let path = (dir as NSString).appendingPathComponent(name)
            return item(at: path)
        }.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    static func totalBytes(in items: [TrashItem]) -> Int64 {
        items.reduce(0) { $0 + $1.sizeBytes }
    }

    @discardableResult
    static func permanentlyDelete(paths: [String]) -> Int64 {
        var reclaimed: Int64 = 0
        for path in paths {
            let bytes = Shell.size(path)
            do {
                try fm.removeItem(atPath: path)
                TrashOriginStore.remove(trashedPath: path)
                reclaimed += bytes
            } catch { /* skip locked items */ }
        }
        return reclaimed
    }

    /// Restore trashed items — Stoguard-recorded origins first, then Finder Put Back.
    static func restore(paths: [String]) async -> TrashRestoreOutcome {
        var restored = 0
        var failed = 0
        var automationDenied = false

        for path in paths {
            if restoreToRecordedOrigin(trashedPath: path) {
                restored += 1
                continue
            }
            let finder = await restoreViaFinder(trashedPath: path)
            switch finder {
            case .success:
                restored += 1
                TrashOriginStore.remove(trashedPath: path)
            case .automationDenied:
                failed += 1
                automationDenied = true
            case .failed:
                failed += 1
            }
        }

        return TrashRestoreOutcome(restored: restored, failed: failed, automationDenied: automationDenied)
    }

    // MARK: - Restore strategies

    private static func restoreToRecordedOrigin(trashedPath: String) -> Bool {
        guard fm.fileExists(atPath: trashedPath) else { return false }
        guard let original = TrashOriginStore.originalPath(forTrashedPath: trashedPath)
                ?? guessOriginalFromRules(trashedPath: trashedPath) else { return false }

        let destination = availableDestination(for: original)
        let parent = (destination as NSString).deletingLastPathComponent
        if !fm.fileExists(atPath: parent) {
            try? fm.createDirectory(atPath: parent, withIntermediateDirectories: true)
        }

        do {
            try fm.moveItem(atPath: trashedPath, toPath: destination)
            TrashOriginStore.remove(trashedPath: trashedPath)
            return true
        } catch {
            return false
        }
    }

    private enum FinderRestoreResult {
        case success, failed, automationDenied
    }

    @MainActor
    private static func restoreViaFinder(trashedPath: String) -> FinderRestoreResult {
        guard fm.fileExists(atPath: trashedPath) else { return .failed }

        if !NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == "com.apple.finder" }) {
            NSWorkspace.shared.openApplication(
                at: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"),
                configuration: NSWorkspace.OpenConfiguration()
            ) { _, _ in }
        }

        let escaped = trashedPath
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Finder"
            set theItem to POSIX file "\(escaped)" as alias
            put back theItem
        end tell
        """
        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else { return .failed }
        appleScript.executeAndReturnError(&error)
        guard let error else { return .success }

        let code = error[NSAppleScript.errorNumber] as? Int ?? 0
        // -1743 = not authorized to send Apple events to Finder
        if code == -1743 { return .automationDenied }
        return .failed
    }

    private static func availableDestination(for originalPath: String) -> String {
        guard fm.fileExists(atPath: originalPath) else { return originalPath }
        let dir = (originalPath as NSString).deletingLastPathComponent
        let fullName = (originalPath as NSString).lastPathComponent
        let base = (fullName as NSString).deletingPathExtension
        let ext = (fullName as NSString).pathExtension
        var n = 1
        while n < 1000 {
            let name: String
            if ext.isEmpty {
                name = n == 1 ? "\(base) (restored)" : "\(base) (restored \(n))"
            } else {
                name = n == 1 ? "\(base) (restored).\(ext)" : "\(base) (restored \(n)).\(ext)"
            }
            let candidate = (dir as NSString).appendingPathComponent(name)
            if !fm.fileExists(atPath: candidate) { return candidate }
            n += 1
        }
        return originalPath
    }

    /// Fallback for items trashed before Stoguard recorded origins — match rules.json leaf names.
    private static func guessOriginalFromRules(trashedPath: String) -> String? {
        let name = (trashedPath as NSString).lastPathComponent
        for rule in Scanner.loadRules() {
            let expanded = PathUtil.expand(rule.path)
            if (expanded as NSString).lastPathComponent == name {
                return expanded
            }
        }
        return nil
    }

    // MARK: - Internals

    private static func item(at path: String) -> TrashItem? {
        guard fm.fileExists(atPath: path) else { return nil }
        var isDir: ObjCBool = false
        fm.fileExists(atPath: path, isDirectory: &isDir)
        let name = (path as NSString).lastPathComponent
        let bytes = Shell.size(path)
        let added = (try? fm.attributesOfItem(atPath: path)[.modificationDate]) as? Date
        return TrashItem(
            id: path,
            name: name,
            path: path,
            sizeBytes: bytes,
            kind: fileKind(path: path, isDirectory: isDir.boolValue),
            isDirectory: isDir.boolValue,
            dateAdded: added
        )
    }

    private static func fileKind(path: String, isDirectory: Bool) -> String {
        if isDirectory { return "Folder" }
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "PDF document"
        case "zip", "gz", "tar", "dmg": return "Archive"
        case "png", "jpg", "jpeg", "gif", "webp": return "Image"
        case "mp4", "mov", "mkv": return "Video"
        case "app": return "Application"
        default: return ext.isEmpty ? "Document" : "\(ext.uppercased()) file"
        }
    }
}
