import Foundation

// MARK: - History

struct ScanHistoryEntry: Codable, Identifiable, Sendable {
    var id: String { "\(date.timeIntervalSince1970)" }
    let date: Date
    let freeBytes: Int64
    let totalBytes: Int64
    let reclaimableSafe: Int64
    let categoryTotals: [String: Int64]
    let topItemIDs: [String]
}

struct ScanHistoryStore: Codable, Sendable {
    var entries: [ScanHistoryEntry] = []

    private static let maxEntries = 60
    private static var fileURL: URL {
        SupportPaths.directory.appendingPathComponent("scan-history.json")
    }

    static func load() -> ScanHistoryStore {
        guard let data = try? Data(contentsOf: fileURL) else { return ScanHistoryStore() }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode(ScanHistoryStore.self, from: data)) ?? ScanHistoryStore()
    }

    mutating func append(_ entry: ScanHistoryEntry) {
        entries.append(entry)
        if entries.count > Self.maxEntries {
            entries = Array(entries.suffix(Self.maxEntries))
        }
        save()
    }

    func save() {
        SupportPaths.ensureDirectory()
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(self) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }
}

// MARK: - Doctor models

struct LargeChild: Identifiable, Hashable, Sendable {
    var id: String { path }
    let name: String
    let path: String
    let sizeBytes: Int64

    var sizeText: String { ByteText.string(sizeBytes) }
}

enum DoctorActionKind: String, Sendable {
    case trashSafe
    case review
    case runCommand
    case info
}

struct DoctorRecommendation: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    /// Plain-English explanation of the term / why it matters.
    let explanation: String
    let advice: String
    let bytes: Int64
    let daysUnused: Int?
    let action: DoctorActionKind
    let relatedItemID: String?
    let command: String?

    var bytesText: String { ByteText.string(bytes) }
}

struct DoctorGrowthInsight: Identifiable, Hashable, Sendable {
    let id: String
    let category: String
    let deltaBytes: Int64
    let detail: String

    var deltaText: String {
        let sign = deltaBytes >= 0 ? "+" : "−"
        return "\(sign)\(ByteText.string(abs(deltaBytes)))"
    }
}

struct DoctorReport: Sendable {
    let generatedAt: Date
    let headline: String
    let summaryLines: [String]
    let reclaimableSafe: Int64
    let reclaimableCheck: Int64
    let recommendations: [DoctorRecommendation]
    let growth: [DoctorGrowthInsight]
    let timeline: [ScanHistoryEntry]
    let skippedRules: Int
    let cacheHits: Int

    static let empty = DoctorReport(
        generatedAt: Date(),
        headline: "Run a scan to diagnose your workstation.",
        summaryLines: [
            "Stoguard measures developer caches, explains what each folder is, and only moves files to Trash after you confirm.",
        ],
        reclaimableSafe: 0,
        reclaimableCheck: 0,
        recommendations: [],
        growth: [],
        timeline: [],
        skippedRules: 0,
        cacheHits: 0
    )
}

// MARK: - Builder

enum DoctorEngine {
    static let unusedDaysThreshold = 45

    static func build(
        items: [ScanItem],
        history: [ScanHistoryEntry],
        freeBytes: Int64,
        totalBytes: Int64,
        skippedRules: Int,
        cacheHits: Int
    ) -> DoctorReport {
        let safe = items.filter { $0.safety == .safe }.reduce(Int64(0)) { $0 + $1.sizeBytes }
        let check = items.filter { $0.safety == .check || $0.safety == .command }
            .reduce(Int64(0)) { $0 + $1.sizeBytes }

        let recommendations = makeRecommendations(from: items)
        let growth = makeGrowth(items: items, history: history)
        let summary = makeSummary(
            items: items,
            safe: safe,
            check: check,
            freeBytes: freeBytes,
            totalBytes: totalBytes,
            growth: growth,
            recommendations: recommendations
        )

        let headline: String = {
            if safe + check == 0 {
                return "Workstation looks lean."
            }
            if safe > 0 {
                return "\(ByteText.string(safe)) looks safe to reclaim."
            }
            return "\(ByteText.string(check)) needs a quick review."
        }()

        return DoctorReport(
            generatedAt: Date(),
            headline: headline,
            summaryLines: summary,
            reclaimableSafe: safe,
            reclaimableCheck: check,
            recommendations: recommendations,
            growth: growth,
            timeline: Array(history.suffix(14)),
            skippedRules: skippedRules,
            cacheHits: cacheHits
        )
    }

    static func historyEntry(
        items: [ScanItem],
        freeBytes: Int64,
        totalBytes: Int64
    ) -> ScanHistoryEntry {
        var totals: [String: Int64] = [:]
        for item in items {
            totals[item.category, default: 0] += item.sizeBytes
        }
        let top = items.sorted { $0.sizeBytes > $1.sizeBytes }.prefix(8).map(\.id)
        let safe = items.filter { $0.safety == .safe }.reduce(Int64(0)) { $0 + $1.sizeBytes }
        return ScanHistoryEntry(
            date: Date(),
            freeBytes: freeBytes,
            totalBytes: totalBytes,
            reclaimableSafe: safe,
            categoryTotals: totals,
            topItemIDs: Array(top)
        )
    }

    // MARK: Private

    private static func makeRecommendations(from items: [ScanItem]) -> [DoctorRecommendation] {
        var recs: [DoctorRecommendation] = []
        let sorted = items.sorted { $0.sizeBytes > $1.sizeBytes }

        for item in sorted.prefix(40) {
            let days = item.daysSinceActivity
            let unused = days.map { $0 >= unusedDaysThreshold } ?? false

            if unused && item.sizeBytes >= 50_000_000 {
                let d = days ?? unusedDaysThreshold
                recs.append(DoctorRecommendation(
                    id: "unused-\(item.id)",
                    title: "\(item.name) looks unused",
                    explanation: explain(item),
                    advice: "Last activity about \(d) days ago. \(item.safety == .safe ? "Safe to move to Trash." : item.safety == .command ? "Prefer the recommended CLI rather than deleting the folder." : "Review before removing.")",
                    bytes: item.sizeBytes,
                    daysUnused: d,
                    action: actionKind(for: item),
                    relatedItemID: item.id,
                    command: item.command
                ))
            } else if item.safety == .safe && item.sizeBytes >= 200_000_000 {
                recs.append(DoctorRecommendation(
                    id: "safe-\(item.id)",
                    title: "\(item.name) can be cleared",
                    explanation: explain(item),
                    advice: "Marked safe — tools recreate this data when needed.",
                    bytes: item.sizeBytes,
                    daysUnused: days,
                    action: .trashSafe,
                    relatedItemID: item.id,
                    command: nil
                ))
            } else if item.safety == .command && item.sizeBytes >= 500_000_000 {
                recs.append(DoctorRecommendation(
                    id: "cmd-\(item.id)",
                    title: "Use the CLI for \(item.name)",
                    explanation: explain(item),
                    advice: "Deleting this folder by hand can corrupt tool state. Copy the suggested command instead.",
                    bytes: item.sizeBytes,
                    daysUnused: days,
                    action: .runCommand,
                    relatedItemID: item.id,
                    command: item.command
                ))
            }
        }

        // Deduplicate by related item, keep first (largest-first already).
        var seen = Set<String>()
        return recs.filter { rec in
            let key = rec.relatedItemID ?? rec.id
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }.prefix(12).map { $0 }
    }

    private static func makeGrowth(items: [ScanItem], history: [ScanHistoryEntry]) -> [DoctorGrowthInsight] {
        guard let previous = history.dropLast().last else { return [] }
        var current: [String: Int64] = [:]
        for item in items {
            current[item.category, default: 0] += item.sizeBytes
        }
        var insights: [DoctorGrowthInsight] = []
        let keys = Set(current.keys).union(previous.categoryTotals.keys)
        for key in keys {
            let now = current[key] ?? 0
            let then = previous.categoryTotals[key] ?? 0
            let delta = now - then
            guard abs(delta) >= 100_000_000 else { continue } // 100 MB
            let detail: String
            if delta > 0 {
                detail = "Grew since your last scan — often caches, images, or build products."
            } else {
                detail = "Shrank since your last scan — previous cleanup or tool prune likely helped."
            }
            insights.append(DoctorGrowthInsight(
                id: key,
                category: key,
                deltaBytes: delta,
                detail: detail
            ))
        }
        return insights.sorted { abs($0.deltaBytes) > abs($1.deltaBytes) }
    }

    private static func makeSummary(
        items: [ScanItem],
        safe: Int64,
        check: Int64,
        freeBytes: Int64,
        totalBytes: Int64,
        growth: [DoctorGrowthInsight],
        recommendations: [DoctorRecommendation]
    ) -> [String] {
        var lines: [String] = []
        if totalBytes > 0 {
            let used = totalBytes - freeBytes
            let pct = Int((Double(used) / Double(totalBytes)) * 100)
            lines.append("Disk is about \(pct)% full (\(ByteText.storage(freeBytes)) free of \(ByteText.storage(totalBytes))).")
        }

        if !items.isEmpty {
            lines.append("Found \(items.count) storage hotspots totaling \(ByteText.string(items.reduce(0) { $0 + $1.sizeBytes })).")
        }

        if safe > 0 {
            lines.append("\(ByteText.string(safe)) is labeled safe to clean — typically rebuildable caches.")
        }
        if check > 0 {
            lines.append("\(ByteText.string(check)) needs a check first (models, package stores, or CLI-managed data).")
        }

        if let topGrowth = growth.first(where: { $0.deltaBytes > 0 }) {
            let totalGrowth = growth.filter { $0.deltaBytes > 0 }.reduce(Int64(0)) { $0 + $1.deltaBytes }
            if totalGrowth > 0 {
                let share = Int((Double(topGrowth.deltaBytes) / Double(totalGrowth)) * 100)
                lines.append("\(share)% of recent growth came from \(topGrowth.category) (\(topGrowth.deltaText)).")
            }
        }

        let unused = recommendations.filter { ($0.daysUnused ?? 0) >= unusedDaysThreshold }
        if let first = unused.first, let days = first.daysUnused {
            lines.append("Example: \(first.title.replacingOccurrences(of: " looks unused", with: "")) — idle ~\(days) days.")
        }

        if lines.isEmpty {
            lines.append("Scan your Mac to get a plain-English workstation report.")
        }
        return lines
    }

    private static func actionKind(for item: ScanItem) -> DoctorActionKind {
        switch item.safety {
        case .safe: return .trashSafe
        case .command: return .runCommand
        case .check: return .review
        case .never: return .info
        }
    }

    private static func explain(_ item: ScanItem) -> String {
        TermGlossary.explain(item: item)
    }

    private static func glossaryHint(for item: ScanItem) -> String {
        TermGlossary.shortLabel(for: item)
    }
}
