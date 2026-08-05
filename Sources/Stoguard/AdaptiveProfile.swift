import Foundation

/// Learns which rule paths never exist on this Mac and skips them after repeated misses.
struct AdaptiveProfile: Codable, Sendable {
    /// Consecutive scans where the path was missing.
    var missStreak: [String: Int] = [:]
    /// Rule IDs the user (or auto-profile) wants permanently skipped.
    var skippedRuleIDs: Set<String> = []
    var scanCount: Int = 0

    static let autoSkipAfterMisses = 5

    private static var fileURL: URL {
        SupportPaths.directory.appendingPathComponent("adaptive-profile.json")
    }

    static func load() -> AdaptiveProfile {
        guard let data = try? Data(contentsOf: fileURL),
              let profile = try? JSONDecoder().decode(AdaptiveProfile.self, from: data)
        else { return AdaptiveProfile() }
        return profile
    }

    func save() {
        SupportPaths.ensureDirectory()
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(self) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }

    func shouldScan(ruleID: String) -> Bool {
        if skippedRuleIDs.contains(ruleID) { return false }
        return (missStreak[ruleID] ?? 0) < Self.autoSkipAfterMisses
    }

    mutating func recordHit(ruleID: String) {
        missStreak[ruleID] = 0
        skippedRuleIDs.remove(ruleID)
    }

    mutating func recordMiss(ruleID: String) {
        let next = (missStreak[ruleID] ?? 0) + 1
        missStreak[ruleID] = next
        if next >= Self.autoSkipAfterMisses {
            skippedRuleIDs.insert(ruleID)
        }
    }

    mutating func beginScan() {
        scanCount += 1
    }

    var autoSkippedCount: Int { skippedRuleIDs.count }

    mutating func resetSkips() {
        skippedRuleIDs = []
        missStreak = [:]
    }
}
