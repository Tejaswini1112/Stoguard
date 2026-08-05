import Foundation

/// ponytail: Purge's probe — try listing three protected Library folders once.
/// Listing them without Full Disk Access is what triggers the per-folder TCC spam.
struct PermissionChecker {
    func hasFullDiskAccess() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let probes = [
            home.appendingPathComponent("Library/Safari", isDirectory: true),
            home.appendingPathComponent("Library/Containers", isDirectory: true),
            home.appendingPathComponent("Library/Application Support", isDirectory: true),
        ]
        for url in probes {
            do {
                _ = try FileManager.default.contentsOfDirectory(
                    at: url, includingPropertiesForKeys: nil,
                    options: [.skipsSubdirectoryDescendants]
                )
            } catch { return false }
        }
        return true
    }
}
