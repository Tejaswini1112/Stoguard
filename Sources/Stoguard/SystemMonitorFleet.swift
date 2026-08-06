import Foundation
import Darwin
import UserNotifications

// MARK: - System health (CPU / RAM / disk)

struct PulseSample: Codable, Identifiable, Hashable, Sendable {
    var id: String { "\(date.timeIntervalSince1970)" }
    let date: Date
    let cpu: Double
    let memory: Double
    let disk: Double
}

enum PulseHistory {
    private static var fileURL: URL {
        SupportPaths.directory.appendingPathComponent("pulse-history.json")
    }

    static func load() -> [PulseSample] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode([PulseSample].self, from: data)) ?? []
    }

    static func append(_ pulse: SystemPulse) {
        SupportPaths.ensureDirectory()
        var samples = load()
        samples.append(PulseSample(
            date: pulse.sampledAt,
            cpu: pulse.cpuBusyPercent,
            memory: pulse.memoryUsedPercent,
            disk: pulse.diskUsedPercent
        ))
        if samples.count > 96 { samples = Array(samples.suffix(96)) }
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(samples) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

struct SystemPulse: Sendable {
    var cpuBusyPercent: Double
    var memoryUsedBytes: Int64
    var memoryTotalBytes: Int64
    var diskFreeBytes: Int64
    var diskTotalBytes: Int64
    var pressureNotes: [String]
    var sampledAt: Date

    var memoryUsedPercent: Double {
        guard memoryTotalBytes > 0 else { return 0 }
        return Double(memoryUsedBytes) / Double(memoryTotalBytes) * 100
    }

    var diskUsedPercent: Double {
        guard diskTotalBytes > 0 else { return 0 }
        return Double(diskTotalBytes - diskFreeBytes) / Double(diskTotalBytes) * 100
    }
}

enum SystemHealth {
    static func snapshot() -> SystemPulse {
        let disk = DiskInfo.homeVolume()
        let mem = memory()
        let cpu = cpuUsage()
        var notes: [String] = []
        if disk.total > 0 {
            let usedPct = Double(disk.total - disk.free) / Double(disk.total) * 100
            if usedPct > 90 {
                notes.append("Disk is over 90% full — this alone can make the Mac feel slow (swap, Photos, indexing).")
            } else if usedPct > 80 {
                notes.append("Disk is over 80% full — clean reclaimable caches before performance cliffs.")
            }
        }
        if mem.total > 0 && Double(mem.used) / Double(mem.total) > 0.85 {
            notes.append("Memory pressure looks high — browsers, Docker, and IDEs are common culprits.")
        }
        if cpu > 70 {
            notes.append("CPU is busy right now — a scan, compile, or background indexer may be running.")
        }
        if notes.isEmpty {
            notes.append("No acute CPU/RAM/disk alarms in this snapshot.")
        }
        return SystemPulse(
            cpuBusyPercent: cpu,
            memoryUsedBytes: mem.used,
            memoryTotalBytes: mem.total,
            diskFreeBytes: disk.free,
            diskTotalBytes: disk.total,
            pressureNotes: notes,
            sampledAt: Date()
        )
    }

    private static func memory() -> (used: Int64, total: Int64) {
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var stats = vm_statistics64()
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size)
            }
        }
        let total = Int64(ProcessInfo.processInfo.physicalMemory)
        guard kerr == KERN_SUCCESS else { return (0, total) }
        let page = Int64(vm_kernel_page_size)
        let used = (Int64(stats.active_count) + Int64(stats.wire_count) + Int64(stats.compressor_page_count)) * page
        return (used, total)
    }

    /// Instantaneous-ish busy percent using host_processor_info delta over a short sleep.
    private static func cpuUsage() -> Double {
        let a = cpuTicks()
        Thread.sleep(forTimeInterval: 0.15)
        let b = cpuTicks()
        let busy = Double((b.user - a.user) + (b.system - a.system) + (b.nice - a.nice))
        let total = busy + Double(b.idle - a.idle)
        guard total > 0 else { return 0 }
        return min(100, max(0, busy / total * 100))
    }

    private static func cpuTicks() -> (user: UInt32, system: UInt32, nice: UInt32, idle: UInt32) {
        var num: natural_t = 0
        var info: processor_info_array_t?
        var count: mach_msg_type_number_t = 0
        let kr = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &num, &info, &count)
        guard kr == KERN_SUCCESS, let info else { return (0, 0, 0, 0) }
        defer {
            let size = vm_size_t(count) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), size)
        }
        var user: UInt32 = 0, system: UInt32 = 0, nice: UInt32 = 0, idle: UInt32 = 0
        let load = UnsafeRawPointer(info).bindMemory(to: processor_cpu_load_info.self, capacity: Int(num))
        for i in 0..<Int(num) {
            user += load[i].cpu_ticks.0
            system += load[i].cpu_ticks.1
            idle += load[i].cpu_ticks.2
            nice += load[i].cpu_ticks.3
        }
        return (user, system, nice, idle)
    }
}

// MARK: - Build trend (DerivedData / project artifacts over time)

struct BuildTrendSample: Codable, Identifiable, Sendable {
    var id: String { "\(date.timeIntervalSince1970)" }
    let date: Date
    let derivedDataBytes: Int64
    let gradleBytes: Int64
    let note: String?
}

struct BuildTrendStore: Codable, Sendable {
    var samples: [BuildTrendSample] = []

    private static var fileURL: URL {
        SupportPaths.directory.appendingPathComponent("build-trends.json")
    }

    static func load() -> BuildTrendStore {
        guard let data = try? Data(contentsOf: fileURL) else { return BuildTrendStore() }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode(BuildTrendStore.self, from: data)) ?? BuildTrendStore()
    }

    mutating func record() {
        let derived = Shell.size(PathUtil.expand("~/Library/Developer/Xcode/DerivedData"))
        let gradle = Shell.size(PathUtil.expand("~/.gradle/caches"))
        var note: String? = nil
        if let prev = samples.last {
            let delta = derived - prev.derivedDataBytes
            if delta > 500_000_000 {
                note = "DerivedData grew \(ByteText.string(delta)) — builds may feel heavier until cleaned."
            } else if delta < -200_000_000 {
                note = "DerivedData shrank \(ByteText.string(-delta)) — recent clean likely helped."
            }
        }
        samples.append(BuildTrendSample(date: Date(), derivedDataBytes: derived, gradleBytes: gradle, note: note))
        if samples.count > 90 { samples = Array(samples.suffix(90)) }
        save()
    }

    func save() {
        SupportPaths.ensureDirectory()
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(self) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }

    var insight: String {
        guard let last = samples.last else {
            return "No build-cache samples yet. Record one after a scan."
        }
        if let note = last.note { return note }
        return "DerivedData \(ByteText.string(last.derivedDataBytes)) · Gradle cache \(ByteText.string(last.gradleBytes))"
    }
}

// MARK: - Continuous monitoring

@MainActor
final class ContinuousMonitor: ObservableObject {
    @Published var enabled: Bool = UserDefaults.standard.bool(forKey: "stoguard.monitorEnabled")
    @Published var lastPulse: SystemPulse?
    @Published var alert: String?
    @Published var watchEvents: [BackgroundWatchEvent] = []

    /// Minutes between ticks (default 10; was 15).
    var intervalMinutes: Double {
        get {
            let v = UserDefaults.standard.double(forKey: "stoguard.monitorIntervalMinutes")
            return v > 0 ? v : 10
        }
        set { UserDefaults.standard.set(newValue, forKey: "stoguard.monitorIntervalMinutes") }
    }

    private var timer: Timer?
    private var lastFree: Int64?
    private var itemsProvider: (() -> [ScanItem])?
    private var modelsProvider: (() -> [AIModelEntry])?

    func configure(items: @escaping () -> [ScanItem], models: @escaping () -> [AIModelEntry]) {
        itemsProvider = items
        modelsProvider = models
    }

    func start(onDiskDrop: @escaping (Int64) -> Void) {
        timer?.invalidate()
        guard enabled else { return }
        let secs = max(120, intervalMinutes * 60)
        timer = Timer.scheduledTimer(withTimeInterval: secs, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick(onDiskDrop: onDiskDrop)
            }
        }
        tick(onDiskDrop: onDiskDrop)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func setEnabled(_ on: Bool, onDiskDrop: @escaping (Int64) -> Void) {
        enabled = on
        UserDefaults.standard.set(on, forKey: "stoguard.monitorEnabled")
        if on { start(onDiskDrop: onDiskDrop) } else { stop() }
    }

    private func tick(onDiskDrop: (Int64) -> Void) {
        let pulse = SystemHealth.snapshot()
        lastPulse = pulse
        PulseHistory.append(pulse)
        var fired = false
        if let prev = lastFree {
            let dropped = prev - pulse.diskFreeBytes
            if dropped > 2_000_000_000 {
                alert = "Free space dropped \(ByteText.storage(dropped)) since last check — open Health for explain → recommend → fix."
                notify(title: "Stoguard — disk dropping", body: alert ?? "")
                onDiskDrop(dropped)
                fired = true
            }
        }
        lastFree = pulse.diskFreeBytes
        if pulse.diskUsedPercent > 92 {
            alert = "Disk critically full (\(Int(pulse.diskUsedPercent))%). Open Health → clean safe caches first."
            notify(title: "Stoguard — disk critical", body: alert ?? "")
            if !fired { onDiskDrop(0) }
        } else if pulse.memoryUsedPercent > 92 {
            alert = "Memory pressure high (\(Int(pulse.memoryUsedPercent))%). Close idle AI models / heavy IDEs, then check Pulse."
            notify(title: "Stoguard — memory pressure", body: alert ?? "")
            if !fired { onDiskDrop(0) }
        }

        let items = itemsProvider?() ?? []
        let models = modelsProvider?() ?? []
        let events = BackgroundIntelligence.evaluateTick(items: items, models: models, pulse: pulse)
        if !events.isEmpty {
            watchEvents = (events + watchEvents).prefix(20).map { $0 }
            if let first = events.first {
                alert = "\(first.title) — \(first.body)"
                if first.severity == "warn" || first.severity == "critical" {
                    notify(title: "Stoguard — \(first.title)", body: first.body)
                }
            }
        }
    }

    private func notify(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { ok, _ in
            guard ok else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let req = UNNotificationRequest(
                identifier: "stoguard-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            center.add(req, withCompletionHandler: nil)
        }
    }
}

// MARK: - Fleet / team export

enum FleetExport {
    struct Report: Codable {
        var generatedAt: Date
        var host: String
        var freeBytes: Int64
        var totalBytes: Int64
        var reclaimableSafe: Int64
        var categoryTotals: [String: Int64]
        var topItems: [Item]
        var envWarnings: [String]
        var duplicateWasteBytes: Int64
        var rulesVersion: String?
        var appVersion: String

        struct Item: Codable {
            var id: String
            var name: String
            var category: String
            var bytes: Int64
            var safety: String
        }
    }

    static func build(
        items: [ScanItem],
        free: Int64,
        total: Int64,
        env: [EnvFinding],
        duplicates: [DuplicateGroup],
        rulesVersion: String?
    ) -> Report {
        var cats: [String: Int64] = [:]
        for i in items { cats[i.category, default: 0] += i.sizeBytes }
        let top = items.sorted { $0.sizeBytes > $1.sizeBytes }.prefix(25).map {
            Report.Item(id: $0.id, name: $0.name, category: $0.category, bytes: $0.sizeBytes, safety: $0.safety.rawValue)
        }
        return Report(
            generatedAt: Date(),
            host: ProcessInfo.processInfo.hostName,
            freeBytes: free,
            totalBytes: total,
            reclaimableSafe: items.filter { $0.safety == .safe }.reduce(0) { $0 + $1.sizeBytes },
            categoryTotals: cats,
            topItems: Array(top),
            envWarnings: env.filter { $0.severity == .warn }.map(\.title),
            duplicateWasteBytes: duplicates.reduce(0) { $0 + $1.wasteBytes },
            rulesVersion: rulesVersion,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.0"
        )
    }

    static func writeJSON(_ report: Report) throws -> URL {
        SupportPaths.ensureDirectory()
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        let data = try enc.encode(report)
        let url = SupportPaths.directory.appendingPathComponent("fleet-report-\(Int(Date().timeIntervalSince1970)).json")
        try data.write(to: url, options: .atomic)
        return url
    }
}
