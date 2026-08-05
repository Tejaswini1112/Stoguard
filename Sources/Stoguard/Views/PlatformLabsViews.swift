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
                    LazyVStack(alignment: .leading, spacing: 10) {
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
                Text("Answers use your scan data. Optional: enhance with local Ollama.")
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
                chip("Why is my SSD full?") { model.askWhySSDFull() }
                chip("Why is my Mac slow?") { model.chatInput = "Why is my Mac slow?"; model.sendChat() }
                chip("Docker?") { model.chatInput = "What about Docker?"; model.sendChat() }
                chip("Duplicates") { model.chatInput = "Show duplicate Node versions"; model.sendChat() }
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
            TextField("Ask about disk, models, env…", text: $model.chatInput)
                .textFieldStyle(.roundedBorder)
                .onSubmit { model.sendChat() }
            Button("Send") { model.sendChat() }
                .buttonStyle(PrimaryPillButtonStyle())
                .disabled(model.chatBusy || model.chatInput.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(12)
        .background(Theme.card)
    }

    private func chatBubble(_ msg: WorkstationChat.Message) -> some View {
        HStack {
            if msg.role == .user { Spacer(minLength: 40) }
            Text(msg.text)
                .font(.system(size: 13))
                .foregroundStyle(msg.role == .user ? Color.white : Theme.primaryText)
                .padding(10)
                .background(
                    msg.role == .user ? Theme.navy : Theme.elevated,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .textSelection(.enabled)
            if msg.role == .assistant { Spacer(minLength: 40) }
        }
    }
}

// MARK: - System Pulse

struct SystemPulseView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                title("System Pulse", subtitle: "CPU, memory, and disk — why the machine feels slow.")
                Toggle("Continuous monitoring (every 15 min)", isOn: Binding(
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
            subtitle: "Brew, runtimes, and SDK conflicts.",
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
    var body: some View {
        labList(title: "Duplicate Finder", subtitle: "Multiple Node/Python/Rust/simulator/model copies.", loading: model.isLoadingDuplicates, reload: { model.loadDuplicates() }) {
            if model.duplicateGroups.isEmpty && model.duplicatesLoaded {
                Text("No multi-version duplicate groups found.").foregroundStyle(Theme.secondaryText)
            }
            ForEach(model.duplicateGroups) { g in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(g.title).font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text("~\(ByteText.string(g.wasteBytes)) extra").font(.caption.monospacedDigit())
                    }
                    Text(g.explanation).font(.caption).foregroundStyle(Theme.secondaryText)
                    ForEach(g.entries) { e in
                        Button { model.revealInFinder(e.path) } label: {
                            HStack {
                                Text(e.name).font(.system(size: 12))
                                Spacer()
                                Text(ByteText.string(e.sizeBytes)).font(.caption.monospacedDigit()).foregroundStyle(Theme.secondaryText)
                            }
                        }.buttonStyle(.plain)
                    }
                }
                .padding(12).elevatedCard(radius: 10)
            }
        }
        .onAppear { if !model.duplicatesLoaded { model.loadDuplicates() } }
    }
}

struct PackageFinderView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        labList(
            title: "Package Finder",
            subtitle: "Every sizable install with a definition and how much disk it uses — so you know what you installed and why.",
            loading: model.isLoadingPackages,
            reload: { model.loadPackageFinder() }
        ) {
            if model.packagesLoaded && model.packageFindings.isEmpty {
                Text("No sizable installed packages found.").foregroundStyle(Theme.secondaryText)
            }
            if model.packagesLoaded && !model.packageFindings.isEmpty {
                let total = model.packageFindings.reduce(Int64(0)) { $0 + $1.sizeBytes }
                Text("\(model.packageFindings.count) packages · \(ByteText.string(total)) total")
                    .font(.callout)
                    .foregroundStyle(Theme.secondaryText)
            }
            ForEach(model.packageFindings) { p in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(p.name).font(.system(size: 13, weight: .semibold))
                        Text(p.source)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.navy)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.navy.opacity(0.1), in: Capsule())
                        Spacer()
                        Text(p.sizeText)
                            .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    }
                    Text(p.definition)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.primaryText)
                    Text(p.path).font(.system(size: 10).monospaced()).foregroundStyle(Theme.secondaryText).lineLimit(1)
                    Text(p.detail).font(.caption).foregroundStyle(Theme.tertiaryText)
                    if let days = p.daysIdle, days >= 45 {
                        Text("Idle ~\(days) days — likely unused")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.dangerRed)
                    }
                    HStack {
                        Button("Reveal") { model.revealInFinder(p.path) }.buttonStyle(.link).font(.caption)
                    }
                }
                .padding(12).elevatedCard(radius: 10)
            }
        }
        .onAppear { if !model.packagesLoaded { model.loadPackageFinder() } }
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
        labList(title: "Local AI Model Manager", subtitle: "Ollama, Hugging Face, LM Studio, ComfyUI, Whisper, llama.cpp.", loading: model.isLoadingModels, reload: { model.loadAIModels() }) {
            let total = model.aiModels.reduce(Int64(0)) { $0 + $1.sizeBytes }
            if model.modelsLoaded {
                Text("Total \(ByteText.string(total)) across \(model.aiModels.count) entries")
                    .font(.callout).foregroundStyle(Theme.secondaryText)
            }
            ForEach(model.aiModels) { m in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(m.provider) · \(m.name)").font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text(ByteText.string(m.sizeBytes)).font(.caption.monospacedDigit())
                    }
                    if let d = m.daysIdle {
                        Text(d >= 45 ? "Unused ~\(d) days" : "Last activity ~\(d) days ago")
                            .font(.caption).foregroundStyle(Theme.secondaryText)
                    }
                    Text(m.removeHint).font(.caption).foregroundStyle(Theme.tertiaryText)
                    HStack {
                        Button("Reveal") { model.revealInFinder(m.path) }.buttonStyle(SecondaryOutlineButtonStyle())
                        Button("Move to Trash…") { model.trashAIModel(m) }.buttonStyle(DestructivePillButtonStyle())
                    }
                }
                .padding(12).elevatedCard(radius: 10)
            }
        }
        .onAppear { if !model.modelsLoaded { model.loadAIModels() } }
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
                title("Codebase Analyzer", subtitle: "Point at a repository — heavy folders and binaries.")
                HStack {
                    TextField("Repository path", text: $model.codebasePath)
                        .textFieldStyle(.roundedBorder)
                    Button("Analyze") { model.analyzeCodebase() }
                        .buttonStyle(PrimaryPillButtonStyle())
                        .disabled(model.isLoadingCodebase)
                }
                if model.isLoadingCodebase { ProgressView() }
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
                title("Rules & Plugins", subtitle: "Versioned cloud rules + drop-in technology plugins (macOS/Windows/Linux schema).")
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
                ForEach(model.plugins, id: \.id) { p in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.name).font(.system(size: 13, weight: .semibold))
                        Text("\(p.rules.count) rules · platforms: \((p.platforms ?? ["any"]).joined(separator: ", "))")
                            .font(.caption).foregroundStyle(Theme.secondaryText)
                    }
                    .padding(10).elevatedCard(radius: 8)
                }
                Text("Cross-platform: add Plugins/*.json with \"platforms\": [\"windows\"] or [\"linux\"] and OS-specific paths. The macOS app loads macos/any; the same JSON format is portable to future Windows/Linux agents.")
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
                title("Fleet Export", subtitle: "JSON workstation report for IT / team dashboards. No telemetry — you choose when to share.")
                Text("Includes host, disk free/total, reclaimable safe bytes, top items, env warnings, duplicate waste.")
                    .font(.callout).foregroundStyle(Theme.secondaryText)
                Button("Export fleet report") {
                    if !model.envLoaded { model.loadEnvDoctor() }
                    if !model.duplicatesLoaded { model.loadDuplicates() }
                    model.exportFleetReport()
                }
                .buttonStyle(PrimaryPillButtonStyle())
                if let s = model.fleetStatus {
                    Text(s).font(.caption).foregroundStyle(Theme.secondaryText)
                }
            }
            .padding(14).frame(maxWidth: 900, alignment: .leading)
        }
        .background(Theme.bg)
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
