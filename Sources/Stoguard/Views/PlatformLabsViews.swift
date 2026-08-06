import SwiftUI
import AppKit

// MARK: - Ask Stoguard

struct AskStoguardView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(model.chatMessages) { msg in
                            chatBubble(msg).id(msg.id)
                        }
                        if model.chatBusy {
                            HStack { ProgressView().controlSize(.small); Text("Thinking…").foregroundStyle(Theme.secondaryText) }
                                .padding(10)
                        }
                    }
                    .padding(14)
                }
                .onChange(of: model.chatMessages.count) { _, _ in
                    if let last = model.chatMessages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            suggestions
            inputBar
        }
        .background(Theme.bg)
        .onAppear {
            if model.chatMessages.isEmpty { model.seedChatWelcome() }
            if model.systemPulse == nil { model.refreshPulse() }
            if !model.duplicatesLoaded { model.loadDuplicates() }
            if !model.modelsLoaded { model.loadAIModels() }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Ask Stoguard").font(.system(size: 18, weight: .bold)).displayTitle()
                Text("Context-aware mentor — grounded in your scan. Not ChatGPT. Not web search.")
                    .font(.caption).foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            Toggle("Ollama", isOn: Binding(
                get: { model.useOllamaChat },
                set: { model.setOllamaChat($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(14)
        .background(Theme.card)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var suggestions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("Why is my Mac slow?") { model.chatInput = "Why is my Mac slow?"; model.sendChat() }
                chip("SSD full?") { model.askWhySSDFull() }
                chip("Docker huge?") { model.chatInput = "Why is Docker using so much space?"; model.sendChat() }
                chip("Xcode 60GB?") { model.chatInput = "Why is Xcode using so much space?"; model.sendChat() }
                chip("Ollama slow?") { model.chatInput = "Why is Ollama slow?"; model.sendChat() }
                chip("VS Code freezing?") { model.chatInput = "Why is VS Code freezing?"; model.sendChat() }
                chip("Memory full?") { model.chatInput = "Why is memory always full?"; model.sendChat() }
                chip("Cleanup sequence") { model.chatInput = "What’s the safest cleanup sequence?"; model.sendChat() }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    private func chip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.caption.weight(.medium))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Theme.elevated, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask why it’s slow, huge, full…", text: $model.chatInput)
                .textFieldStyle(.roundedBorder)
                .onSubmit { model.sendChat() }
            Button("Send") { model.sendChat() }
                .buttonStyle(PrimaryPillButtonStyle())
                .disabled(model.chatBusy || model.chatInput.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(12)
        .background(Theme.card)
    }

    @ViewBuilder
    private func chatBubble(_ msg: WorkstationChat.Message) -> some View {
        HStack(alignment: .top) {
            if msg.role == .user { Spacer(minLength: 40) }
            if msg.role == .assistant, let briefing = msg.briefing {
                MentorBriefingCard(
                    briefing: briefing,
                    knowledge: msg.knowledge,
                    onFix: { model.applyMentorFix($0) },
                    onLearnMore: { model.applyMentorLearnMore($0) }
                )
            } else {
                Text(msg.text)
                    .font(.system(size: 13))
                    .foregroundStyle(msg.role == .user ? Color.white : Theme.primaryText)
                    .padding(10)
                    .background(
                        msg.role == .user ? Theme.navy : Theme.elevated,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .textSelection(.enabled)
            }
            if msg.role == .assistant { Spacer(minLength: 24) }
        }
    }
}

// MARK: - Mentor briefing card (Problem → … → Fix)

struct MentorBriefingCard: View {
    let briefing: MentorBriefing
    var knowledge: KnowledgeCard? = nil
    var onFix: (MentorFix) -> Void
    var onLearnMore: (MentorLearnMore) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            section("Problem", briefing.problem, weight: .semibold)
            flowDivider
            section("Cause", briefing.cause)
            flowDivider
            section("Explanation", briefing.explanation)
            flowDivider
            section("Risk", briefing.risk)
            flowDivider
            section("Recommendation", briefing.recommendation)

            if let knowledge {
                KnowledgeCardView(card: knowledge)
            }

            HStack(spacing: 8) {
                if let fix = briefing.fix {
                    Button(fix.label) { onFix(fix) }
                        .buttonStyle(PrimaryPillButtonStyle())
                }
                if let learn = briefing.learnMore {
                    Button(learn.label) { onLearnMore(learn) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .padding(.top, 4)
        }
        .padding(12)
        .frame(maxWidth: 520, alignment: .leading)
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.navy.opacity(0.12), lineWidth: 1)
        )
    }

    private var flowDivider: some View {
        Image(systemName: "arrow.down")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(Theme.secondaryText.opacity(0.55))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 2)
    }

    private func section(_ title: String, _ body: String, weight: Font.Weight = .regular) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.navy.opacity(0.75))
                .tracking(0.6)
            Text(body)
                .font(.system(size: 12.5, weight: weight))
                .foregroundStyle(Theme.primaryText)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct KnowledgeCardView: View {
    let card: KnowledgeCard

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(card.title).font(.system(size: 13, weight: .semibold))
            gridRow("Storage", card.yourSizeText ?? "—")
            gridRow("Created by", card.createdBy)
            gridRow("Purpose", card.purpose)
            gridRow("Can I delete?", card.canDelete)
            gridRow("After effect", card.afterEffect)
            gridRow("Risk", card.risk)
            gridRow("Typical size", card.typicalSize)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card.opacity(0.9), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func gridRow(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k).font(.caption).foregroundStyle(Theme.secondaryText).frame(width: 100, alignment: .leading)
            Text(v).font(.caption).foregroundStyle(Theme.primaryText).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - System Pulse

struct SystemPulseView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                title("System Pulse", subtitle: "CPU, memory, and disk pressure — with a short history when monitoring is on.")
                Toggle("Continuous monitoring (every 15 min · notifies on critical pressure)", isOn: Binding(
                    get: { model.continuousMonitor.enabled },
                    set: { model.setContinuousMonitoring($0) }
                ))
                if let alert = model.monitorAlert ?? model.continuousMonitor.alert {
                    Text(alert).font(.callout).foregroundStyle(Theme.navy)
                        .padding(10).elevatedCard(radius: 8)
                }
                if let p = model.systemPulse {
                    HStack(spacing: 12) {
                        metric("CPU", "\(Int(p.cpuBusyPercent))%")
                        metric("Memory", "\(Int(p.memoryUsedPercent))%")
                        metric("Disk", "\(Int(p.diskUsedPercent))%")
                    }
                    ForEach(p.pressureNotes, id: \.self) { note in
                        Text("· \(note)").font(.callout).foregroundStyle(Theme.secondaryText)
                    }
                } else {
                    ProgressView("Sampling…")
                }
                let hist = PulseHistory.load().suffix(8)
                if !hist.isEmpty {
                    Text("Recent samples").font(.headline).padding(.top, 4)
                    ForEach(Array(hist)) { s in
                        HStack {
                            Text(s.date.formatted(date: .omitted, time: .shortened))
                                .font(.caption).foregroundStyle(Theme.secondaryText)
                            Spacer()
                            Text("CPU \(Int(s.cpu))% · Mem \(Int(s.memory))% · Disk \(Int(s.disk))%")
                                .font(.caption.monospacedDigit())
                        }
                        .padding(8).elevatedCard(radius: 8)
                    }
                }
                Button("Refresh pulse") { model.refreshPulse() }
                    .buttonStyle(SecondaryOutlineButtonStyle())
            }
            .padding(14)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .background(Theme.bg)
        .onAppear { model.refreshPulse() }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.tertiaryText)
            Text(value).font(.title2.bold().monospacedDigit())
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading).elevatedCard(radius: 10)
    }
}

// MARK: - Env / Dupes / Models / Git / Codebase / Rules / Fleet

struct EnvDoctorView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        labList(
            title: "Environment Doctor",
            subtitle: "Brew, Node, Python, Java, Android, Flutter, Rust, Git, Xcode CLT.",
            loading: model.isLoadingEnv,
            reload: { model.loadEnvDoctor() }
        ) {
            ForEach(model.envFindings) { f in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: f.severity == .ok ? "checkmark.circle.fill" : f.severity == .warn ? "exclamationmark.triangle.fill" : "info.circle")
                            .foregroundStyle(f.severity == .ok ? Theme.safeGreen : Theme.navy)
                        Text(f.title).font(.system(size: 13, weight: .semibold))
                    }
                    Text(f.detail).font(.caption).foregroundStyle(Theme.secondaryText)
                    if let fix = f.fixHint {
                        Text("Fix: \(fix)").font(.caption.weight(.medium)).foregroundStyle(Theme.navy)
                    }
                }
                .padding(12).elevatedCard(radius: 10)
            }
        }
        .onAppear { if !model.envLoaded { model.loadEnvDoctor() } }
    }
}

struct DuplicatesView: View {
    @EnvironmentObject var model: AppModel

    private var confirmed: [DuplicateGroup] {
        model.duplicateGroups.filter { $0.verdict == .duplicate }
    }
    private var related: [DuplicateGroup] {
        model.duplicateGroups.filter { $0.verdict == .related }
    }

    var body: some View {
        labList(
            title: "Duplicate Finder",
            subtitle: "Confirmed duplicates only after fingerprint checks. Related installs show differences — not labeled duplicate.",
            loading: model.isLoadingDuplicates,
            reload: { model.loadDuplicates() }
        ) {
            if model.duplicatesLoaded && model.duplicateGroups.isEmpty {
                Text("No confirmed duplicates or related multi-install groups found.")
                    .foregroundStyle(Theme.secondaryText)
            }

            if !confirmed.isEmpty {
                Text("Confirmed duplicates")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.top, 4)
                ForEach(confirmed) { g in
                    duplicateCard(g)
                }
            }

            if !related.isEmpty {
                Text("Related — not duplicates")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.top, 8)
                Text("Compared thoroughly; differences are listed with icons. These are not reclaimable “duplicate waste”.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                ForEach(related) { g in
                    duplicateCard(g)
                }
            }
        }
        .onAppear { if !model.duplicatesLoaded { model.loadDuplicates() } }
    }

    private func duplicateCard(_ g: DuplicateGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: g.verdict.icon)
                    .foregroundStyle(g.verdict == .duplicate ? Theme.navy : Theme.secondaryText)
                VStack(alignment: .leading, spacing: 2) {
                    Text(g.title).font(.system(size: 13, weight: .semibold))
                    Text(g.verdict.badge)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(g.verdict == .duplicate ? Theme.navy : Theme.secondaryText)
                }
                Spacer()
                if g.verdict == .duplicate, g.wasteBytes > 0 {
                    Text("~\(ByteText.string(g.wasteBytes)) reclaimable")
                        .font(.caption.monospacedDigit())
                } else {
                    Text(ByteText.string(g.totalBytes))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            Text(g.explanation).font(.caption).foregroundStyle(Theme.secondaryText)

            if !g.differences.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(g.differences) { d in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: d.icon)
                                .font(.system(size: 12))
                                .frame(width: 16)
                                .foregroundStyle(Theme.navy)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(d.label)
                                    .font(.system(size: 11, weight: .semibold))
                                Text(d.detail)
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondaryText)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
                .padding(8)
                .background(Theme.navy.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            ForEach(g.entries) { e in
                Button { model.revealInFinder(e.path) } label: {
                    HStack {
                        Image(systemName: "doc")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.tertiaryText)
                        Text(e.name).font(.system(size: 12))
                        if let fp = e.fingerprint {
                            Text(String(fp.prefix(8)))
                                .font(.system(size: 9).monospaced())
                                .foregroundStyle(Theme.tertiaryText)
                        }
                        Spacer()
                        Text(ByteText.string(e.sizeBytes))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.secondaryText)
                    }
                }.buttonStyle(.plain)
            }
        }
        .padding(12).elevatedCard(radius: 10)
    }
}

struct PackageFinderView: View {
    @EnvironmentObject var model: AppModel

    private var cacheItems: [ScanItem] {
        model.items(for: .packageManagers).sorted { $0.sizeBytes > $1.sizeBytes }
    }

    var body: some View {
        labList(
            title: "Packages",
            subtitle: "Installed Homebrew / npm / pipx tools (with definitions) plus rebuildable package caches.",
            loading: model.isLoadingPackages,
            reload: {
                model.loadPackageFinder()
                if !model.scannedSections.contains(.packageManagers) {
                    model.scan(section: .packageManagers)
                }
            }
        ) {
            Text("Installed packages")
                .font(.system(size: 15, weight: .semibold))

            if model.isLoadingPackages && model.packageFindings.isEmpty {
                Text("Scanning Homebrew Cellar and global installs…")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }

            if model.packagesLoaded && model.packageFindings.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No Homebrew / npm / pipx installs matched yet.")
                        .foregroundStyle(Theme.secondaryText)
                    Text("Tap Refresh — this reads /opt/homebrew/Cellar and global node_modules.")
                        .font(.caption)
                        .foregroundStyle(Theme.tertiaryText)
                }
            }

            if !model.packageFindings.isEmpty {
                let total = model.packageFindings.reduce(Int64(0)) { $0 + $1.sizeBytes }
                Text("\(model.packageFindings.count) installs · \(ByteText.string(total))")
                    .font(.callout)
                    .foregroundStyle(Theme.secondaryText)
            }

            ForEach(model.packageFindings) { p in
                PackageInstallRow(package: p)
            }

            Text("Package caches")
                .font(.system(size: 15, weight: .semibold))
                .padding(.top, 12)
            Text("Rebuildable download/build caches (safe to clean).")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)

            if cacheItems.isEmpty {
                Text(model.scannedSections.contains(.packageManagers)
                     ? "No package caches found."
                     : "Run Refresh to measure npm / Homebrew / Go caches.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .elevatedCard(radius: 10)
            } else {
                ForEach(cacheItems) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(item.name).font(.system(size: 13, weight: .semibold))
                            SafetyChip(safety: item.safety, libraryRisk: item.isLibraryProfileRisk)
                            Spacer()
                            Text(item.sizeText).font(.caption.monospacedDigit())
                        }
                        Text(item.path).font(.system(size: 10).monospaced()).foregroundStyle(Theme.secondaryText).lineLimit(1)
                        Text(item.note).font(.caption).foregroundStyle(Theme.secondaryText)
                        HStack {
                            Button("Reveal") { model.revealInFinder(item.path) }.buttonStyle(.link).font(.caption)
                            if item.safety == .safe || item.safety == .check {
                                Button("Move to Trash…") { model.requestTrash(item) }.buttonStyle(.link).font(.caption)
                            }
                        }
                    }
                    .padding(12).elevatedCard(radius: 10)
                }
            }
        }
        .onAppear {
            model.loadPackageFinder()
            if !model.scannedSections.contains(.packageManagers) {
                model.scan(section: .packageManagers)
            }
        }
    }
}


private struct PackageInstallRow: View {
    @EnvironmentObject var model: AppModel
    let package: PackageFinding
    @State private var showWhy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(package.name).font(.system(size: 13, weight: .semibold))
                Button {
                    showWhy = true
                } label: {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.navy.opacity(0.85))
                        .accessibilityLabel("Why is \(package.name) installed?")
                }
                .buttonStyle(.plain)
                .help("What this package is and why it’s installed")
                Text(package.source)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.navy)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Theme.navy.opacity(0.1), in: Capsule())
                Spacer()
                Text(package.sizeText)
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
            }
            Text(package.definition)
                .font(.system(size: 12))
                .foregroundStyle(Theme.primaryText)
            Text(package.path).font(.system(size: 10).monospaced()).foregroundStyle(Theme.secondaryText).lineLimit(1)
            Text(package.detail).font(.caption).foregroundStyle(Theme.tertiaryText)
            if let days = package.daysIdle, days >= 45 {
                Text("Idle ~\(days) days — likely unused")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.dangerRed)
            }
            HStack {
                Button("Reveal") { model.revealInFinder(package.path) }.buttonStyle(.link).font(.caption)
                Button("Why installed?") { showWhy = true }.buttonStyle(.link).font(.caption)
            }
        }
        .padding(12).elevatedCard(radius: 10)
        .popover(isPresented: $showWhy, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 10) {
                Text(package.name)
                    .font(.system(size: 15, weight: .bold))
                Text("What it is")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                Text(package.definition)
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Why it’s here")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                Text(PackageWhy.reason(for: package))
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Disk · \(package.sizeText)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
                Text(package.detail)
                    .font(.caption)
                    .foregroundStyle(Theme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(width: 320, alignment: .leading)
        }
    }
}

enum PackageWhy {
    static func reason(for p: PackageFinding) -> String {
        switch p.source.lowercased() {
        case let s where s.contains("homebrew"):
            return "Installed with Homebrew — usually a CLI, language runtime, or library you needed for a project."
        case let s where s.contains("npm"):
            return "Installed globally with npm so the CLI is available in every project terminal."
        case let s where s.contains("pipx"):
            return "Installed with pipx as an isolated Python CLI app (its own virtualenv)."
        case let s where s.contains("cargo"):
            return "Installed with Cargo as a Rust binary on your PATH."
        case let s where s.contains("user bin"):
            return "Dropped into ~/.local/bin — a tool you installed manually for shell use."
        default:
            return "You (or a setup script) installed this as a developer tool. Review whether you still use it before removing."
        }
    }
}

struct AgentToolsView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        labList(
            title: "AI Skills & MCP",
            subtitle: "MCP servers, skill packs, and idle editor extensions.",
            loading: model.isLoadingAgentTools,
            reload: { model.loadAgentTools() }
        ) {
            if model.agentToolsLoaded && model.agentToolFindings.isEmpty {
                Text("No MCP configs, skills, or large extensions found.").foregroundStyle(Theme.secondaryText)
            }
            ForEach(model.agentToolFindings) { f in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(f.name).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                        Text(f.kind)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(f.isStale ? Theme.dangerRed : Theme.navy)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background((f.isStale ? Theme.dangerRed : Theme.navy).opacity(0.1), in: Capsule())
                        Spacer()
                        Text(f.sizeText).font(.caption.monospacedDigit())
                    }
                    Text(f.path).font(.system(size: 10).monospaced()).foregroundStyle(Theme.secondaryText).lineLimit(1)
                    Text(f.detail).font(.caption).foregroundStyle(Theme.secondaryText)
                    if f.isStale, let days = f.staleDays {
                        Text("Outdated / idle ~\(days) days")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.dangerRed)
                    }
                    Button("Reveal") { model.revealInFinder(f.path) }.buttonStyle(.link).font(.caption)
                }
                .padding(12).elevatedCard(radius: 10)
            }
        }
        .onAppear { if !model.agentToolsLoaded { model.loadAgentTools() } }
    }
}

struct AIModelsView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        labList(title: "Local AI Workspace Manager", subtitle: "Models · last used · RAM estimate · GPU · quants · duplicates · archive/delete.", loading: model.isLoadingModels, reload: {
            model.loadAIModels()
            model.refreshIntelligence()
        }) {
            let total = model.aiModels.reduce(Int64(0)) { $0 + $1.sizeBytes }
            if model.modelsLoaded {
                Text("Disk \(ByteText.string(total)) across \(model.aiModels.count) entries")
                    .font(.callout).foregroundStyle(Theme.secondaryText)
                if let rt = model.aiRuntimeUsage {
                    Text(rt.notes.joined(separator: " · "))
                        .font(.caption).foregroundStyle(Theme.navy)
                    if rt.totalAIResidentBytes > 0 {
                        Text("Live AI RAM ~\(ByteText.string(rt.totalAIResidentBytes))")
                            .font(.caption.weight(.semibold))
                    }
                }
                Text(AIModelOps.duplicatesSummary(models: model.aiModels))
                    .font(.caption).foregroundStyle(Theme.secondaryText)
                    .padding(.bottom, 4)
            }
            ForEach(model.aiModels) { m in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(m.provider) · \(m.name)").font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text(ByteText.string(m.sizeBytes)).font(.caption.monospacedDigit())
                    }
                    HStack(spacing: 8) {
                        if let q = m.quantization {
                            Text(q).font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Theme.navy.opacity(0.12), in: Capsule())
                        }
                        if let f = m.formatHint {
                            Text(f).font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Theme.secondaryText)
                        }
                        if let ram = m.estimatedRAMBytes {
                            Text("~\(ByteText.string(ram)) RAM if loaded")
                                .font(.caption2).foregroundStyle(Theme.secondaryText)
                        }
                    }
                    if let d = m.daysIdle {
                        Text(d >= 45 ? "Last used ~\(d) days ago (idle)" : "Last used ~\(d) days ago")
                            .font(.caption).foregroundStyle(d >= 45 ? Theme.dangerRed : Theme.secondaryText)
                    }
                    if let tip = m.suggestedAction {
                        Text(tip).font(.caption.weight(.medium)).foregroundStyle(Theme.navy)
                    }
                    Text(m.removeHint).font(.caption).foregroundStyle(Theme.tertiaryText)
                    HStack {
                        Button("Reveal") { model.revealInFinder(m.path) }.buttonStyle(SecondaryOutlineButtonStyle())
                        Button("Archive") { model.archiveAIModel(m) }.buttonStyle(SecondaryOutlineButtonStyle())
                        Button("Move to Trash…") { model.trashAIModel(m) }.buttonStyle(DestructivePillButtonStyle())
                    }
                }
                .padding(12).elevatedCard(radius: 10)
            }
        }
        .onAppear {
            if !model.modelsLoaded { model.loadAIModels() }
            model.refreshIntelligence()
        }
    }
}

struct GitReposView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        labList(title: "Git Repository Optimizer", subtitle: "Large .git dirs, stashes, and branch sprawl.", loading: model.isLoadingGit, reload: { model.loadGitRepos() }) {
            ForEach(model.gitReports) { r in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(r.name).font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text(".git \(ByteText.string(r.gitBytes))").font(.caption.monospacedDigit())
                    }
                    Text(r.path).font(.system(size: 10).monospaced()).foregroundStyle(Theme.secondaryText).lineLimit(1)
                    Text("\(r.branchCount) branches · \(r.stashCount) stashes")
                        .font(.caption).foregroundStyle(Theme.secondaryText)
                    ForEach(r.recommendations, id: \.self) { rec in
                        Text("· \(rec)").font(.caption).foregroundStyle(Theme.primaryText)
                    }
                    Button("Reveal") { model.revealInFinder(r.path) }.buttonStyle(SecondaryOutlineButtonStyle())
                }
                .padding(12).elevatedCard(radius: 10)
            }
        }
        .onAppear { if !model.gitLoaded { model.loadGitRepos() } }
    }
}

struct CodebaseView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                title("Repository Doctor", subtitle: "Git weight · dead deps · duplicate assets · binaries · secrets · build artifacts.")
                HStack {
                    TextField("Repository path", text: $model.codebasePath)
                        .textFieldStyle(.roundedBorder)
                    Button("Analyze") { model.analyzeCodebase() }
                        .buttonStyle(PrimaryPillButtonStyle())
                        .disabled(model.isLoadingCodebase)
                }
                if model.isLoadingCodebase { ProgressView() }
                if model.repoInsightTotal > 0 {
                    Text("Repo size ~\(ByteText.string(model.repoInsightTotal)) · \(model.repoInsights.count) insights")
                        .font(.callout).foregroundStyle(Theme.secondaryText)
                }
                if !model.secretFindings.isEmpty {
                    Text("Secrets (\(model.secretFindings.count))").font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.dangerRed)
                    ForEach(model.secretFindings) { s in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(s.kind).font(.system(size: 13, weight: .semibold))
                            Text(s.path).font(.system(size: 10).monospaced()).foregroundStyle(Theme.secondaryText).lineLimit(2)
                            Text("Match: \(s.snippet)").font(.caption).foregroundStyle(Theme.dangerRed)
                            Text(s.advice).font(.caption)
                            Button("Reveal") { model.revealInFinder(s.path) }.buttonStyle(.link).font(.caption)
                        }
                        .padding(12).elevatedCard(radius: 10)
                    }
                }
                if !model.repoInsights.isEmpty {
                    Text("Intelligence").font(.system(size: 14, weight: .semibold))
                    ForEach(model.repoInsights) { r in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(r.title).font(.system(size: 13, weight: .semibold))
                                Text(r.kind.uppercased())
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Theme.secondaryText)
                                Spacer()
                                Text(ByteText.string(r.bytes)).font(.caption.monospacedDigit())
                            }
                            Text(r.detail).font(.caption).foregroundStyle(Theme.secondaryText)
                        }
                        .padding(12).elevatedCard(radius: 10)
                    }
                }
                if !model.codebaseFindings.isEmpty {
                    Text("Analyzer findings").font(.system(size: 14, weight: .semibold)).padding(.top, 4)
                }
                ForEach(model.codebaseFindings) { f in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(f.title).font(.system(size: 13, weight: .semibold))
                            Spacer()
                            Text(ByteText.string(f.bytes)).font(.caption.monospacedDigit())
                        }
                        Text("\(f.kind) — \(f.advice)").font(.caption).foregroundStyle(Theme.secondaryText)
                        Button("Reveal") { model.revealInFinder(f.path) }.buttonStyle(GhostButtonStyle())
                    }
                    .padding(12).elevatedCard(radius: 10)
                }
            }
            .padding(14).frame(maxWidth: 900, alignment: .leading)
        }
        .background(Theme.bg)
    }
}

struct BuildTrendsView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                title("Build Performance Trends", subtitle: "DerivedData & Gradle cache size over time (proxy for build weight).")
                Text(model.buildTrends.insight).font(.callout)
                Button("Record sample now") { model.recordBuildTrend() }
                    .buttonStyle(PrimaryPillButtonStyle())
                ForEach(model.buildTrends.samples.suffix(12).reversed()) { s in
                    HStack {
                        Text(s.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(Theme.secondaryText)
                        Spacer()
                        Text("DD \(ByteText.string(s.derivedDataBytes))")
                            .font(.caption.monospacedDigit())
                        Text("Gradle \(ByteText.string(s.gradleBytes))")
                            .font(.caption.monospacedDigit()).foregroundStyle(Theme.secondaryText)
                    }
                    .padding(8).elevatedCard(radius: 8)
                }
            }
            .padding(14).frame(maxWidth: 900, alignment: .leading)
        }
        .background(Theme.bg)
    }
}

struct RulesPluginsView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                title("Rules & Plugins", subtitle: "Versioned cloud rules + drop-in JSON plugins. Full schema: docs/PLUGIN_SDK.md")
                Text("Active rules: \(model.ruleCount)")
                    .font(.headline)
                if let meta = model.rulesMeta {
                    Text("Feed version: \(meta.version ?? "—") · source: \(meta.source)")
                        .font(.caption).foregroundStyle(Theme.secondaryText)
                }
                if let status = model.rulesStatus {
                    Text(status).font(.caption).foregroundStyle(Theme.secondaryText)
                }
                HStack {
                    Button(model.rulesRefreshing ? "Refreshing…" : "Refresh cloud rules") {
                        Task { await model.refreshCloudRules() }
                    }
                    .buttonStyle(PrimaryPillButtonStyle())
                    .disabled(model.rulesRefreshing)
                    Button("Open Plugins folder") { model.openPluginsFolder() }
                        .buttonStyle(SecondaryOutlineButtonStyle())
                }
                Text("Plugins (\(model.plugins.count))")
                    .font(.headline).padding(.top, 8)
                ForEach(model.plugins) { p in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(p.name).font(.system(size: 13, weight: .semibold))
                            Text(p.displayRisk.uppercased())
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Theme.secondaryText)
                            Spacer()
                            Text(p.version ?? "").font(.caption2).foregroundStyle(Theme.tertiaryText)
                        }
                        if let d = p.description {
                            Text(d).font(.caption).foregroundStyle(Theme.secondaryText)
                        }
                        Text("\(p.rules.count) rules · platforms: \((p.platforms ?? ["any"]).joined(separator: ", "))")
                            .font(.caption).foregroundStyle(Theme.secondaryText)
                        if let docs = p.documentationURL, let url = URL(string: docs) {
                            Link("Documentation", destination: url).font(.caption)
                        }
                        ForEach(p.rules.prefix(3)) { r in
                            Text("· \(r.name) — \(r.riskLevel ?? r.safety.rawValue)")
                                .font(.caption2).foregroundStyle(Theme.tertiaryText)
                            if let actions = r.safeActions, !actions.isEmpty {
                                Text("  Actions: \(actions.joined(separator: " · "))")
                                    .font(.caption2).foregroundStyle(Theme.secondaryText)
                            }
                        }
                    }
                    .padding(10).elevatedCard(radius: 8)
                }
                Text("Cross-platform: add Plugins/*.json or Plugins/<pack>/rules.json with \"platforms\": [\"macos\",\"windows\",\"linux\"]. Same packs load in the Go engine at :8787 — see docs/PLUGIN_SDK.md and repo plugins/{docker,flutter,unity,rust}/.")
                    .font(.caption).foregroundStyle(Theme.tertiaryText)
            }
            .padding(14).frame(maxWidth: 900, alignment: .leading)
        }
        .background(Theme.bg)
        .onAppear {
            model.refreshPluginsList()
            model.rulesMeta = CloudRules.loadMeta()
        }
    }
}

struct FleetExportView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                title("Enterprise Fleet", subtitle: "Multi-machine health, compliance, AI inventory, licenses — macOS · Windows · Linux via shared schema.")
                if let s = model.fleetSummary {
                    HStack(spacing: 12) {
                        summaryPill("Machines", "\(s.machineCount)")
                        summaryPill("Reclaimable", ByteText.string(s.totalReclaimable))
                        summaryPill("Non-compliant", "\(s.nonCompliantCount)")
                        if let h = s.avgHealth { summaryPill("Avg health", "\(h)") }
                    }
                }
                Text("Machine ID: \(EnterpriseIdentity.machineID)")
                    .font(.caption.monospaced()).foregroundStyle(Theme.secondaryText)
                HStack {
                    Button("Export + ingest this Mac") {
                        if !model.envLoaded { model.loadEnvDoctor() }
                        if !model.duplicatesLoaded { model.loadDuplicates() }
                        if !model.modelsLoaded { model.loadAIModels() }
                        model.exportFleetReport()
                    }
                    .buttonStyle(PrimaryPillButtonStyle())
                    Button("Refresh list") {
                        model.fleetMachines = FleetStore.list()
                        model.fleetSummary = FleetStore.summary()
                    }
                    .buttonStyle(SecondaryOutlineButtonStyle())
                }
                Text("Push to Team server (Go with -bind 0.0.0.0 -api-key …)")
                    .font(.system(size: 13, weight: .semibold)).padding(.top, 6)
                TextField("http://fleet-host:8787", text: $model.enterpriseRemoteURL)
                    .textFieldStyle(.roundedBorder)
                SecureField("API key (optional)", text: $model.enterpriseAPIKey)
                    .textFieldStyle(.roundedBorder)
                Button(model.isPushingFleet ? "Pushing…" : "Push report to remote") {
                    model.pushFleetToRemote()
                }
                .buttonStyle(SecondaryOutlineButtonStyle())
                .disabled(model.isPushingFleet)
                if let s = model.fleetStatus {
                    Text(s).font(.caption).foregroundStyle(Theme.secondaryText)
                }
                Text("Fleet machines (\(model.fleetMachines.count))")
                    .font(.headline).padding(.top, 8)
                ForEach(model.fleetMachines) { m in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(m.hostname).font(.system(size: 13, weight: .semibold))
                            Text(m.platform.uppercased())
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Theme.secondaryText)
                            Spacer()
                            Text(ByteText.string(m.reclaimable)).font(.caption.monospacedDigit())
                        }
                        if let c = m.report.compliance {
                            Text("Compliance \(c.score)/100 · \(c.failed.first ?? "all checks passed")")
                                .font(.caption)
                                .foregroundStyle(c.score < 80 ? Theme.dangerRed : Theme.secondaryText)
                        }
                        if let h = m.report.healthScore {
                            Text("Health \(h)/100 · \(m.report.aiModels.count) AI models · \(m.report.licenses.count) licenses")
                                .font(.caption2).foregroundStyle(Theme.tertiaryText)
                        }
                        Text(m.report.scannedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2).foregroundStyle(Theme.tertiaryText)
                        Button("Remove") { model.deleteFleetMachine(m.report.machineID) }
                            .buttonStyle(.link).font(.caption)
                    }
                    .padding(12).elevatedCard(radius: 10)
                }
            }
            .padding(14).frame(maxWidth: 900, alignment: .leading)
        }
        .background(Theme.bg)
        .onAppear {
            model.fleetMachines = FleetStore.list()
            model.fleetSummary = FleetStore.summary()
        }
    }

    private func summaryPill(_ k: String, _ v: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.system(size: 14, weight: .bold).monospacedDigit())
            Text(k).font(.caption2).foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .elevatedCard(radius: 8)
    }
}

// MARK: - Shared chrome

private func title(_ t: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(t).font(.system(size: 22, weight: .bold)).displayTitle()
        Text(subtitle).font(.subheadline).foregroundStyle(Theme.secondaryText)
    }
}

private func labList<Content: View>(
    title titleText: String,
    subtitle: String,
    loading: Bool,
    reload: @escaping () -> Void,
    @ViewBuilder content: () -> Content
) -> some View {
    ScrollView {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                title(titleText, subtitle: subtitle)
                Spacer()
                Button(loading ? "Scanning…" : "Refresh", action: reload)
                    .buttonStyle(SecondaryOutlineButtonStyle())
                    .disabled(loading)
            }
            if loading { ProgressView().padding(.vertical, 20) }
            content()
        }
        .padding(14)
        .frame(maxWidth: 900, alignment: .leading)
    }
    .background(Theme.bg)
}
