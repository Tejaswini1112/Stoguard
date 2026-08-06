import Foundation

// MARK: - Enterprise machine identity

enum EnterpriseIdentity {
    private static let key = "stoguard.machineId"

    static var machineID: String {
        if let existing = UserDefaults.standard.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let id = UUID().uuidString.lowercased()
        UserDefaults.standard.set(id, forKey: key)
        return id
    }
}

// MARK: - Unified enterprise / fleet report (shared schema with Go)

struct EnterpriseReport: Codable, Identifiable, Hashable, Sendable {
    var id: String { machineID }
    var schemaVersion: String = "2.0"
    var machineID: String
    var hostname: String
    var platform: String
    var arch: String
    var appVersion: String
    var scannedAt: Date
    var freeBytes: Int64
    var totalBytes: Int64
    var reclaimable: Int64
    var safeBytes: Int64
    var checkBytes: Int64
    var itemCount: Int
    var topCategories: [CategoryBytes]
    var topItems: [FleetItem]
    var envWarnings: [String]
    var duplicateWasteBytes: Int64
    var healthScore: Int?
    var compliance: ComplianceSnapshot?
    var aiModels: [AIModelInventoryEntry]
    var licenses: [LicenseEntry]
    var cohortMetrics: [String: Int64]

    struct CategoryBytes: Codable, Hashable, Sendable {
        var category: String
        var bytes: Int64
    }

    struct FleetItem: Codable, Hashable, Sendable {
        var id: String
        var name: String
        var category: String
        var bytes: Int64
        var safety: String
    }

    struct AIModelInventoryEntry: Codable, Hashable, Sendable {
        var provider: String
        var name: String
        var bytes: Int64
        var daysIdle: Int?
    }

    struct LicenseEntry: Codable, Hashable, Sendable {
        var product: String
        var path: String
        var note: String
    }
}

struct ComplianceSnapshot: Codable, Hashable, Sendable {
    var score: Int
    var passed: [String]
    var failed: [String]
    var baseline: String
}

struct FleetMachineRecord: Identifiable, Hashable, Sendable {
    var id: String { report.machineID }
    var report: EnterpriseReport

    var reclaimable: Int64 { report.reclaimable }
    var hostname: String { report.hostname }
    var platform: String { report.platform }
}

enum ComplianceEngine {
    static let baselineName = "Stoguard Developer Baseline v1"

    static func evaluate(
        free: Int64,
        total: Int64,
        env: [EnvFinding],
        reclaimableSafe: Int64,
        models: [AIModelEntry],
        secretsCount: Int = 0
    ) -> ComplianceSnapshot {
        var passed: [String] = []
        var failed: [String] = []

        let usedPct = total > 0 ? Double(total - free) / Double(total) * 100 : 0
        if usedPct < 90 {
            passed.append("Disk under 90% used")
        } else {
            failed.append(String(format: "Disk %.0f%% full (limit 90%%)", usedPct))
        }

        let warns = env.filter { $0.severity == .warn }.count
        if warns == 0 {
            passed.append("No Env Doctor warnings")
        } else {
            failed.append("\(warns) Env Doctor warning(s)")
        }

        if reclaimableSafe < 20_000_000_000 {
            passed.append("Safe reclaimable under 20 GB")
        } else {
            failed.append("Safe reclaimable \(ByteText.string(reclaimableSafe)) exceeds 20 GB policy")
        }

        let idleModels = models.filter { ($0.daysIdle ?? 0) >= 90 && $0.sizeBytes > 5_000_000_000 }.count
        if idleModels == 0 {
            passed.append("No huge idle AI models (≥90d)")
        } else {
            failed.append("\(idleModels) idle AI model store(s) ≥90 days")
        }

        if secretsCount == 0 {
            passed.append("No secrets findings in last repo scan (or not scanned)")
        } else {
            failed.append("\(secretsCount) potential secret(s) in last repo scan")
        }

        let totalChecks = passed.count + failed.count
        let score = totalChecks == 0 ? 100 : Int(Double(passed.count) / Double(totalChecks) * 100)
        return ComplianceSnapshot(score: score, passed: passed, failed: failed, baseline: baselineName)
    }
}

enum LicenseInventory {
    /// Best-effort local license / seat markers (never uploads license keys).
    static func scan() -> [EnterpriseReport.LicenseEntry] {
        var out: [EnterpriseReport.LicenseEntry] = []
        let candidates: [(String, String, String)] = [
            ("JetBrains", PathUtil.expand("~/Library/Application Support/JetBrains"), "IDE license folder present"),
            ("Xcode", "/Applications/Xcode.app", "Xcode installed"),
            ("Docker Desktop", "/Applications/Docker.app", "Docker Desktop installed"),
            ("Unity", PathUtil.expand("~/Library/Unity"), "Unity support folder"),
            ("Android Studio", "/Applications/Android Studio.app", "Android Studio installed"),
            ("Stoguard Team", SupportPaths.directory.appendingPathComponent("license.json").path, "Local Stoguard license.json"),
        ]
        for (product, path, note) in candidates {
            if FileManager.default.fileExists(atPath: path) {
                out.append(.init(product: product, path: path, note: note))
            }
        }
        return out
    }
}

enum EnterpriseBuilder {
    static func build(
        items: [ScanItem],
        free: Int64,
        total: Int64,
        env: [EnvFinding],
        duplicates: [DuplicateGroup],
        models: [AIModelEntry],
        health: HealthReport?,
        secretsCount: Int = 0
    ) -> EnterpriseReport {
        var cats: [String: Int64] = [:]
        for i in items { cats[i.category, default: 0] += i.sizeBytes }
        let topCats = cats.sorted { $0.value > $1.value }.prefix(8).map {
            EnterpriseReport.CategoryBytes(category: $0.key, bytes: $0.value)
        }
        let safe = items.filter { $0.safety == .safe }.reduce(Int64(0)) { $0 + $1.sizeBytes }
        let check = items.filter { $0.safety == .check || $0.safety == .command }.reduce(Int64(0)) { $0 + $1.sizeBytes }
        let topItems = items.sorted { $0.sizeBytes > $1.sizeBytes }.prefix(25).map {
            EnterpriseReport.FleetItem(
                id: $0.id, name: $0.name, category: $0.category,
                bytes: $0.sizeBytes, safety: $0.safety.rawValue
            )
        }
        let compliance = ComplianceEngine.evaluate(
            free: free, total: total, env: env,
            reclaimableSafe: safe, models: models, secretsCount: secretsCount
        )
        let cohort = CohortMetrics.extract(from: items)
        let arch: String = {
            #if arch(arm64)
            return "arm64"
            #else
            return "x86_64"
            #endif
        }()
        return EnterpriseReport(
            machineID: EnterpriseIdentity.machineID,
            hostname: ProcessInfo.processInfo.hostName,
            platform: "macos",
            arch: arch,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.4.2",
            scannedAt: Date(),
            freeBytes: free,
            totalBytes: total,
            reclaimable: safe + check,
            safeBytes: safe,
            checkBytes: check,
            itemCount: items.count,
            topCategories: Array(topCats),
            topItems: Array(topItems),
            envWarnings: env.filter { $0.severity == .warn }.map(\.title),
            duplicateWasteBytes: duplicates.reduce(0) { $0 + $1.wasteBytes },
            healthScore: health?.overall,
            compliance: compliance,
            aiModels: models.prefix(40).map {
                .init(provider: $0.provider, name: $0.name, bytes: $0.sizeBytes, daysIdle: $0.daysIdle)
            },
            licenses: LicenseInventory.scan(),
            cohortMetrics: cohort
        )
    }
}

// MARK: - Local fleet store (Team console on-device / shared folder)

enum FleetStore {
    static var directory: URL {
        SupportPaths.directory.appendingPathComponent("fleet", isDirectory: true)
    }

    static func ensure() {
        SupportPaths.ensureDirectory()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    static func ingest(_ report: EnterpriseReport) throws -> FleetMachineRecord {
        ensure()
        var r = report
        if r.machineID.isEmpty { r.machineID = EnterpriseIdentity.machineID }
        if r.hostname.isEmpty { r.hostname = ProcessInfo.processInfo.hostName }
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(r)
        let name = sanitize(r.machineID.isEmpty ? r.hostname : r.machineID) + ".json"
        try data.write(to: directory.appendingPathComponent(name), options: .atomic)
        // Also contribute anonymized cohort metrics when opted in.
        if AutomationStore.load().cloudOptIn {
            CohortStore.contribute(metrics: r.cohortMetrics, platform: r.platform)
        }
        return FleetMachineRecord(report: r)
    }

    static func list() -> [FleetMachineRecord] {
        ensure()
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []
        return urls.compactMap { url -> FleetMachineRecord? in
            guard url.pathExtension == "json",
                  let data = try? Data(contentsOf: url),
                  let report = try? dec.decode(EnterpriseReport.self, from: data)
            else { return nil }
            return FleetMachineRecord(report: report)
        }
        .sorted { $0.reclaimable > $1.reclaimable }
    }

    static func delete(machineID: String) {
        let name = sanitize(machineID) + ".json"
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
    }

    static func summary() -> FleetSummary {
        let machines = list()
        let reclaim = machines.reduce(Int64(0)) { $0 + $1.reclaimable }
        let byOS = Dictionary(grouping: machines, by: \.platform).mapValues(\.count)
        let nonCompliant = machines.filter { ($0.report.compliance?.score ?? 100) < 80 }.count
        return FleetSummary(
            machineCount: machines.count,
            totalReclaimable: reclaim,
            platforms: byOS,
            nonCompliantCount: nonCompliant,
            avgHealth: machines.isEmpty ? nil :
                machines.compactMap(\.report.healthScore).reduce(0, +) / max(1, machines.compactMap(\.report.healthScore).count)
        )
    }

    /// Push to a Team server (Go `:8787` with -bind and -api-key).
    static func pushRemote(report: EnterpriseReport, baseURL: URL, apiKey: String?) async throws {
        var req = URLRequest(url: baseURL.appendingPathComponent("api/fleet/ingest"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty {
            req.setValue(apiKey, forHTTPHeaderField: "X-Stoguard-Key")
        }
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        req.httpBody = try enc.encode(report)
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "FleetStore", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Remote ingest failed"
            ])
        }
    }

    private static func sanitize(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        return String(s.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
    }
}

struct FleetSummary: Hashable, Sendable {
    var machineCount: Int
    var totalReclaimable: Int64
    var platforms: [String: Int]
    var nonCompliantCount: Int
    var avgHealth: Int?
}

// MARK: - Cloud cohort knowledge (complete)

struct CloudBenchmark: Identifiable, Hashable, Sendable {
    let id: String
    let cohort: String
    let averageBytes: Int64
    let yourBytes: Int64
    let recommendation: String
    var source: String = "baseline" // baseline | fleet-peers | remote
    var sampleSize: Int? = nil
    var platform: String? = nil

    var yourVsAvgText: String {
        if yourBytes > averageBytes {
            return "Your cache is \(ByteText.string(yourBytes - averageBytes)) above the cohort average."
        }
        return "You’re at or below the cohort average."
    }
}

enum CohortMetrics {
    static let keys: [(id: String, label: String, match: [String])] = [
        ("docker", "Docker", ["docker", "container"]),
        ("deriveddata", "Xcode DerivedData", ["deriveddata", "derived data"]),
        ("npm", "npm cache", ["npm"]),
        ("ollama", "Ollama models", ["ollama"]),
        ("huggingface", "Hugging Face", ["hugging", "huggingface"]),
        ("gradle", "Gradle", ["gradle"]),
        ("flutter", "Flutter / pub-cache", ["flutter", "pub-cache", "pub cache"]),
        ("node_modules", "node_modules sprawl", ["node_modules"]),
        ("pip", "pip / Python caches", ["pip", "pycache", ".venv"]),
        ("cargo", "Cargo / Rust", ["cargo", "rustup"]),
        ("android-sdk", "Android SDK", ["android/sdk", "android sdk"]),
        ("downloads", "Downloads folder", ["downloads"]),
        ("wsl", "WSL / Linux distro data", ["wsl", "ext4.vhdx"]),
        ("nuget", "NuGet caches", ["nuget"]),
        ("flatpak", "Flatpak", ["flatpak"]),
    ]

    static func extract(from items: [ScanItem]) -> [String: Int64] {
        var out: [String: Int64] = [:]
        for key in keys {
            let sum = items.filter { item in
                let hay = (item.name + " " + item.path + " " + item.category).lowercased()
                return key.match.contains { hay.contains($0) }
            }.reduce(Int64(0)) { $0 + $1.sizeBytes }
            if sum > 0 { out[key.id] = sum }
        }
        // Always include Downloads if measurable.
        let dl = Shell.size(PathUtil.expand("~/Downloads"))
        if dl > 50_000_000 { out["downloads"] = dl }
        return out
    }

    static func label(for id: String) -> String {
        keys.first { $0.id == id }?.label ?? id
    }
}

/// Local peer contributions (from this machine + fleet ingest) — privacy-safe category bytes only.
enum CohortStore {
    struct Store: Codable {
        var samples: [Sample] = []
        struct Sample: Codable {
            var date: Date
            var platform: String
            var metrics: [String: Int64]
        }
    }

    private static var fileURL: URL {
        SupportPaths.directory.appendingPathComponent("cohort-contributions.json")
    }

    static func load() -> Store {
        guard let data = try? Data(contentsOf: fileURL) else { return Store() }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode(Store.self, from: data)) ?? Store()
    }

    static func contribute(metrics: [String: Int64], platform: String) {
        guard !metrics.isEmpty else { return }
        SupportPaths.ensureDirectory()
        var store = load()
        store.samples.append(.init(date: Date(), platform: platform, metrics: metrics))
        store.samples = Array(store.samples.suffix(500))
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(store) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static func peerAverages(platform: String? = nil) -> (avgs: [String: Int64], counts: [String: Int]) {
        let samples = load().samples.filter { platform == nil || $0.platform == platform }
        var sums: [String: Int64] = [:]
        var counts: [String: Int] = [:]
        for s in samples {
            for (k, v) in s.metrics where v > 0 {
                sums[k, default: 0] += v
                counts[k, default: 0] += 1
            }
        }
        var avgs: [String: Int64] = [:]
        for (k, sum) in sums {
            let c = max(1, counts[k] ?? 1)
            avgs[k] = sum / Int64(c)
        }
        return (avgs, counts)
    }
}

enum CloudIntelligence {
    /// Published baseline averages (anonymous industry estimates used until peers/remote exist).
    static let baselines: [String: Int64] = [
        "docker": 18_000_000_000,
        "deriveddata": 10_000_000_000,
        "npm": 2_500_000_000,
        "ollama": 14_000_000_000,
        "huggingface": 20_000_000_000,
        "gradle": 6_000_000_000,
        "flutter": 9_000_000_000,
        "node_modules": 4_000_000_000,
        "pip": 3_000_000_000,
        "cargo": 4_000_000_000,
        "android-sdk": 25_000_000_000,
        "downloads": 8_000_000_000,
        "wsl": 30_000_000_000,
        "nuget": 3_000_000_000,
        "flatpak": 5_000_000_000,
    ]

    static var cohortFeedURL: URL? {
        guard let s = UserDefaults.standard.string(forKey: "stoguard.cohortFeedURL"),
              let u = URL(string: s), !s.isEmpty else { return nil }
        return u
    }

    static var cohortContributeURL: URL? {
        guard let s = UserDefaults.standard.string(forKey: "stoguard.cohortContributeURL"),
              let u = URL(string: s), !s.isEmpty else { return nil }
        return u
    }

    static func setFeedURL(_ s: String?) {
        UserDefaults.standard.set(s, forKey: "stoguard.cohortFeedURL")
    }

    static func setContributeURL(_ s: String?) {
        UserDefaults.standard.set(s, forKey: "stoguard.cohortContributeURL")
    }

    static func benchmarks(items: [ScanItem], optIn: Bool, platform: String = "macos") -> [CloudBenchmark] {
        guard optIn else { return [] }
        let yours = CohortMetrics.extract(from: items)
        CohortStore.contribute(metrics: yours, platform: platform)

        let remote = loadCachedRemote()
        let peers = CohortStore.peerAverages()
        var out: [CloudBenchmark] = []

        for (id, yourBytes) in yours.sorted(by: { $0.value > $1.value }) {
            var avg = baselines[id] ?? yourBytes
            var source = "baseline"
            var samples: Int? = nil

            if let remoteAvg = remote?[id], remoteAvg > 0 {
                avg = remoteAvg
                source = "remote"
            } else if let peerAvg = peers.avgs[id], (peers.counts[id] ?? 0) >= 2 {
                avg = peerAvg
                source = "fleet-peers"
                samples = peers.counts[id]
            }

            let ratio = Double(yourBytes) / Double(max(1, avg))
            let rec: String
            if ratio >= 2.5 {
                rec = "Well above cohort — prioritize cleanup / archive for \(CohortMetrics.label(for: id))."
            } else if ratio >= 1.4 {
                rec = "Above average — good candidate when you need free space."
            } else if ratio <= 0.6 {
                rec = "Below cohort average — healthy relative to peers."
            } else {
                rec = "Within a normal range for this cohort."
            }

            out.append(CloudBenchmark(
                id: id,
                cohort: CohortMetrics.label(for: id),
                averageBytes: avg,
                yourBytes: yourBytes,
                recommendation: rec,
                source: source,
                sampleSize: samples,
                platform: platform
            ))
        }
        return out
    }

    /// Doctor-facing one-liners from cohorts.
    static func doctorHints(from benches: [CloudBenchmark]) -> [String] {
        benches.filter { Double($0.yourBytes) > Double($0.averageBytes) * 1.5 }.prefix(3).map {
            "\($0.cohort): you \(ByteText.string($0.yourBytes)) vs cohort \(ByteText.string($0.averageBytes)) (\($0.source))."
        }
    }

    static func refreshRemote(timeout: TimeInterval = 12) async -> String? {
        guard let url = cohortFeedURL else {
            return "No cohort feed URL — set stoguard.cohortFeedURL or use fleet-peer averages."
        }
        do {
            var req = URLRequest(url: url, timeoutInterval: timeout)
            req.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return "Cohort feed HTTP error"
            }
            // Expected: { "version":"1", "averages": { "docker": 18000000000, ... } }
            struct Feed: Codable {
                var version: String?
                var averages: [String: Int64]
            }
            let feed = try JSONDecoder().decode(Feed.self, from: data)
            try? data.write(to: cacheFile, options: .atomic)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "stoguard.cohortFetchedAt")
            return "Loaded \(feed.averages.count) cohort averages (v\(feed.version ?? "?"))"
        } catch {
            return error.localizedDescription
        }
    }

    static func contributeRemote(items: [ScanItem], platform: String = "macos") async -> String? {
        guard let url = cohortContributeURL else { return nil }
        let metrics = CohortMetrics.extract(from: items)
        // Anonymous payload — no hostname, paths, or machine ID.
        let body: [String: Any] = [
            "platform": platform,
            "metrics": metrics.mapValues { NSNumber(value: $0) },
            "schema": "stoguard-cohort-1",
        ]
        guard JSONSerialization.isValidJSONObject(body),
              let data = try? JSONSerialization.data(withJSONObject: body) else { return "encode failed" }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return "contribute HTTP error"
            }
            return "Anonymous metrics contributed"
        } catch {
            return error.localizedDescription
        }
    }

    private static var cacheFile: URL {
        SupportPaths.directory.appendingPathComponent("cohort-remote.json")
    }

    private static func loadCachedRemote() -> [String: Int64]? {
        guard let data = try? Data(contentsOf: cacheFile) else { return nil }
        struct Feed: Codable { var averages: [String: Int64] }
        return try? JSONDecoder().decode(Feed.self, from: data).averages
    }
}
