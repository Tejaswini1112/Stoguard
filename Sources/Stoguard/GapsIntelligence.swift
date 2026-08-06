import Foundation
import Darwin

// MARK: - Hotspot growth history (predictive curves)

/// Named workstation hotspots tracked across scans for GB/day forecasts.
enum HotspotKind: String, CaseIterable, Codable, Sendable {
    case docker
    case ollama
    case huggingface
    case derivedData
    case downloads
    case timeMachine

    var title: String {
        switch self {
        case .docker: return "Docker"
        case .ollama: return "Ollama models"
        case .huggingface: return "Hugging Face cache"
        case .derivedData: return "Xcode DerivedData"
        case .downloads: return "Downloads"
        case .timeMachine: return "Time Machine local snapshots"
        }
    }

    var typicalNote: String {
        switch self {
        case .docker: return "Images, build cache, and volumes accumulate with every pull/build."
        case .ollama: return "Each `ollama pull` adds multi‑GB weights that stay until removed."
        case .huggingface: return "Transformers/diffusers re‑use hub blobs; experiments leave orphans."
        case .derivedData: return "Indexes and intermediates grow with every Xcode project you open."
        case .downloads: return "Installers and exports rarely get archived."
        case .timeMachine: return "Local APFS snapshots reclaim slowly until purged."
        }
    }
}

struct HotspotSnapshot: Codable, Hashable, Sendable {
    let date: Date
    let sizes: [String: Int64]
}

struct CategoryForecast: Identifiable, Hashable, Sendable {
    let id: String
    let kind: HotspotKind
    let currentBytes: Int64
    let bytesPerDay: Double
    let windowDays: Double
    let daysToDouble: Double?
    let projection30dBytes: Int64
    let severity: String

    var title: String {
        if bytesPerDay >= 50_000_000 {
            return String(format: "%@ growing %.1f GB/day", kind.title, bytesPerDay / 1e9)
        }
        if bytesPerDay <= -50_000_000 {
            return String(format: "%@ shrinking %.1f GB/day", kind.title, abs(bytesPerDay) / 1e9)
        }
        return "\(kind.title) stable at \(ByteText.string(currentBytes))"
    }

    var body: String {
        var lines = [
            "Now \(ByteText.string(currentBytes)).",
            String(format: "Rate over last %.0f days: %+.2f GB/day.", windowDays, bytesPerDay / 1e9),
        ]
        if bytesPerDay > 50_000_000 {
            lines.append("At this pace, +\(ByteText.string(projection30dBytes - currentBytes)) in ~30 days → ~\(ByteText.string(projection30dBytes)).")
            if let d = daysToDouble, d.isFinite, d > 0, d < 365 {
                lines.append(String(format: "Would roughly double in ~%.0f days if growth continues.", d))
            }
        }
        lines.append(kind.typicalNote)
        return lines.joined(separator: " ")
    }
}

enum HotspotTracker {
    private static var fileURL: URL {
        SupportPaths.directory.appendingPathComponent("hotspot-history.json")
    }

    static func load() -> [HotspotSnapshot] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode([HotspotSnapshot].self, from: data)) ?? []
    }

    static func measure(items: [ScanItem]) -> [String: Int64] {
        var sizes: [String: Int64] = [:]
        sizes[HotspotKind.docker.rawValue] = items.filter {
            $0.category.localizedCaseInsensitiveContains("Container")
                || $0.name.localizedCaseInsensitiveContains("Docker")
                || $0.id.localizedCaseInsensitiveContains("docker")
        }.reduce(Int64(0)) { $0 + $1.sizeBytes }

        sizes[HotspotKind.ollama.rawValue] = items.filter {
            $0.name.localizedCaseInsensitiveContains("ollama")
                || $0.id.localizedCaseInsensitiveContains("ollama")
                || $0.path.localizedCaseInsensitiveContains("/.ollama")
        }.reduce(Int64(0)) { $0 + $1.sizeBytes }
        if (sizes[HotspotKind.ollama.rawValue] ?? 0) == 0 {
            sizes[HotspotKind.ollama.rawValue] = Shell.size(PathUtil.expand("~/.ollama/models"))
        }

        sizes[HotspotKind.huggingface.rawValue] = items.filter {
            $0.name.localizedCaseInsensitiveContains("hugging")
                || $0.path.localizedCaseInsensitiveContains("huggingface")
        }.reduce(Int64(0)) { $0 + $1.sizeBytes }
        if (sizes[HotspotKind.huggingface.rawValue] ?? 0) == 0 {
            sizes[HotspotKind.huggingface.rawValue] = Shell.size(PathUtil.expand("~/.cache/huggingface"))
        }

        sizes[HotspotKind.derivedData.rawValue] = items.filter {
            $0.name.localizedCaseInsensitiveContains("DerivedData")
                || $0.id.localizedCaseInsensitiveContains("derived")
        }.reduce(Int64(0)) { $0 + $1.sizeBytes }
        if (sizes[HotspotKind.derivedData.rawValue] ?? 0) == 0 {
            sizes[HotspotKind.derivedData.rawValue] = Shell.size(
                PathUtil.expand("~/Library/Developer/Xcode/DerivedData")
            )
        }

        sizes[HotspotKind.downloads.rawValue] = Shell.size(PathUtil.expand("~/Downloads"))
        sizes[HotspotKind.timeMachine.rawValue] = measureTimeMachineSnapshots()
        return sizes
    }

    static func append(items: [ScanItem]) {
        SupportPaths.ensureDirectory()
        var hist = load()
        let snap = HotspotSnapshot(date: Date(), sizes: measure(items: items))
        // Keep at most one sample per hour to avoid spam while still tracking growth.
        if let last = hist.last, snap.date.timeIntervalSince(last.date) < 3600 {
            hist[hist.count - 1] = snap
        } else {
            hist.append(snap)
        }
        hist = Array(hist.suffix(90))
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(hist) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static func forecasts(items: [ScanItem], windowDays: Double = 30) -> [CategoryForecast] {
        let hist = load()
        let nowSizes = measure(items: items)
        let cutoff = Date().addingTimeInterval(-windowDays * 86_400)
        let window = hist.filter { $0.date >= cutoff }
        guard let oldest = window.first ?? hist.first, let newest = window.last ?? hist.last else {
            return HotspotKind.allCases.compactMap { kind in
                let cur = nowSizes[kind.rawValue] ?? 0
                guard cur > 100_000_000 else { return nil }
                return CategoryForecast(
                    id: kind.rawValue,
                    kind: kind,
                    currentBytes: cur,
                    bytesPerDay: 0,
                    windowDays: 0,
                    daysToDouble: nil,
                    projection30dBytes: cur,
                    severity: "info"
                )
            }
        }

        let days = max(0.5, newest.date.timeIntervalSince(oldest.date) / 86_400)
        return HotspotKind.allCases.compactMap { kind -> CategoryForecast? in
            let cur = nowSizes[kind.rawValue] ?? newest.sizes[kind.rawValue] ?? 0
            let then = oldest.sizes[kind.rawValue] ?? 0
            guard cur > 50_000_000 || then > 50_000_000 else { return nil }
            let delta = Double(cur - then)
            let rate = delta / days
            let proj = Int64(Double(cur) + rate * 30)
            let daysToDouble: Double? = rate > 1_000_000 ? Double(cur) / rate : nil
            let severity: String
            if rate > 1_500_000_000 { severity = "critical" }
            else if rate > 400_000_000 { severity = "warn" }
            else { severity = "info" }
            return CategoryForecast(
                id: kind.rawValue,
                kind: kind,
                currentBytes: cur,
                bytesPerDay: rate,
                windowDays: days,
                daysToDouble: daysToDouble,
                projection30dBytes: max(0, proj),
                severity: severity
            )
        }
        .sorted { abs($0.bytesPerDay) > abs($1.bytesPerDay) }
    }

    private static func measureTimeMachineSnapshots() -> Int64 {
        // Best-effort: tmutil listlocalsnapshotdates; size via `du` on snapshot mount is unreliable.
        // Use disk free delta hint from `tmutil calculatedrift` is too slow — measure common locals.
        let candidates = [
            "/.MobileBackups",
            PathUtil.expand("~/Library/Application Support/MobileSync"),
        ]
        var total: Int64 = 0
        for c in candidates where FileManager.default.fileExists(atPath: c) {
            total += Shell.size(c)
        }
        // Count local snapshots via tmutil (presence → estimate thin if we can't size).
        let listed = shell("tmutil", ["listlocalsnapshotdates", "/"])
        let lines = listed.split(separator: "\n").filter { $0.contains("-") }
        if total < 100_000_000 && lines.count > 2 {
            // Unknown size but multiple snapshots exist — report a sentinel so UI can mention them.
            total = Int64(lines.count) * 500_000_000 // conservative placeholder until thin reclaim
        }
        return total
    }

    private static func shell(_ cmd: String, _ args: [String]) -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = [cmd] + args
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do { try proc.run() } catch { return "" }
        let g = DispatchGroup()
        g.enter()
        DispatchQueue.global().async { proc.waitUntilExit(); g.leave() }
        _ = g.wait(timeout: .now() + 8)
        if proc.isRunning { proc.terminate() }
        return String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }
}

// MARK: - Recommendation explainability (Why / undo / rebuild / common)

struct RecommendationExplain: Hashable, Sendable {
    let why: String
    let whatHappens: String
    let canUndo: String
    let whatRebuilds: String
    let isCommon: String

    static func forItem(_ item: ScanItem) -> RecommendationExplain {
        let why = item.note.isEmpty
            ? "\(item.name) is using \(item.sizeText) under \(item.category)."
            : item.note
        let whatHappens: String
        let canUndo: String
        let rebuilds: String
        switch item.safety {
        case .safe:
            whatHappens = "Stoguard moves it to Trash. Your projects and source stay put."
            canUndo = "Yes — open Trash and Put Back before Empty Trash."
            rebuilds = "The tool recreates caches/indexes on next use (first run may be slower)."
        case .command:
            whatHappens = "You run the suggested CLI so the tool updates its own state safely."
            canUndo = "Usually no put-back for pruned layers — re-pull/rebuild instead."
            rebuilds = item.command.map { "Re-run workflows after `\($0)` as needed." }
                ?? "Tool regenerates missing pieces on next use."
        case .check:
            whatHappens = "You review the folder first — it may hold settings or project-adjacent data."
            canUndo = "If Trashed: Put Back. If deleted outside Trash: restore from backup."
            rebuilds = "Only rebuildable parts come back; preferences may need reconfiguration."
        case .never:
            whatHappens = "Stoguard will not remove this — it looks like credentials or profiles."
            canUndo = "N/A — no delete action offered."
            rebuilds = "N/A"
        }
        let common: String = {
            let id = item.id.lowercased() + item.name.lowercased()
            if id.contains("derived") { return "Very common — DerivedData often 5–40 GB on Macs that use Xcode." }
            if id.contains("docker") { return "Very common — Docker Desktop disks frequently reach 20–60 GB." }
            if id.contains("npm") || id.contains("gradle") || id.contains("cocoapod") {
                return "Common on active JS/Android/iOS projects."
            }
            if id.contains("ollama") || id.contains("hugging") || id.contains("model") {
                return "Increasingly common for local-AI developers (multi‑GB weights)."
            }
            if item.safety == .safe { return "Common reclaim target for developer machines." }
            return "Seen regularly on developer workstations; severity depends on your stack."
        }()
        return RecommendationExplain(
            why: why,
            whatHappens: whatHappens,
            canUndo: canUndo,
            whatRebuilds: rebuilds,
            isCommon: common
        )
    }
}

// MARK: - Live AI process usage (RAM / GPU best-effort)

struct AIRuntimeUsage: Hashable, Sendable {
    var ollamaResidentBytes: Int64
    var pythonAIResidentBytes: Int64
    var lmStudioResidentBytes: Int64
    var gpuBusyPercent: Double?
    var notes: [String]

    var totalAIResidentBytes: Int64 {
        ollamaResidentBytes + pythonAIResidentBytes + lmStudioResidentBytes
    }
}

enum AIRuntimeMonitor {
    static func snapshot() -> AIRuntimeUsage {
        var ollama: Int64 = 0
        var python: Int64 = 0
        var lm: Int64 = 0
        var notes: [String] = []

        // `ps -axo rss,comm` — RSS is in KB on macOS.
        let ps = shell("ps", ["-axo", "rss=,comm="])
        for line in ps.split(separator: "\n") {
            let parts = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard parts.count >= 2, let rssKB = Int64(parts[0]) else { continue }
            let comm = parts.dropFirst().joined(separator: " ").lowercased()
            let bytes = rssKB * 1024
            if comm.contains("ollama") {
                ollama += bytes
            } else if comm.contains("lm studio") || comm.contains("lm-studio") || comm.hasSuffix("lms") {
                lm += bytes
            } else if (comm.contains("python") || comm.contains("comfy")) &&
                        (comm.contains("torch") || comm.contains("transformers") || comm.contains("comfy") || bytes > 800_000_000) {
                python += bytes
            }
        }

        let gpu = gpuBusyPercent()
        if ollama > 0 {
            notes.append("Ollama resident ~\(ByteText.string(ollama))")
        }
        if lm > 0 { notes.append("LM Studio resident ~\(ByteText.string(lm))") }
        if python > 0 { notes.append("Python/Comfy-like resident ~\(ByteText.string(python))") }
        if let gpu {
            notes.append(String(format: "GPU busy ~%.0f%% (best-effort)", gpu))
        } else if notes.isEmpty {
            notes.append("No heavy local-AI processes detected right now.")
        }
        return AIRuntimeUsage(
            ollamaResidentBytes: ollama,
            pythonAIResidentBytes: python,
            lmStudioResidentBytes: lm,
            gpuBusyPercent: gpu,
            notes: notes
        )
    }

    /// Best-effort GPU utilization via `ioreg` / powermetrics is privileged — try metal HUD-less sample.
    private static func gpuBusyPercent() -> Double? {
        // `sudo powermetrics` needs admin. Fall back: parse `ioreg -r -d 1 -c IOAccelerator` for PerformanceStatistics if present.
        let out = shell("ioreg", ["-r", "-d", "1", "-c", "IOAccelerator"])
        if let range = out.range(of: "\"Device Utilization %\"=([0-9]+)", options: .regularExpression) {
            let slice = String(out[range])
            if let n = Int(slice.split(separator: "=").last.map(String.init) ?? "") {
                return Double(n)
            }
        }
        if let range = out.range(of: "\"GPU Busy\"=([0-9]+)", options: .regularExpression) {
            let slice = String(out[range])
            if let n = Int(slice.split(separator: "=").last.map(String.init) ?? "") {
                return Double(n)
            }
        }
        return nil
    }

    private static func shell(_ cmd: String, _ args: [String]) -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = [cmd] + args
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do { try proc.run() } catch { return "" }
        let g = DispatchGroup()
        g.enter()
        DispatchQueue.global().async { proc.waitUntilExit(); g.leave() }
        _ = g.wait(timeout: .now() + 4)
        if proc.isRunning { proc.terminate() }
        return String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }
}

// MARK: - Background intelligence (lightweight watches while app runs)

struct BackgroundWatchEvent: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let body: String
    let severity: String
    let date: Date
}

enum BackgroundIntelligence {
    private static let lastSizesKey = "stoguard.bg.lastHotspotSizes"
    private static let lastTickKey = "stoguard.bg.lastTick"

    static func evaluateTick(
        items: [ScanItem],
        models: [AIModelEntry],
        pulse: SystemPulse
    ) -> [BackgroundWatchEvent] {
        var events: [BackgroundWatchEvent] = []
        let now = HotspotTracker.measure(items: items)
        let prev = loadLastSizes()
        saveLastSizes(now)

        for kind in HotspotKind.allCases {
            let cur = now[kind.rawValue] ?? 0
            let before = prev[kind.rawValue] ?? cur
            let delta = cur - before
            // Rapid growth between ticks (monitor interval).
            if delta > 1_500_000_000 {
                events.append(BackgroundWatchEvent(
                    id: "spike-\(kind.rawValue)-\(Int(Date().timeIntervalSince1970))",
                    title: "\(kind.title) spiked +\(ByteText.string(delta))",
                    body: "Rapid growth since last background check. \(kind.typicalNote)",
                    severity: "warn",
                    date: Date()
                ))
            }
        }

        // Build cache spike: DerivedData alone.
        let derived = now[HotspotKind.derivedData.rawValue] ?? 0
        let derivedPrev = prev[HotspotKind.derivedData.rawValue] ?? derived
        if derived - derivedPrev > 800_000_000 {
            events.append(BackgroundWatchEvent(
                id: "build-spike-\(Int(Date().timeIntervalSince1970))",
                title: "Build cache spike",
                body: "DerivedData grew \(ByteText.string(derived - derivedPrev)). Large indexes after opening projects are normal — clean when idle.",
                severity: "info",
                date: Date()
            ))
        }

        for m in models where (m.daysIdle ?? 0) >= 90 && m.sizeBytes > 2_000_000_000 {
            events.append(BackgroundWatchEvent(
                id: "idle-model-\(m.id)",
                title: "Idle model store: \(m.provider)/\(m.name)",
                body: "Unused ~\(m.daysIdle ?? 90) days · \(ByteText.string(m.sizeBytes)). Archive or Trash if you don’t need it.",
                severity: "info",
                date: Date()
            ))
        }

        let docker = now[HotspotKind.docker.rawValue] ?? 0
        if docker > 25_000_000_000 {
            let dockerItems = items.filter {
                $0.name.localizedCaseInsensitiveContains("Docker") || $0.category.contains("Container")
            }
            let idleish = dockerItems.filter { ($0.daysSinceActivity ?? 0) >= 60 }
            if !idleish.isEmpty {
                events.append(BackgroundWatchEvent(
                    id: "idle-docker",
                    title: "Docker data large & idle",
                    body: "\(ByteText.string(docker)) with idle-looking layers. Prefer `docker system prune` for unused images.",
                    severity: "warn",
                    date: Date()
                ))
            }
        }

        if pulse.diskUsedPercent > 88 {
            events.append(BackgroundWatchEvent(
                id: "disk-watch",
                title: String(format: "Disk %.0f%% full", pulse.diskUsedPercent),
                body: "Background watch: free space is low enough to hurt performance. Open Health for forecasts and safe reclaim.",
                severity: pulse.diskUsedPercent > 92 ? "critical" : "warn",
                date: Date()
            ))
        }

        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastTickKey)
        // Deduplicate noisy idle-model spam: max 6 events per tick.
        return Array(events.prefix(6))
    }

    private static func loadLastSizes() -> [String: Int64] {
        (UserDefaults.standard.dictionary(forKey: lastSizesKey) as? [String: Int])?
            .mapValues { Int64($0) } ?? [:]
    }

    private static func saveLastSizes(_ sizes: [String: Int64]) {
        let boxed = sizes.mapValues { Int(clamping: $0) }
        UserDefaults.standard.set(boxed, forKey: lastSizesKey)
    }
}

// MARK: - Secrets scanner (Repository Doctor)

struct SecretFinding: Identifiable, Hashable, Sendable {
    let id: String
    let path: String
    let kind: String
    let snippet: String
    let severity: String
    let advice: String
}

enum SecretsScanner {
    private static let patterns: [(String, String, String)] = [
        ("AWS access key", #"AKIA[0-9A-Z]{16}"#, "Rotate the key in IAM; remove from git history if committed."),
        ("Generic API key assignment", #"(?i)(api[_-]?key|apikey|secret[_-]?key)\s*[:=]\s*['\"][^'\"]{12,}"#, "Move secrets to env vars or a vault; scrub the file."),
        ("Private key header", #"-----BEGIN (RSA |OPENSSH |EC )?PRIVATE KEY-----"#, "Never commit private keys. Rotate if this repo was pushed."),
        ("GitHub token", #"gh[pousr]_[A-Za-z0-9_]{36,}"#, "Revoke the token on GitHub and use a fine-grained replacement."),
        ("Slack token", #"xox[baprs]-[A-Za-z0-9-]{10,}"#, "Revoke in Slack admin and rotate."),
        ("JWT-like secret", #"(?i)(jwt|token)\s*[:=]\s*['\"]eyJ[A-Za-z0-9_-]{20,}"#, "Treat as compromised if committed; rotate signing secrets."),
    ]

    static func scan(root: String, maxFiles: Int = 400) -> [SecretFinding] {
        let abs = PathUtil.expand(root)
        guard FileManager.default.fileExists(atPath: abs) else { return [] }
        var findings: [SecretFinding] = []
        var filesChecked = 0
        let skipDirs: Set<String> = [
            "node_modules", ".git", "Pods", "build", "dist", "target",
            ".next", "vendor", "__pycache__", ".venv", "venv", "DerivedData",
        ]
        let textExt: Set<String> = [
            "env", "txt", "md", "json", "yml", "yaml", "js", "ts", "tsx", "py",
            "rb", "go", "swift", "kt", "java", "properties", "toml", "sh", "zsh",
            "plist", "xml", "cfg", "ini", "pem", "key",
        ]

        func walk(_ dir: String, depth: Int) {
            guard depth <= 6, filesChecked < maxFiles, findings.count < 40 else { return }
            guard let kids = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return }
            for name in kids {
                if name.hasPrefix(".") && name != ".env" && name != ".env.local" && name != ".env.production" { continue }
                let path = (dir as NSString).appendingPathComponent(name)
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { continue }
                if isDir.boolValue {
                    if skipDirs.contains(name) { continue }
                    walk(path, depth: depth + 1)
                    continue
                }
                let ext = (name as NSString).pathExtension.lowercased()
                let base = name.lowercased()
                let interesting = textExt.contains(ext) || base.hasPrefix(".env") || base.contains("secret") || base.contains("credential")
                guard interesting else { continue }
                filesChecked += 1
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: [.mappedIfSafe]),
                      data.count < 400_000,
                      let text = String(data: data, encoding: .utf8)
                else { continue }
                for (kind, pattern, advice) in patterns {
                    guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                    let range = NSRange(text.startIndex..<text.endIndex, in: text)
                    if let match = regex.firstMatch(in: text, range: range),
                       let swiftRange = Range(match.range, in: text) {
                        var snip = String(text[swiftRange])
                        if snip.count > 48 { snip = String(snip.prefix(40)) + "…" }
                        findings.append(SecretFinding(
                            id: "\(path)-\(kind)",
                            path: path,
                            kind: kind,
                            snippet: snip,
                            severity: "critical",
                            advice: advice
                        ))
                    }
                }
            }
        }

        walk(abs, depth: 0)
        return findings
    }
}
