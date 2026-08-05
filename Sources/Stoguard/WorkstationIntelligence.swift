import Foundation

// MARK: - Health score

struct HealthDimension: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let score: Int // 0...100
    let detail: String
}

struct HealthReport: Sendable {
    let overall: Int
    let dimensions: [HealthDimension]
    let headline: String
    let generatedAt: Date
}

enum HealthScore {
    static func compute(
        items: [ScanItem],
        history: [ScanHistoryEntry],
        pulse: SystemPulse?,
        models: [AIModelEntry],
        env: [EnvFinding],
        prefs: PreferenceMemory
    ) -> HealthReport {
        let storage = storageScore(items: items, pulse: pulse)
        let performance = performanceScore(pulse: pulse, history: history, items: items)
        let security = securityScore(env: env, items: items)
        let ai = aiWorkspaceScore(models: models, items: items)
        let dims = [storage, performance, security, ai]
        let overall = dims.map(\.score).reduce(0, +) / max(1, dims.count)
        let headline: String
        switch overall {
        case 90...: headline = "Workstation looks healthy — keep light maintenance."
        case 75..<90: headline = "Solid machine with a few reclaim opportunities."
        case 55..<75: headline = "Pressure building — act on safe caches and idle AI models."
        default: headline = "Critical space/performance risk — clean and review now."
        }
        _ = prefs // reserved for future personalization of weights
        return HealthReport(overall: overall, dimensions: dims, headline: headline, generatedAt: Date())
    }

    private static func storageScore(items: [ScanItem], pulse: SystemPulse?) -> HealthDimension {
        let used = pulse?.diskUsedPercent ?? 0
        let safe = items.filter { $0.safety == .safe }.reduce(Int64(0)) { $0 + $1.sizeBytes }
        var score = 100
        if used > 95 { score -= 40 }
        else if used > 90 { score -= 28 }
        else if used > 80 { score -= 16 }
        else if used > 70 { score -= 8 }
        if safe > 20_000_000_000 { score -= 12 }
        else if safe > 5_000_000_000 { score -= 6 }
        score = min(100, max(5, score))
        return HealthDimension(
            id: "storage", name: "Storage",
            score: score,
            detail: String(format: "Disk ~%.0f%% used · %.1f GB safe to reclaim", used, Double(safe) / 1e9)
        )
    }

    private static func performanceScore(pulse: SystemPulse?, history: [ScanHistoryEntry], items: [ScanItem]) -> HealthDimension {
        var score = 88
        if let p = pulse {
            if p.cpuBusyPercent > 80 { score -= 15 }
            else if p.cpuBusyPercent > 60 { score -= 8 }
            if p.memoryUsedPercent > 90 { score -= 15 }
            else if p.memoryUsedPercent > 80 { score -= 8 }
            if p.diskUsedPercent > 90 { score -= 12 }
        }
        let derived = items.first { $0.name.localizedCaseInsensitiveContains("DerivedData") }?.sizeBytes ?? 0
        if derived > 30_000_000_000 { score -= 10 }
        else if derived > 10_000_000_000 { score -= 5 }
        if history.count >= 2 {
            let last = history[history.count - 1]
            let prev = history[history.count - 2]
            if last.freeBytes + 5_000_000_000 < prev.freeBytes { score -= 6 }
        }
        score = min(100, max(5, score))
        return HealthDimension(
            id: "performance", name: "Performance",
            score: score,
            detail: "CPU/RAM/disk pressure + build-cache weight (DerivedData/Gradle proxies)."
        )
    }

    private static func securityScore(env: [EnvFinding], items: [ScanItem]) -> HealthDimension {
        var score = 92
        let warnings = env.filter { $0.severity == .warn }.count
        score -= min(30, warnings * 6)
        let risky = items.filter { $0.safety == .never || $0.isLibraryProfileRisk }.count
        score -= min(15, risky * 3)
        score = min(100, max(20, score))
        return HealthDimension(
            id: "security", name: "Security",
            score: score,
            detail: "\(warnings) env warnings · \(risky) high-risk paths flagged."
        )
    }

    private static func aiWorkspaceScore(models: [AIModelEntry], items: [ScanItem]) -> HealthDimension {
        let modelBytes = models.reduce(Int64(0)) { $0 + $1.sizeBytes }
        let idle = models.filter { ($0.daysIdle ?? 0) >= 45 }.count
        var score = 90
        if modelBytes > 80_000_000_000 { score -= 20 }
        else if modelBytes > 30_000_000_000 { score -= 10 }
        score -= min(20, idle * 4)
        let aiCaches = items.filter { $0.category == "AI Tools" || $0.category == "AI Models" }
            .reduce(Int64(0)) { $0 + $1.sizeBytes }
        if aiCaches > 10_000_000_000 { score -= 8 }
        score = min(100, max(15, score))
        return HealthDimension(
            id: "ai", name: "AI Workspace",
            score: score,
            detail: String(format: "%.1f GB models · %d idle ≥45d", Double(modelBytes) / 1e9, idle)
        )
    }
}

// MARK: - Predictive insights

struct PredictiveInsight: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let body: String
    let severity: String // info | warn | critical
}

enum PredictiveEngine {
    static func insights(history: [ScanHistoryEntry], pulse: SystemPulse?, items: [ScanItem]) -> [PredictiveInsight] {
        var out: [PredictiveInsight] = []
        if let eta = diskFullETA(history: history, pulse: pulse) {
            out.append(eta)
        }
        out += growthInsights(history: history)
        out += hotspots(items: items)
        if out.isEmpty {
            out.append(PredictiveInsight(
                id: "need-history",
                title: "Need more scans for forecasts",
                body: "Run scans over a few days — Stoguard will project when your SSD fills and which categories are growing.",
                severity: "info"
            ))
        }
        return out
    }

    private static func diskFullETA(history: [ScanHistoryEntry], pulse: SystemPulse?) -> PredictiveInsight? {
        guard history.count >= 2, let pulse, pulse.diskTotalBytes > 0 else { return nil }
        let recent = Array(history.suffix(8))
        guard let first = recent.first, let last = recent.last else { return nil }
        let days = max(0.5, last.date.timeIntervalSince(first.date) / 86_400)
        let freeDelta = Double(first.freeBytes - last.freeBytes) // positive = losing free space
        guard freeDelta > 50_000_000 else {
            return PredictiveInsight(
                id: "disk-stable",
                title: "Disk usage looks stable",
                body: String(format: "Free space held roughly steady over %.0f days (%.1f GB free now).", days, Double(pulse.diskFreeBytes) / 1e9),
                severity: "info"
            )
        }
        let bytesPerDay = freeDelta / days
        guard bytesPerDay > 0 else { return nil }
        let daysTo95: Double = {
            let targetFree = Double(pulse.diskTotalBytes) * 0.05
            let need = Double(pulse.diskFreeBytes) - targetFree
            guard need > 0 else { return 0 }
            return need / bytesPerDay
        }()
        let severity = daysTo95 < 14 ? "critical" : (daysTo95 < 45 ? "warn" : "info")
        return PredictiveInsight(
            id: "disk-eta",
            title: String(format: "SSD may hit 95%% in ~%.0f days", max(1, daysTo95)),
            body: String(
                format: "Based on %.1f GB/day free-space loss over the last %.0f days. At this pace, reclaim safe caches before you hit the performance cliff.",
                bytesPerDay / 1e9, days
            ),
            severity: severity
        )
    }

    private static func growthInsights(history: [ScanHistoryEntry]) -> [PredictiveInsight] {
        guard history.count >= 2 else { return [] }
        let last = history[history.count - 1]
        let prev = history[history.count - 2]
        let days = max(0.5, last.date.timeIntervalSince(prev.date) / 86_400)
        var best: (String, Int64)?
        for (cat, bytes) in last.categoryTotals {
            let before = prev.categoryTotals[cat] ?? 0
            let delta = bytes - before
            if best == nil || delta > best!.1 { best = (cat, delta) }
        }
        guard let best, best.1 > 200_000_000 else { return [] }
        return [PredictiveInsight(
            id: "growth-\(best.0)",
            title: "\(best.0) grew \(ByteText.string(best.1))",
            body: String(format: "Largest category growth since last scan (~%.1f days). Review that section first.", days),
            severity: best.1 > 5_000_000_000 ? "warn" : "info"
        )]
    }

    private static func hotspots(items: [ScanItem]) -> [PredictiveInsight] {
        guard let top = items.sorted(by: { $0.sizeBytes > $1.sizeBytes }).first, top.sizeBytes > 5_000_000_000 else { return [] }
        return [PredictiveInsight(
            id: "hotspot-\(top.id)",
            title: "\(top.name) is your largest hotspot",
            body: "\(ByteText.string(top.sizeBytes)) · \(top.note)",
            severity: top.safety == .safe ? "info" : "warn"
        )]
    }
}

// MARK: - Preference memory (learns keep vs clean habits)

struct PreferenceMemory: Codable, Sendable {
    struct Stat: Codable, Hashable, Sendable {
        var keepCount: Int = 0
        var cleanCount: Int = 0
        var lastAction: String? // keep | clean
        var lastAt: Date?
    }

    var byKey: [String: Stat] = [:]

    private static var fileURL: URL {
        SupportPaths.directory.appendingPathComponent("preference-memory.json")
    }

    static func load() -> PreferenceMemory {
        guard let data = try? Data(contentsOf: fileURL) else { return PreferenceMemory() }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode(PreferenceMemory.self, from: data)) ?? PreferenceMemory()
    }

    mutating func recordKeep(key: String) {
        var s = byKey[key] ?? Stat()
        s.keepCount += 1
        s.lastAction = "keep"
        s.lastAt = Date()
        byKey[key] = s
        save()
    }

    mutating func recordClean(key: String) {
        var s = byKey[key] ?? Stat()
        s.cleanCount += 1
        s.lastAction = "clean"
        s.lastAt = Date()
        byKey[key] = s
        save()
    }

    func shouldDeprioritize(_ key: String) -> Bool {
        guard let s = byKey[key] else { return false }
        return s.keepCount >= 2 && s.keepCount > s.cleanCount
    }

    func shouldPrioritize(_ key: String) -> Bool {
        guard let s = byKey[key] else { return false }
        return s.cleanCount >= 2 && s.cleanCount > s.keepCount
    }

    func note(for key: String) -> String? {
        guard let s = byKey[key] else { return nil }
        if shouldDeprioritize(key) {
            return "You usually keep this — recommendation deprioritized."
        }
        if shouldPrioritize(key) {
            return "You usually clean this — prioritized."
        }
        if s.keepCount + s.cleanCount > 0 {
            return "Memory: kept \(s.keepCount)× · cleaned \(s.cleanCount)×"
        }
        return nil
    }

    func save() {
        SupportPaths.ensureDirectory()
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(self) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }

    static func key(for item: ScanItem) -> String {
        item.id
    }
}

// MARK: - Automation rules

struct AutomationRule: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var enabled: Bool
    /// sunday | daily | weekly
    var schedule: String
    /// safeCaches | npmCache | scanOnly
    var action: String
    var minBytes: Int64
    var lastRun: Date?
}

struct AutomationStore: Codable, Sendable {
    var rules: [AutomationRule] = []
    var cloudOptIn: Bool = false

    private static var fileURL: URL {
        SupportPaths.directory.appendingPathComponent("automation.json")
    }

    static func load() -> AutomationStore {
        guard let data = try? Data(contentsOf: fileURL) else {
            return AutomationStore(rules: Self.defaults, cloudOptIn: false)
        }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode(AutomationStore.self, from: data)) ?? AutomationStore(rules: Self.defaults, cloudOptIn: false)
    }

    static let defaults: [AutomationRule] = [
        AutomationRule(id: "sunday-safe", name: "Sunday safe-cache tidy", enabled: false, schedule: "sunday", action: "safeCaches", minBytes: 1_000_000_000, lastRun: nil),
        AutomationRule(id: "npm-5gb", name: "npm cache if > 5 GB", enabled: false, schedule: "weekly", action: "npmCache", minBytes: 5_000_000_000, lastRun: nil),
        AutomationRule(id: "daily-scan", name: "Daily background scan", enabled: true, schedule: "daily", action: "scanOnly", minBytes: 0, lastRun: nil),
    ]

    mutating func save() {
        SupportPaths.ensureDirectory()
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(self) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }
}

// MARK: - Proactive alerts (background → explain → recommend)

struct ProactiveAlert: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let explanation: String
    let recommendation: String
    let severity: String
    let relatedSection: AppSection?
}

enum ProactiveEngine {
    static func evaluate(
        items: [ScanItem],
        history: [ScanHistoryEntry],
        pulse: SystemPulse?,
        prefs: PreferenceMemory
    ) -> [ProactiveAlert] {
        var alerts: [ProactiveAlert] = []
        if let pulse, pulse.diskUsedPercent >= 92 {
            alerts.append(ProactiveAlert(
                id: "disk-critical",
                title: "Disk critically full",
                explanation: String(format: "Your volume is %.0f%% full. macOS slows sharply near capacity (swap, Photos, Spotlight).", pulse.diskUsedPercent),
                recommendation: "Clean safe caches first, then review Docker / AI models.",
                severity: "critical",
                relatedSection: .doctor
            ))
        }
        for item in items.sorted(by: { $0.sizeBytes > $1.sizeBytes }).prefix(8) {
            let key = PreferenceMemory.key(for: item)
            if prefs.shouldDeprioritize(key) { continue }
            if item.safety == .safe && item.sizeBytes > 2_000_000_000 {
                alerts.append(ProactiveAlert(
                    id: "safe-\(item.id)",
                    title: "\(item.name) can free \(item.sizeText)",
                    explanation: item.note,
                    recommendation: prefs.shouldPrioritize(key)
                        ? "You usually clean this — move to Trash when ready."
                        : "Safe to Trash; regenerates on next use.",
                    severity: "info",
                    relatedSection: AppSection.section(forCategory: item.category)
                ))
            }
        }
        if history.count >= 2 {
            let last = history[history.count - 1]
            let prev = history[history.count - 2]
            for (cat, bytes) in last.categoryTotals {
                let delta = bytes - (prev.categoryTotals[cat] ?? 0)
                if delta > 3_000_000_000 {
                    let days = max(1, Int(last.date.timeIntervalSince(prev.date) / 86_400))
                    alerts.append(ProactiveAlert(
                        id: "grow-\(cat)",
                        title: "\(cat) grew \(ByteText.string(delta)) in \(days)d",
                        explanation: "Repeated builds or downloads often cause this (images, DerivedData, model pulls).",
                        recommendation: "Open \(cat) and review the largest folders.",
                        severity: "warn",
                        relatedSection: AppSection.section(forCategory: cat)
                    ))
                }
            }
        }
        return Array(alerts.prefix(12))
    }
}

// MARK: - Learning center articles

struct LearningArticle: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let category: String
    let what: String
    let whyCreated: String
    let whySafe: String
    let whenDelete: String
    let afterDelete: String
}

enum LearningCenter {
    static let articles: [LearningArticle] = [
        LearningArticle(
            id: "deriveddata", title: "DerivedData", category: "Xcode",
            what: "Xcode’s build products, indexes, and module caches for your projects.",
            whyCreated: "Speeds up incremental compiles by reusing compiled artifacts and indexes.",
            whySafe: "Xcode regenerates it on the next build — source code is never stored only there.",
            whenDelete: "When it’s huge, builds act weird, or you’re short on disk after finishing a project.",
            afterDelete: "The next build is slower (cold compile), then speeds up again."
        ),
        LearningArticle(
            id: "docker", title: "Docker disk image", category: "Containers",
            what: "A virtual disk holding images, containers, build cache, and volumes.",
            whyCreated: "Docker Desktop keeps a persistent VM disk so containers start quickly.",
            whySafe: "Pruning unused images doesn’t delete your Dockerfiles or source repos.",
            whenDelete: "When unused images/volumes pile up after many rebuilds.",
            afterDelete: "Next `docker pull` / build re-downloads layers — projects stay intact."
        ),
        LearningArticle(
            id: "npm-cache", title: "npm cache", category: "Packages",
            what: "Downloaded package tarballs npm keeps for faster reinstalls.",
            whyCreated: "Avoids re-downloading the same versions across projects.",
            whySafe: "Fully rebuildable with `npm install`.",
            whenDelete: "When the cache is multi‑GB and you’re not installing packages constantly.",
            afterDelete: "Next installs are slower until the cache refills."
        ),
        LearningArticle(
            id: "ollama", title: "Ollama models", category: "AI",
            what: "Local LLM weights Ollama downloaded for offline inference.",
            whyCreated: "So you can run models without calling a cloud API.",
            whySafe: "Deleting a model doesn’t remove Ollama itself — only that weight file.",
            whenDelete: "When a model is idle for weeks and you need disk back.",
            afterDelete: "You must `ollama pull` again to use that model."
        ),
        LearningArticle(
            id: "huggingface", title: "Hugging Face cache", category: "AI",
            what: "Model and dataset blobs cached under ~/.cache/huggingface.",
            whyCreated: "Libraries re-use downloads across Python projects.",
            whySafe: "Re-downloaded on next use; your training code stays put.",
            whenDelete: "When old experiment models linger unused.",
            afterDelete: "First run after delete re-fetches weights (network + time)."
        ),
        LearningArticle(
            id: "gradle", title: "Gradle caches", category: "Android/JVM",
            what: "Downloaded dependencies and transform caches for Gradle builds.",
            whyCreated: "Keeps Android/JVM builds from re-fetching the internet every time.",
            whySafe: "Gradle refills caches on the next build.",
            whenDelete: "After SDK upgrades or when caches exceed tens of GB.",
            afterDelete: "Next build re-downloads dependencies — longer cold build."
        ),
    ]

    static func article(matching query: String) -> LearningArticle? {
        let q = query.lowercased()
        return articles.first { a in
            q.contains(a.id) || q.contains(a.title.lowercased()) || a.title.lowercased().split(separator: " ").contains { q.contains($0) }
        }
    }
}

// MARK: - Cloud intelligence (opt-in anonymous benchmarks)

struct CloudBenchmark: Identifiable, Hashable, Sendable {
    let id: String
    let cohort: String
    let averageBytes: Int64
    let yourBytes: Int64
    let recommendation: String

    var yourVsAvgText: String {
        if yourBytes > averageBytes {
            return "Your cache is \(ByteText.string(yourBytes - averageBytes)) above the anonymous cohort average."
        }
        return "You’re at or below the cohort average."
    }
}

enum CloudIntelligence {
    /// Local synthetic benchmarks until a real opt-in endpoint exists.
    static func benchmarks(items: [ScanItem], optIn: Bool) -> [CloudBenchmark] {
        guard optIn else { return [] }
        let cohorts: [(String, String, Int64)] = [
            ("flutter", "Flutter", 9_000_000_000),
            ("docker", "Docker", 15_000_000_000),
            ("npm", "npm", 2_000_000_000),
            ("ollama", "Ollama", 12_000_000_000),
            ("derived", "Xcode DerivedData", 8_000_000_000),
        ]
        return cohorts.compactMap { key, label, avg in
            let yours = items.filter {
                $0.name.localizedCaseInsensitiveContains(key)
                    || $0.path.localizedCaseInsensitiveContains(key)
                    || $0.category.localizedCaseInsensitiveContains(label)
            }.reduce(Int64(0)) { $0 + $1.sizeBytes }
            guard yours > 0 else { return nil }
            let rec = yours > avg * 2 ? "Clean or archive — you’re well above peers." : "Within a normal range for this cohort."
            return CloudBenchmark(id: key, cohort: label, averageBytes: avg, yourBytes: yours, recommendation: rec)
        }
    }
}

// MARK: - AI model management helpers

enum AIModelOps {
    static func archiveAdvice(for model: AIModelEntry) -> String {
        """
        Archive / free space options for \(model.provider) · \(model.name):
        • Move the folder to an external drive, then symlink back if needed.
        • Or Trash it (\(ByteText.string(model.sizeBytes))) — \(model.removeHint)
        Idle: \(model.daysIdle.map { "\($0) days" } ?? "unknown").
        """
    }

    static func duplicatesSummary(models: [AIModelEntry]) -> String {
        let byName = Dictionary(grouping: models, by: { $0.name.lowercased() })
        let dups = byName.filter { $0.value.count > 1 }
        if dups.isEmpty { return "No obvious duplicate model names across providers." }
        return dups.map { "• \($0.key): \($0.value.count) copies across \(Set($0.value.map(\.provider)).joined(separator: ", "))" }
            .joined(separator: "\n")
    }
}

// MARK: - Repository intelligence (deeper)

struct RepoInsight: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let detail: String
    let bytes: Int64
    let kind: String
}

enum RepoIntelligence {
    static func analyze(root: String) -> (total: Int64, insights: [RepoInsight]) {
        let fm = FileManager.default
        let expanded = PathUtil.expand(root)
        guard fm.fileExists(atPath: expanded) else { return (0, []) }
        let total = Shell.size(expanded)
        var insights: [RepoInsight] = []

        let heavyNames = ["node_modules", "Pods", ".gradle", "build", "dist", "DerivedData", ".next", "vendor", "__pycache__", ".venv", "venv"]
        for name in heavyNames {
            let path = (expanded as NSString).appendingPathComponent(name)
            if fm.fileExists(atPath: path) {
                let sz = Shell.size(path)
                if sz > 20_000_000 {
                    insights.append(RepoInsight(
                        id: "heavy-\(name)", title: name, detail: "Dependency/build artifact folder",
                        bytes: sz, kind: "heavy"
                    ))
                }
            }
        }

        // Large media / binaries (shallow)
        if let kids = try? fm.contentsOfDirectory(atPath: expanded) {
            for name in kids.prefix(80) {
                let path = (expanded as NSString).appendingPathComponent(name)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: path, isDirectory: &isDir) else { continue }
                let ext = (name as NSString).pathExtension.lowercased()
                if ["png", "jpg", "jpeg", "gif", "mp4", "mov", "psd", "zip", "dmg", "jar", "wasm"].contains(ext) {
                    let sz = Shell.size(path)
                    if sz > 5_000_000 {
                        insights.append(RepoInsight(
                            id: "bin-\(name)", title: name,
                            detail: "Large binary/media — consider Git LFS or external storage",
                            bytes: sz, kind: "binary"
                        ))
                    }
                }
            }
        }

        insights.sort { $0.bytes > $1.bytes }
        return (total, Array(insights.prefix(40)))
    }
}
