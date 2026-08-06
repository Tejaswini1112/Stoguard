import Foundation

/// Natural-language AI mentor grounded in scan/doctor facts.
/// Primary output is a Phase-1 MentorBriefing (Problem → … → Learn More).
enum WorkstationChat {
    struct Message: Identifiable, Hashable, Sendable {
        let id: UUID
        let role: Role
        let text: String
        let createdAt: Date
        var briefing: MentorBriefing? = nil
        var knowledge: KnowledgeCard? = nil

        enum Role: String, Sendable { case user, assistant }
    }

    struct Context: Sendable {
        var items: [ScanItem]
        var report: DoctorReport
        var pulse: SystemPulse?
        var duplicates: [DuplicateGroup]
        var models: [AIModelEntry]
        var env: [EnvFinding]
        var health: HealthReport? = nil
        var predictions: [PredictiveInsight] = []
        var pulseHistory: [PulseSample] = []
    }

    /// Legacy string API — returns briefing plain text (Ollama may rewrite).
    static func answer(_ question: String, context: Context) async -> String {
        let briefing = await mentorAnswer(question, context: context)
        return briefing.plainText
    }

    /// Preferred API for Ask Stoguard UI.
    static func mentorAnswer(_ question: String, context: Context) async -> MentorBriefing {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            return MentorBriefing(
                problem: "No question yet",
                cause: "Empty input",
                explanation: "Ask why the Mac is slow, why Docker is huge, why Xcode grew, or what is safe to delete.",
                risk: "None",
                recommendation: "Try a chip below or type a question grounded in your last scan.",
                fix: MentorFix(label: "Open Doctor", kind: .openSection, section: .doctor),
                learnMore: MentorLearnMore(label: "Learning Center", articleID: nil, prompt: nil)
            )
        }

        var briefing = groundedBriefing(q, context: context)
        if let rewritten = await maybeOllama(question: q, grounded: briefing.plainText, context: context) {
            briefing = MentorBriefing(
                id: briefing.id,
                problem: briefing.problem,
                cause: briefing.cause,
                explanation: rewritten,
                risk: briefing.risk,
                recommendation: briefing.recommendation,
                fix: briefing.fix,
                learnMore: briefing.learnMore
            )
        }
        return briefing
    }

    /// Deterministic SSD diagnosis (sync; used by self-test and Overview shortcuts).
    static func whyIsSSDFull(context: Context) -> String {
        ssdFullBriefing(context: context).plainText
    }

    // MARK: - Routing

    private static func groundedBriefing(_ q: String, context: Context) -> MentorBriefing {
        let lower = q.lowercased()

        if matches(lower, ["safest cleanup", "cleanup sequence", "what should i clean first", "order"]) {
            return cleanupSequenceBriefing(context: context)
        }
        if matches(lower, ["will deleting", "break my", "can i delete", "safe to delete", "safe to clean", "what happens if"]) {
            return safeToDeleteBriefing(question: lower, context: context)
        }
        if matches(lower, ["ssd full", "disk full", "storage full", "out of space", "no space"])
            || (matches(lower, ["why is my"]) && matches(lower, ["ssd", "disk", "storage", "full"])) {
            return ssdFullBriefing(context: context)
        }
        if matches(lower, ["build", "builds getting", "compile", "deriveddata", "xcode using", "xcode"])
            && matches(lower, ["slow", "slower", "huge", "gb", "using", "why"]) {
            return xcodeBuildsBriefing(context: context)
        }
        if matches(lower, ["vscode", "vs code", "cursor freezing", "editor freezing", "freezing"]) {
            return vscodeFreezeBriefing(context: context)
        }
        if matches(lower, ["ollama slow", "model slow", "llm slow", "inference"])
            || (matches(lower, ["ollama"]) && matches(lower, ["slow", "why"])) {
            return ollamaSlowBriefing(context: context)
        }
        if matches(lower, ["memory always", "ram full", "memory full", "swap"])
            || (matches(lower, ["memory", "ram"]) && matches(lower, ["full", "why", "always"])) {
            return memoryFullBriefing(context: context)
        }
        if matches(lower, ["docker"]) && matches(lower, ["huge", "large", "space", "why", "using", "gb", "big"]) {
            return dockerHugeBriefing(context: context)
        }
        if matches(lower, ["slow", "sluggish", "performance", "this week"]) {
            return whySlowBriefing(context: context)
        }
        if matches(lower, ["docker"]) {
            return dockerHugeBriefing(context: context)
        }
        if matches(lower, ["xcode", "derived"]) {
            return xcodeBuildsBriefing(context: context)
        }
        if matches(lower, ["volume", "what is a docker"]) {
            return dockerVolumeBriefing(context: context)
        }
        if matches(lower, ["ollama", "model", "llm", "huggingface", "lm studio", "comfy", "stable diffusion"]) {
            return modelsBriefing(context: context)
        }
        if matches(lower, ["duplicate", "nvm", "node version", "pyenv"]) {
            return duplicatesBriefing(context: context)
        }
        if matches(lower, ["brew", "java", "python", "environment", "flutter", "rust", "git", "android"]) {
            return envBriefing(context: context)
        }
        if matches(lower, ["health", "score", "how healthy"]) {
            return healthBriefing(context: context)
        }
        if matches(lower, ["fill up", "will my ssd", "predict", "forecast", "run out"]) {
            return predictBriefing(context: context)
        }
        if matches(lower, ["what is", "explain", "mean", "why does", "teacher", "when should", "what happens", "teach me"]) {
            return teachBriefing(query: lower, context: context)
        }
        if matches(lower, ["safe", "reclaim", "clean", "delete", "trash"]) {
            return safeReclaimBriefing(context: context)
        }

        return defaultBriefing(context: context)
    }

    // MARK: - Phase-1 diagnosis briefings

    private static func ssdFullBriefing(context: Context) -> MentorBriefing {
        let items = context.items.sorted { $0.sizeBytes > $1.sizeBytes }
        let totalHot = items.reduce(Int64(0)) { $0 + $1.sizeBytes }
        guard totalHot > 0 else {
            return MentorBriefing(
                problem: "SSD / storage pressure unknown",
                cause: "No scan data yet",
                explanation: "Stoguard needs a Smart Scan before it can ground answers in your machine.",
                risk: "None",
                recommendation: "Run Analyze / Smart Scan, then ask again.",
                fix: MentorFix(label: "Open Overview to scan", kind: .openSection, section: .overview),
                learnMore: MentorLearnMore(label: "How Stoguard works", prompt: "Explain how Stoguard decides what is safe to clean")
            )
        }

        let top = Array(items.prefix(5))
        let topSum = top.reduce(Int64(0)) { $0 + $1.sizeBytes }
        let pct = totalHot > 0 ? Int(Double(topSum) / Double(totalHot) * 100) : 0
        var causeParts: [String] = []
        if let pulse = context.pulse, pulse.diskTotalBytes > 0 {
            causeParts.append("Disk ~\(Int(pulse.diskUsedPercent))% full (\(ByteText.storage(pulse.diskFreeBytes)) free)")
        }
        causeParts.append("Developer hotspots total \(ByteText.string(totalHot)); top \(top.count) are \(pct)% of that")
        if let growth = context.report.growth.first(where: { $0.deltaBytes > 0 }) {
            causeParts.append("Recent growth leader: \(growth.category) (\(growth.deltaText))")
        }

        let explainLines = top.map { "• \($0.name) — \(ByteText.string($0.sizeBytes)) (\($0.category)). \(TermGlossary.shortLabel(for: $0))" }
        let safe = context.report.reclaimableSafe
        let topSafe = items.first { $0.safety == .safe }

        return MentorBriefing(
            problem: "SSD feels full / low free space",
            cause: causeParts.joined(separator: ". "),
            explanation: """
            Developer-related folders often dominate Mac storage for engineers — not Photos or Movies.

            Largest measured items:
            \(explainLines.joined(separator: "\n"))

            \(safe > 0 ? "About \(ByteText.string(safe)) is labeled rebuildable/safe." : "Few safe caches measured — review command-gated items carefully.")
            """,
            risk: "Cleaning rebuildable caches is low risk. Deleting Docker volumes or credentials is medium–high — Stoguard never auto-deletes.",
            recommendation: safe > 0
                ? "Start with safe caches (\(ByteText.string(safe))), then Docker prune if unused, then idle AI models."
                : "Open Workstation Doctor and follow the safest cleanup sequence.",
            fix: topSafe.map {
                MentorFix(label: "Stage \($0.name) for Trash", kind: .trashSafeItem, section: .overview, itemID: $0.id)
            } ?? MentorFix(label: "Open Doctor", kind: .openSection, section: .doctor),
            learnMore: MentorLearnMore(label: "Learn DerivedData / Docker", articleID: "deriveddata", prompt: "Explain DerivedData")
        )
    }

    private static func whySlowBriefing(context: Context) -> MentorBriefing {
        var cause: [String] = []
        var explain: [String] = []
        if let p = context.pulse {
            cause.append("CPU \(Int(p.cpuBusyPercent))% · Memory \(Int(p.memoryUsedPercent))% · Disk \(Int(p.diskUsedPercent))% used")
            explain.append(contentsOf: p.pressureNotes)
        } else {
            cause.append("No live pulse sample yet")
        }
        if context.pulseHistory.count >= 2 {
            let first = context.pulseHistory[0]
            let last = context.pulseHistory[context.pulseHistory.count - 1]
            explain.append(String(
                format: "Trend across %d samples: CPU %.0f%%→%.0f%% · Mem %.0f%%→%.0f%% · Disk %.0f%%→%.0f%%.",
                context.pulseHistory.count, first.cpu, last.cpu, first.memory, last.memory, first.disk, last.disk
            ))
        }
        let dockerBytes = context.items.filter {
            $0.id.contains("docker") || $0.category.contains("Containers")
        }.reduce(Int64(0)) { $0 + $1.sizeBytes }
        if dockerBytes > 10_000_000_000 {
            explain.append("Docker data is \(ByteText.string(dockerBytes)) — VM disk I/O can make the whole Mac feel sticky.")
        }
        if let derived = context.items.first(where: { $0.id.contains("deriveddata") }),
           derived.sizeBytes > 5_000_000_000 {
            explain.append("Xcode DerivedData is \(ByteText.string(derived.sizeBytes)) — indexes tax disk and builds.")
        }
        if explain.isEmpty {
            explain.append("Without pulse + scan, slowdowns are usually disk pressure, memory pressure, or runaway build/indexers.")
        }

        return MentorBriefing(
            problem: "Mac feels slow or sluggish",
            cause: cause.joined(separator: ". "),
            explanation: explain.joined(separator: "\n"),
            risk: "Closing apps helps short-term; ignoring a nearly-full SSD causes chronic thrashing.",
            recommendation: "Free rebuildable disk first, then check Pulse for CPU/RAM spikes, then idle Docker/AI models.",
            fix: MentorFix(label: "Open System Pulse", kind: .openSection, section: .pulse),
            learnMore: MentorLearnMore(label: "Why SSD full?", prompt: "Why is my SSD full?")
        )
    }

    private static func xcodeBuildsBriefing(context: Context) -> MentorBriefing {
        let derived = context.items.first {
            $0.name.localizedCaseInsensitiveContains("DerivedData")
                || $0.id.localizedCaseInsensitiveContains("derived")
        }
        let size = derived.map { ByteText.string($0.sizeBytes) } ?? "unknown"
        let card = KnowledgeGraph.card(forTerm: "DerivedData", context: context)

        return MentorBriefing(
            problem: derived.map { "Xcode / builds using \($0.sizeText)" } ?? "Xcode builds feel slow or DerivedData is huge",
            cause: "DerivedData holds compiled intermediates, indexes, and module caches (your size: \(size))",
            explanation: """
            \(card?.plainBlock ?? "DerivedData is Xcode’s workspace for build products.")

            Typical size 5–20 GB; yours may be higher if you open many projects or rarely clean.
            Deleting it does not delete your source — only intermediates.
            """,
            risk: "Low. Next build is a cold compile (slower once), then returns to normal.",
            recommendation: "Trash DerivedData when idle between big projects, or when it exceeds ~20 GB and builds feel sluggish.",
            fix: derived.map {
                MentorFix(label: "Stage DerivedData for Trash", kind: .trashSafeItem, section: .developer, itemID: $0.id)
            } ?? MentorFix(label: "Open Developer section", kind: .openSection, section: .developer),
            learnMore: MentorLearnMore(label: "Learn DerivedData", articleID: "deriveddata")
        )
    }

    private static func dockerHugeBriefing(context: Context) -> MentorBriefing {
        let hits = context.items.filter {
            $0.category.localizedCaseInsensitiveContains("Container")
                || $0.name.localizedCaseInsensitiveContains("Docker")
        }.sorted { $0.sizeBytes > $1.sizeBytes }
        let total = hits.reduce(Int64(0)) { $0 + $1.sizeBytes }
        let lines = hits.prefix(5).map { "• \($0.name): \(ByteText.string($0.sizeBytes)) — \($0.note)" }
        let cmdItem = hits.first { $0.safety == .command }

        return MentorBriefing(
            problem: total > 0 ? "Docker using \(ByteText.string(total))" : "Docker disk usage is large",
            cause: "Images, layer cache, build cache, and volumes accumulate every pull/build",
            explanation: """
            Docker images are layered filesystems reused by containers. Unused tags and build cache stay until pruned.

            On this Mac:
            \(lines.isEmpty ? "• No Docker hotspots measured — is Docker Desktop installed?" : lines.joined(separator: "\n"))

            Prefer `docker system prune` / Desktop Clean rather than deleting the VM disk by hand.
            """,
            risk: "Low for unused images/cache. Medium–high for named volumes (may hold DB data).",
            recommendation: "Prune unused images/cache first; list volumes before removing any.",
            fix: cmdItem.flatMap { item in
                item.command.map { MentorFix(label: "Copy prune command", kind: .copyCommand, section: .containers, command: $0) }
            } ?? MentorFix(label: "Open Containers", kind: .openSection, section: .containers),
            learnMore: MentorLearnMore(label: "Learn Docker disk", articleID: "docker", prompt: "Would you like me to explain Docker images?")
        )
    }

    private static func dockerVolumeBriefing(context: Context) -> MentorBriefing {
        MentorBriefing(
            problem: "Understanding Docker volumes",
            cause: "Volumes persist data outside the container filesystem",
            explanation: """
            A Docker volume stores databases, uploads, and named state attached to containers.
            Images and build cache are usually safe to prune; named volumes may hold real app data.
            Review with `docker volume ls` before removing.
            \(focusCategory("Containers", context: context, term: "Docker"))
            """,
            risk: "Deleting the wrong volume can wipe a local database.",
            recommendation: "Prune images/cache; only remove volumes you recognize as disposable.",
            fix: MentorFix(label: "Open Containers", kind: .openSection, section: .containers),
            learnMore: MentorLearnMore(label: "Learn Docker", articleID: "docker")
        )
    }

    private static func memoryFullBriefing(context: Context) -> MentorBriefing {
        let mem = context.pulse.map { Int($0.memoryUsedPercent) } ?? 0
        var explain = ["Memory pressure often comes from browsers, IDEs, Docker VM, and loaded LLMs — not just “too many apps.”"]
        if let p = context.pulse {
            explain.append("Current memory ~\(Int(p.memoryUsedPercent))% used.")
            explain.append(contentsOf: p.pressureNotes)
        }
        let modelBytes = context.models.reduce(Int64(0)) { $0 + $1.sizeBytes }
        if modelBytes > 20_000_000_000 {
            explain.append("Local models on disk: \(ByteText.string(modelBytes)) — loaded models also consume RAM/VRAM.")
        }

        return MentorBriefing(
            problem: mem > 0 ? "Memory ~\(mem)% used / feels always full" : "Memory feels always full",
            cause: "Resident apps + Docker VM + IDE indexers + optional local LLMs compete for RAM",
            explanation: explain.joined(separator: "\n"),
            risk: "Chronic swap makes everything feel slow; quitting one app is temporary.",
            recommendation: "Check Pulse, unload unused Ollama models, pause Docker when idle, close heavy Electron apps.",
            fix: MentorFix(label: "Open System Pulse", kind: .openSection, section: .pulse),
            learnMore: MentorLearnMore(label: "Why is my Mac slow?", prompt: "Why is my Mac slow?")
        )
    }

    private static func ollamaSlowBriefing(context: Context) -> MentorBriefing {
        let total = context.models.reduce(Int64(0)) { $0 + $1.sizeBytes }
        let count = context.models.count
        let lines = context.models.prefix(6).map { m in
            let idle = m.daysIdle.map { " · idle ~\($0)d" } ?? ""
            return "• \(m.provider)/\(m.name): \(ByteText.string(m.sizeBytes))\(idle)"
        }

        return MentorBriefing(
            problem: "Ollama / local LLM feels slow",
            cause: count > 0
                ? "\(count) local model entries totaling \(ByteText.string(total)) — large models + disk pressure + CPU/GPU contention"
                : "Large models, disk pressure, or CPU/GPU contention (no model inventory yet)",
            explanation: """
            Local inference speed depends on model size, quantization, available RAM/GPU, and whether the SSD is thrashing.

            \(lines.isEmpty ? "Open AI Models after a scan to inventory weights." : lines.joined(separator: "\n"))

            \(AIModelOps.duplicatesSummary(models: context.models))
            """,
            risk: "Deleting a model is low risk (re-pull). Keeping dozens of huge weights fills the SSD and slows everything.",
            recommendation: "Keep 1–2 active models; archive or trash idle ones; free disk if >85% full.",
            fix: MentorFix(label: "Open AI Models", kind: .openSection, section: .aiModels),
            learnMore: MentorLearnMore(label: "Learn local models", articleID: "ollama")
        )
    }

    private static func vscodeFreezeBriefing(context: Context) -> MentorBriefing {
        let extRelated = context.items.filter {
            $0.name.localizedCaseInsensitiveContains("Code")
                || $0.name.localizedCaseInsensitiveContains("Cursor")
                || $0.name.localizedCaseInsensitiveContains("VS Code")
                || $0.category.localizedCaseInsensitiveContains("Apps")
        }.prefix(4)
        let lines = extRelated.map { "• \($0.name): \(ByteText.string($0.sizeBytes))" }

        return MentorBriefing(
            problem: "VS Code / Cursor freezing or stuttering",
            cause: "Extension host + language servers + large workspaces + low free disk/RAM",
            explanation: """
            Freezes are rarely “VS Code is broken” — usually indexing, a bad extension, or memory/disk pressure.

            Related measured items:
            \(lines.isEmpty ? "• No editor caches measured yet — still check Pulse and disk free space." : lines.joined(separator: "\n"))

            Also check Env Doctor for too many Node versions and AI Models for huge weights loaded alongside the IDE.
            """,
            risk: "Clearing editor caches is usually low risk; disabling extensions temporarily is safer than deleting settings.",
            recommendation: "Free disk if tight, reload window with extensions disabled to bisect, trim idle MCP/skills.",
            fix: MentorFix(label: "Open Skills/MCP", kind: .openSection, section: .agentTools),
            learnMore: MentorLearnMore(label: "Why Mac slow?", prompt: "Why is my Mac slow?")
        )
    }

    private static func cleanupSequenceBriefing(context: Context) -> MentorBriefing {
        let safe = context.items.filter { $0.safety == .safe }.sorted { $0.sizeBytes > $1.sizeBytes }
        let cmds = context.items.filter { $0.safety == .command }.sorted { $0.sizeBytes > $1.sizeBytes }
        let check = context.items.filter { $0.safety == .check }.sorted { $0.sizeBytes > $1.sizeBytes }
        var explain = ["1) Safe rebuildable caches first:"]
        if safe.isEmpty {
            explain.append("   • None measured — scan again.")
        } else {
            for s in safe.prefix(5) { explain.append("   • \(s.name) — \(s.sizeText)") }
        }
        explain.append("2) Tool CLIs next:")
        if cmds.isEmpty {
            explain.append("   • No command-gated items.")
        } else {
            for c in cmds.prefix(4) {
                explain.append("   • \(c.name) — \(c.command ?? "see Doctor")")
            }
        }
        explain.append("3) Check-first / idle models last:")
        for c in check.prefix(4) { explain.append("   • \(c.name) — \(c.sizeText)") }
        explain.append("Nothing is permanent until Empty Trash.")

        return MentorBriefing(
            problem: "Need a safe cleanup order",
            cause: "Mixing safe caches with volumes/credentials is how cleanups go wrong",
            explanation: explain.joined(separator: "\n"),
            risk: "Skipping order: you might prune a volume or delete credentials while chasing free space.",
            recommendation: "Stage safe caches first, confirm Clean, then Docker CLI, then review models.",
            fix: safe.first.map {
                MentorFix(label: "Stage largest safe cache", kind: .trashSafeItem, section: .overview, itemID: $0.id)
            } ?? MentorFix(label: "Open Doctor", kind: .openSection, section: .doctor),
            learnMore: MentorLearnMore(label: "Learning Center", articleID: nil, prompt: "Explain what safe to clean means")
        )
    }

    private static func safeToDeleteBriefing(question: String, context: Context) -> MentorBriefing {
        if let item = context.items.first(where: {
            question.contains($0.name.lowercased()) || question.contains($0.id.lowercased())
                || ($0.name.lowercased().contains("docker") && question.contains("docker"))
                || ($0.name.lowercased().contains("derived") && question.contains("derived"))
        }) {
            let after: String
            switch item.safety {
            case .safe: after = "Tools recreate this on next use. First run after delete may be slower."
            case .command: after = "Use the CLI so tool state stays consistent: \(item.command ?? "see item")."
            case .check: after = "May remove settings or project-adjacent data — reveal and skim before Trash."
            case .never: after = "Stoguard will not delete this — looks like profiles/credentials."
            }
            let fix: MentorFix? = {
                switch item.safety {
                case .safe:
                    return MentorFix(label: "Stage \(item.name)", kind: .trashSafeItem, section: .overview, itemID: item.id)
                case .command:
                    return item.command.map { MentorFix(label: "Copy command", kind: .copyCommand, section: .containers, command: $0) }
                default:
                    return MentorFix(label: "Reveal in Doctor", kind: .openSection, section: .doctor)
                }
            }()
            return MentorBriefing(
                problem: "Can I delete \(item.name)?",
                cause: "\(item.sizeText) · safety \(item.safety.rawValue) · \(item.note)",
                explanation: "\(TermGlossary.explain(item: item))\n\nWhat happens after:\n\(after)",
                risk: item.safety == .safe ? "Low" : item.safety == .command ? "Low if you use the CLI" : item.safety == .check ? "Medium — review first" : "Do not delete",
                recommendation: after,
                fix: fix,
                learnMore: MentorLearnMore(label: "Teach this term", prompt: "Explain \(item.name)")
            )
        }
        if let article = LearningCenter.article(matching: question) {
            return teachFromArticle(article, context: context)
        }
        let safe = context.report.reclaimableSafe
        return MentorBriefing(
            problem: "Is this safe to delete?",
            cause: "Couldn’t match a specific item name",
            explanation: "About \(ByteText.string(safe)) is labeled safe in your last scan. Name the folder (DerivedData, Docker, npm cache) for a precise answer.",
            risk: "Guessing without a match is how accidents happen.",
            recommendation: "Open Doctor or ask “Can I delete DerivedData safely?”",
            fix: MentorFix(label: "Open Doctor", kind: .openSection, section: .doctor),
            learnMore: MentorLearnMore(label: "Learning Center", articleID: nil)
        )
    }

    private static func teachBriefing(query: String, context: Context) -> MentorBriefing {
        if let article = LearningCenter.article(matching: query) {
            return teachFromArticle(article, context: context)
        }
        if let item = context.items.first(where: { query.contains($0.name.lowercased()) || query.contains($0.id.lowercased()) }) {
            return MentorBriefing(
                problem: "What is \(item.name)?",
                cause: "Appears in your scan at \(item.sizeText)",
                explanation: TermGlossary.explain(item: item),
                risk: "Safety: \(item.safety.rawValue)",
                recommendation: item.safety == .safe ? "Safe to stage for Trash when you need space." : "Review before removing.",
                fix: item.safety == .safe
                    ? MentorFix(label: "Stage for Trash", kind: .trashSafeItem, itemID: item.id)
                    : MentorFix(label: "Open Doctor", kind: .openSection, section: .doctor),
                learnMore: MentorLearnMore(label: "More in Learning Center", articleID: nil, prompt: "Teach me about \(item.name)")
            )
        }
        return ssdFullBriefing(context: context)
    }

    private static func teachFromArticle(_ a: LearningArticle, context: Context) -> MentorBriefing {
        let card = KnowledgeGraph.card(forTerm: a.id, context: context)
            ?? KnowledgeGraph.card(forTerm: a.title, context: context)
        let explain = """
        What it is: \(a.what)

        Why it exists: \(a.whyCreated)

        Why cleanup can be safe: \(a.whySafe)

        When to delete: \(a.whenDelete)

        After deletion: \(a.afterDelete)

        \(card.map { "\nKnowledge card:\n\($0.plainBlock)" } ?? "")
        """
        let item = context.items.first {
            $0.name.localizedCaseInsensitiveContains(a.title)
                || $0.id.localizedCaseInsensitiveContains(a.id)
        }
        return MentorBriefing(
            problem: "Understanding \(a.title)",
            cause: card?.purpose ?? a.whyCreated,
            explanation: explain,
            risk: card?.risk ?? "See when-to-delete guidance",
            recommendation: a.whenDelete,
            fix: item.flatMap {
                $0.safety == .safe
                    ? MentorFix(label: "Stage \($0.name)", kind: .trashSafeItem, itemID: $0.id)
                    : MentorFix(label: "Open related section", kind: .openSection, section: .learning, articleID: a.id)
            } ?? MentorFix(label: "Open Learning Center", kind: .openLearning, section: .learning, articleID: a.id),
            learnMore: MentorLearnMore(label: a.title, articleID: a.id)
        )
    }

    private static func modelsBriefing(context: Context) -> MentorBriefing {
        guard !context.models.isEmpty else {
            return MentorBriefing(
                problem: "Local AI model storage",
                cause: "No large model folders found yet",
                explanation: "Stoguard looks for Ollama, Hugging Face, LM Studio, ComfyUI, Stable Diffusion, llama.cpp.",
                risk: "None",
                recommendation: "Install/use a local stack, then rescan — or open AI Models.",
                fix: MentorFix(label: "Open AI Models", kind: .openSection, section: .aiModels),
                learnMore: MentorLearnMore(label: "Learn models", articleID: "ollama")
            )
        }
        let total = context.models.reduce(Int64(0)) { $0 + $1.sizeBytes }
        let lines = context.models.prefix(8).map { m in
            let idle = m.daysIdle.map { " · idle ~\($0)d" } ?? ""
            return "• \(m.provider)/\(m.name): \(ByteText.string(m.sizeBytes))\(idle)"
        }
        return MentorBriefing(
            problem: "Local AI models using \(ByteText.string(total))",
            cause: "\(context.models.count) model/cache entries across providers",
            explanation: """
            \(lines.joined(separator: "\n"))

            \(AIModelOps.duplicatesSummary(models: context.models))
            """,
            risk: "Low to archive/trash idle weights; you re-download to restore.",
            recommendation: "Archive or Trash idle models; keep active ones only.",
            fix: MentorFix(label: "Open AI Models", kind: .openSection, section: .aiModels),
            learnMore: MentorLearnMore(label: "Learn Ollama models", articleID: "ollama")
        )
    }

    private static func duplicatesBriefing(context: Context) -> MentorBriefing {
        let dups = context.duplicates.filter { $0.verdict == .duplicate }
        let related = context.duplicates.filter { $0.verdict == .related }
        let waste = dups.reduce(Int64(0)) { $0 + $1.wasteBytes }
        var explain: [String] = ["Confirmed duplicate reclaimable: \(ByteText.string(waste))."]
        for g in dups.prefix(4) { explain.append("• DUPLICATE — \(g.title) (~\(ByteText.string(g.wasteBytes)))") }
        if !related.isEmpty {
            explain.append("Related (not duplicates):")
            for g in related.prefix(4) {
                let diff = g.differences.first.map { "\($0.label): \($0.detail)" } ?? "see Differences"
                explain.append("• \(g.title) — \(diff)")
            }
        }
        if context.duplicates.isEmpty {
            explain = ["No confirmed duplicates or related multi-install groups found."]
        }
        return MentorBriefing(
            problem: "Duplicate / multi-version installs",
            cause: "nvm, pyenv, SDKs, and toolchains often leave parallel trees",
            explanation: explain.joined(separator: "\n"),
            risk: "Removing the wrong Node/Python version can break projects — prefer related-vs-duplicate guidance.",
            recommendation: "Clean fingerprint-confirmed duplicates first; keep related versions you still use.",
            fix: MentorFix(label: "Open Duplicates", kind: .openSection, section: .duplicates),
            learnMore: MentorLearnMore(label: "Env Doctor", prompt: "What does Environment Doctor find?")
        )
    }

    private static func envBriefing(context: Context) -> MentorBriefing {
        if context.env.isEmpty {
            return MentorBriefing(
                problem: "Environment health unknown",
                cause: "Env Doctor hasn’t run",
                explanation: "Checks Brew, Node, Python, Java, Android, Flutter, Rust, and Git.",
                risk: "None",
                recommendation: "Open Env Doctor and refresh.",
                fix: MentorFix(label: "Open Env Doctor", kind: .openSection, section: .envDoctor),
                learnMore: MentorLearnMore(label: "Ask about Node versions", prompt: "Why do I have so many Node versions?")
            )
        }
        let warns = context.env.filter { $0.severity == .warn }
        let oks = context.env.filter { $0.severity == .ok }
        var explain = ["\(oks.count) ok · \(warns.count) warning(s)."]
        for w in warns.prefix(8) {
            explain.append("⚠ \(w.title) — \(w.detail)")
            if let fix = w.fixHint { explain.append("   Fix: \(fix)") }
        }
        return MentorBriefing(
            problem: "Toolchain / environment sprawl",
            cause: warns.first.map { $0.title } ?? "Multiple language runtimes and SDKs installed",
            explanation: explain.joined(separator: "\n"),
            risk: "Version conflicts break builds; unused SDKs waste tens of GB.",
            recommendation: warns.isEmpty ? "Environment looks healthy — spot-check before major upgrades." : "Address warnings top-down; archive unused SDKs.",
            fix: MentorFix(label: "Open Env Doctor", kind: .openSection, section: .envDoctor),
            learnMore: MentorLearnMore(label: "Teach Node/Python sprawl", prompt: "Explain nvm and unused Node versions")
        )
    }

    private static func healthBriefing(context: Context) -> MentorBriefing {
        if let h = context.health {
            let dims = h.dimensions.map { "• \($0.name): \($0.score)/100 — \($0.detail)" }.joined(separator: "\n")
            return MentorBriefing(
                problem: "Workstation health \(h.overall)/100",
                cause: h.headline,
                explanation: dims,
                risk: h.overall < 70 ? "Below 70 — prioritize storage and performance fixes." : "Generally healthy — keep weekly scans.",
                recommendation: "Open Health for dimensions, predictions, and history.",
                fix: MentorFix(label: "Open Health", kind: .openHealth, section: .health),
                learnMore: MentorLearnMore(label: "Will SSD fill up?", prompt: "Will my SSD fill up soon?")
            )
        }
        return MentorBriefing(
            problem: "Health score not computed yet",
            cause: "Need scan + pulse",
            explanation: "Health combines Storage, Performance, Environment, Security, and AI Workspace.",
            risk: "None",
            recommendation: "Run Smart Scan, then open Health.",
            fix: MentorFix(label: "Open Health", kind: .openHealth, section: .health),
            learnMore: nil
        )
    }

    private static func predictBriefing(context: Context) -> MentorBriefing {
        let insights = context.predictions.isEmpty
            ? PredictiveEngine.insights(history: context.report.timeline, pulse: context.pulse, items: context.items)
            : context.predictions
        if insights.isEmpty {
            return MentorBriefing(
                problem: "SSD fill forecast unavailable",
                cause: "Need scans across multiple days",
                explanation: "Predictive engine estimates days-to-full from growth between scans.",
                risk: "None",
                recommendation: "Run Smart Scan again tomorrow to unlock forecasts.",
                fix: MentorFix(label: "Open Overview", kind: .scan, section: .overview),
                learnMore: MentorLearnMore(label: "Open Health predictions", articleID: nil)
            )
        }
        let body = insights.map { "• \($0.title)\n  \($0.body)" }.joined(separator: "\n\n")
        return MentorBriefing(
            problem: insights.first?.title ?? "Storage forecast",
            cause: "Growth rate from your scan history",
            explanation: body,
            risk: "Forecasts are estimates — large Docker pulls can change the curve overnight.",
            recommendation: "Act on the largest growth category before the ETA.",
            fix: MentorFix(label: "Open Health", kind: .openHealth, section: .health),
            learnMore: MentorLearnMore(label: "Why SSD full?", prompt: "Why is my SSD full?")
        )
    }

    private static func safeReclaimBriefing(context: Context) -> MentorBriefing {
        let s = context.report.reclaimableSafe
        return MentorBriefing(
            problem: "How much can I reclaim safely?",
            cause: "Rebuildable caches labeled safe in rules",
            explanation: "Safe-to-clean caches total \(ByteText.string(s)). DerivedData, npm cache, IDE caches, etc. Nothing is permanently erased until Empty Trash.",
            risk: "Low for labeled-safe items.",
            recommendation: "Use Overview → Clean Selected, or follow Doctor recommendations.",
            fix: MentorFix(label: "Open Overview", kind: .openSection, section: .overview),
            learnMore: MentorLearnMore(label: "Safest cleanup sequence", prompt: "What’s the safest cleanup sequence?")
        )
    }

    private static func defaultBriefing(context: Context) -> MentorBriefing {
        var cause = dossier(context: context)
        if cause.isEmpty { cause = "Run a Smart Scan for a full dossier." }
        let ssd = ssdFullBriefing(context: context)
        return MentorBriefing(
            problem: "Workstation briefing",
            cause: cause,
            explanation: ssd.explanation,
            risk: ssd.risk,
            recommendation: "Try: Explain DerivedData · Can I delete Docker safely? · Safest cleanup sequence · Will my SSD fill up soon?",
            fix: MentorFix(label: "Open Doctor", kind: .openSection, section: .doctor),
            learnMore: MentorLearnMore(label: "Learning Center", articleID: nil)
        )
    }

    // MARK: - Helpers

    private static func dossier(context: Context) -> String {
        var lines: [String] = []
        if let h = context.health {
            lines.append("Health \(h.overall)/100 — \(h.headline)")
        }
        if let p = context.predictions.first {
            lines.append("Forecast: \(p.title)")
        }
        let warns = context.env.filter { $0.severity == .warn }.count
        if warns > 0 {
            lines.append("Env Doctor: \(warns) warning(s)")
        }
        if !context.models.isEmpty {
            let t = context.models.reduce(Int64(0)) { $0 + $1.sizeBytes }
            lines.append("Local AI models: \(ByteText.string(t))")
        }
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

    private static func matches(_ q: String, _ keys: [String]) -> Bool {
        keys.contains { q.contains($0) }
    }

    private static func maybeOllama(question: String, grounded: String, context: Context) async -> String? {
        guard UserDefaults.standard.bool(forKey: "stoguard.useOllamaChat") else { return nil }
        guard FileManager.default.fileExists(atPath: "/usr/local/bin/ollama")
                || FileManager.default.fileExists(atPath: "/opt/homebrew/bin/ollama")
                || which("ollama") != nil
        else { return nil }

        let prompt = """
        You are Stoguard, an AI mentor for developer workstations. Only use the FACTS below. Do not invent sizes.
        Rewrite the Explanation section clearly for a developer. Keep facts exact. Do not invent fixes.

        USER: \(question)

        FACTS:
        \(dossier(context: context))

        \(grounded)
        """

        let model = UserDefaults.standard.string(forKey: "stoguard.ollamaModel") ?? "llama3.2"
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
