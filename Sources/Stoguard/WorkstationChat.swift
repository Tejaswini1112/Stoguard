import Foundation

/// Natural-language answers grounded in scan/doctor facts. Optionally asks local Ollama.
enum WorkstationChat {
    struct Message: Identifiable, Hashable, Sendable {
        let id: UUID
        let role: Role
        let text: String
        let createdAt: Date

        enum Role: String, Sendable { case user, assistant }
    }

    struct Context: Sendable {
        var items: [ScanItem]
        var report: DoctorReport
        var pulse: SystemPulse?
        var duplicates: [DuplicateGroup]
        var models: [AIModelEntry]
        var env: [EnvFinding]
    }

    static func answer(_ question: String, context: Context) async -> String {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return "Ask anything about disk, models, duplicates, or why the Mac feels slow." }

        let grounded = groundedAnswer(q, context: context)
        if let enhanced = await maybeOllama(question: q, grounded: grounded, context: context) {
            return enhanced
        }
        return grounded
    }

    /// Deterministic “Why is my SSD full?” style narrative.
    static func whyIsSSDFull(context: Context) -> String {
        let items = context.items.sorted { $0.sizeBytes > $1.sizeBytes }
        let totalHot = items.reduce(Int64(0)) { $0 + $1.sizeBytes }
        guard totalHot > 0 else {
            return "I don’t have scan data yet. Run Analyze / Smart Scan first, then ask again."
        }

        var lines: [String] = []
        if let pulse = context.pulse, pulse.diskTotalBytes > 0 {
            lines.append("Your disk is about \(Int(pulse.diskUsedPercent))% full (\(ByteText.storage(pulse.diskFreeBytes)) free).")
        }

        lines.append("Developer-related hotspots total \(ByteText.string(totalHot)).")

        let top = Array(items.prefix(5))
        let topSum = top.reduce(Int64(0)) { $0 + $1.sizeBytes }
        if totalHot > 0 {
            lines.append("The top \(top.count) items are \(Int(Double(topSum) / Double(totalHot) * 100))% of that:")
            for t in top {
                lines.append("• \(t.name) — \(ByteText.string(t.sizeBytes)) (\(t.category)). \(TermGlossary.shortLabel(for: t))")
            }
        }

        if let growth = context.report.growth.first(where: { $0.deltaBytes > 0 }) {
            let grew = context.report.growth.filter { $0.deltaBytes > 0 }
            let sum = grew.reduce(Int64(0)) { $0 + $1.deltaBytes }
            if sum > 0 {
                let pct = Int(Double(growth.deltaBytes) / Double(sum) * 100)
                lines.append("Since your last scan, ~\(pct)% of growth came from \(growth.category) (\(growth.deltaText)).")
            }
        }

        let safe = context.report.reclaimableSafe
        if safe > 0 {
            lines.append("About \(ByteText.string(safe)) is labeled safe to reclaim (rebuildable caches).")
        }

        let idle = context.report.recommendations.filter { ($0.daysUnused ?? 0) >= 45 }
        if let first = idle.first {
            lines.append("Idle example: \(first.title) — \(first.advice)")
        }

        lines.append("Next step: open Workstation Doctor for guided actions, or say “clean safe caches”.")
        return lines.joined(separator: "\n")
    }

    private static func groundedAnswer(_ q: String, context: Context) -> String {
        let lower = q.lowercased()

        if matches(lower, ["ssd full", "disk full", "storage full", "why is my", "out of space", "no space", "eating"]) {
            return whyIsSSDFull(context: context)
        }
        if matches(lower, ["slow", "sluggish", "cpu", "memory", "ram", "performance"]) {
            return whySlow(context: context)
        }
        if matches(lower, ["docker"]) {
            return focusCategory("Containers", context: context, term: "Docker")
        }
        if matches(lower, ["xcode", "derived"]) {
            return focusCategory("Developer", context: context, term: "Xcode/DerivedData")
        }
        if matches(lower, ["ollama", "model", "llm", "huggingface", "lm studio"]) {
            return modelsSummary(context: context)
        }
        if matches(lower, ["duplicate", "nvm", "node version", "pyenv"]) {
            return duplicatesSummary(context: context)
        }
        if matches(lower, ["brew", "java", "python", "environment", "doctor"]) {
            return envSummary(context: context)
        }
        if matches(lower, ["safe", "reclaim", "clean", "delete", "trash"]) {
            let s = context.report.reclaimableSafe
            return "Safe-to-clean caches total \(ByteText.string(s)). These are rebuildable (DerivedData, npm cache, IDE caches, etc.). Use Overview → Clean Selected, or Doctor recommendations. Nothing is permanently erased until you empty Trash."
        }
        if matches(lower, ["what is", "explain", "mean"]) {
            if let item = context.items.first(where: { lower.contains($0.name.lowercased()) || lower.contains($0.id.lowercased()) }) {
                return TermGlossary.explain(item: item)
            }
            return whyIsSSDFull(context: context)
        }

        // Default: short briefing
        return """
        Here’s a quick briefing:

        \(whyIsSSDFull(context: context))

        You can also ask: “why is my Mac slow?”, “what about Docker?”, “show duplicate Node versions”, or “explain DerivedData”.
        """
    }

    private static func whySlow(context: Context) -> String {
        var lines: [String] = []
        if let p = context.pulse {
            lines.append("Snapshot: CPU \(Int(p.cpuBusyPercent))% · Memory \(Int(p.memoryUsedPercent))% · Disk \(Int(p.diskUsedPercent))% used.")
            lines.append(contentsOf: p.pressureNotes)
        } else {
            lines.append("No live pulse yet — open System Pulse or enable monitoring.")
        }
        let docker = context.items.filter { $0.id.contains("docker") || $0.category.contains("Containers") }
        if docker.reduce(0, { $0 + $1.sizeBytes }) > 10_000_000_000 {
            lines.append("Docker data is large — VMs compete for disk I/O even when idle.")
        }
        let derived = context.items.first { $0.id.contains("deriveddata") }
        if let derived, derived.sizeBytes > 5_000_000_000 {
            lines.append("Xcode DerivedData is \(ByteText.string(derived.sizeBytes)) — huge indexes can slow builds and Spotlight.")
        }
        lines.append("Freeing disk often helps more than closing one app. Ask “why is my SSD full?” for the breakdown.")
        return lines.joined(separator: "\n")
    }

    private static func focusCategory(_ needle: String, context: Context, term: String) -> String {
        let hits = context.items.filter {
            $0.category.localizedCaseInsensitiveContains(needle)
                || $0.name.localizedCaseInsensitiveContains(term)
                || $0.id.localizedCaseInsensitiveContains(term.lowercased())
        }.sorted { $0.sizeBytes > $1.sizeBytes }
        guard !hits.isEmpty else {
            return "No \(term) hotspots in the last scan (path missing or empty)."
        }
        var lines = ["\(term) related usage:"]
        for h in hits.prefix(6) {
            lines.append("• \(h.name): \(ByteText.string(h.sizeBytes)) — \(h.note)")
            if let d = h.daysSinceActivity, d >= 30 {
                lines.append("  Idle ~\(d) days.")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func modelsSummary(context: Context) -> String {
        guard !context.models.isEmpty else {
            return "No large local model folders found (Ollama / HF / LM Studio / etc.)."
        }
        let total = context.models.reduce(Int64(0)) { $0 + $1.sizeBytes }
        var lines = ["Local AI models/caches: \(ByteText.string(total)) across \(context.models.count) entries."]
        for m in context.models.prefix(8) {
            let idle = m.daysIdle.map { " · idle ~\($0)d" } ?? ""
            lines.append("• \(m.provider)/\(m.name): \(ByteText.string(m.sizeBytes))\(idle)")
        }
        lines.append("Open AI Models to reveal or trash with confirmation.")
        return lines.joined(separator: "\n")
    }

    private static func duplicatesSummary(context: Context) -> String {
        guard !context.duplicates.isEmpty else {
            return "No multi-version duplicate groups detected (nvm/pyenv/rustup/sim runtimes/Ollama tags)."
        }
        let waste = context.duplicates.reduce(Int64(0)) { $0 + $1.wasteBytes }
        var lines = ["Potential duplicate waste: \(ByteText.string(waste))."]
        for g in context.duplicates.prefix(6) {
            lines.append("• \(g.title): \(g.entries.count) copies, ~\(ByteText.string(g.wasteBytes)) extra")
        }
        return lines.joined(separator: "\n")
    }

    private static func envSummary(context: Context) -> String {
        let warns = context.env.filter { $0.severity == .warn }
        if warns.isEmpty {
            return "Environment Doctor didn’t find major warnings. Open Env Doctor for the full checklist."
        }
        return warns.map { "⚠ \($0.title) — \($0.detail)" }.joined(separator: "\n")
    }

    private static func matches(_ q: String, _ keys: [String]) -> Bool {
        keys.contains { q.contains($0) }
    }

    /// If Ollama is installed, ask it to rewrite the grounded facts — still fact-bound.
    private static func maybeOllama(question: String, grounded: String, context: Context) async -> String? {
        guard UserDefaults.standard.bool(forKey: "vacs.useOllamaChat") else { return nil }
        guard FileManager.default.fileExists(atPath: "/usr/local/bin/ollama")
                || FileManager.default.fileExists(atPath: "/opt/homebrew/bin/ollama")
                || which("ollama") != nil
        else { return nil }

        let prompt = """
        You are Stoguard, a macOS developer workstation assistant. Only use the FACTS below. Do not invent sizes. Be concise. Teach terms briefly.

        USER: \(question)

        FACTS:
        \(grounded)
        """

        let model = UserDefaults.standard.string(forKey: "vacs.ollamaModel") ?? "llama3.2"
        return await runOllama(model: model, prompt: prompt)
    }

    private static func which(_ cmd: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = [cmd]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do { try proc.run() } catch { return nil }
        proc.waitUntilExit()
        let s = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    private static func runOllama(model: String, prompt: String) async -> String? {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                if let path = which("ollama") {
                    proc.executableURL = URL(fileURLWithPath: path)
                } else {
                    proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                    proc.arguments = ["ollama", "run", model]
                }
                if proc.arguments == nil {
                    proc.arguments = ["run", model]
                }
                let input = Pipe()
                let output = Pipe()
                proc.standardInput = input
                proc.standardOutput = output
                proc.standardError = Pipe()
                do { try proc.run() } catch {
                    cont.resume(returning: nil)
                    return
                }
                input.fileHandleForWriting.write(Data(prompt.utf8))
                try? input.fileHandleForWriting.close()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async {
                    proc.waitUntilExit()
                    group.leave()
                }
                if group.wait(timeout: .now() + 45) == .timedOut {
                    proc.terminate()
                    cont.resume(returning: nil)
                    return
                }
                let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                cont.resume(returning: text.isEmpty ? nil : text)
            }
        }
    }
}
