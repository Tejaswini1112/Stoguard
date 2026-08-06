import SwiftUI

// MARK: - Health Dashboard

struct HealthDashboardView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Developer Health").font(.system(size: 22, weight: .bold))
                        Text(model.healthReport?.headline ?? "Run a scan to score this workstation.")
                            .font(.subheadline).foregroundStyle(Theme.secondaryText)
                    }
                    Spacer()
                    Button("Refresh") { model.refreshIntelligence() }
                        .buttonStyle(SecondaryOutlineButtonStyle())
                }

                if let h = model.healthReport {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(spacing: 6) {
                            Text("\(h.overall)")
                                .font(.system(size: 56, weight: .bold).monospacedDigit())
                                .foregroundStyle(Theme.navy)
                            Text("/ 100").font(.caption).foregroundStyle(Theme.secondaryText)
                            Text("Overall").font(.headline)
                        }
                        .frame(width: 140)
                        .padding()
                        .elevatedCard(radius: 14)

                        VStack(spacing: 10) {
                            ForEach(h.dimensions) { d in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(d.name).font(.system(size: 13, weight: .semibold))
                                        Spacer()
                                        Text("\(d.score)").font(.caption.monospacedDigit())
                                    }
                                    ProgressView(value: Double(d.score), total: 100)
                                        .tint(Theme.navy)
                                    Text(d.detail).font(.caption).foregroundStyle(Theme.secondaryText)
                                }
                                .padding(12)
                                .elevatedCard(radius: 10)
                            }
                        }
                    }

                    sectionTitle("History")
                    HStack(spacing: 12) {
                        historyPill("Today", h.overall)
                        if let w = HealthHistory.averages(periodDays: 7) {
                            historyPill("7-day avg", w.overall)
                        }
                        if let m = HealthHistory.averages(periodDays: 30) {
                            historyPill("30-day avg", m.overall)
                        }
                    }
                    ForEach(Array(HealthHistory.load().suffix(8).reversed())) { s in
                        HStack {
                            Text(s.date, style: .date).font(.caption).foregroundStyle(Theme.secondaryText)
                            Spacer()
                            Text("\(s.overall)").font(.caption.monospacedDigit().weight(.semibold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                    .elevatedCard(radius: 10)
                }

                sectionTitle("Predictive insights")
                if model.predictiveInsights.isEmpty {
                    Text("Scan a few times to unlock forecasts.").foregroundStyle(Theme.secondaryText)
                } else {
                    ForEach(model.predictiveInsights) { p in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(p.title).font(.system(size: 13, weight: .semibold))
                            Text(p.body).font(.caption).foregroundStyle(Theme.secondaryText)
                            HStack {
                                Text(p.severity.uppercased()).font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.secondaryText)
                                if let rate = p.bytesPerDay, abs(rate) > 1_000_000 {
                                    Text(String(format: "%+.2f GB/day", rate / 1e9))
                                        .font(.caption.monospacedDigit())
                                }
                                if let d = p.daysUntilFull {
                                    Text(String(format: "~%.0f days to full", d))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Theme.dangerRed)
                                }
                            }
                        }
                        .padding(12).elevatedCard(radius: 10)
                    }
                }

                if !model.categoryForecasts.isEmpty {
                    sectionTitle("Category growth (30-day window)")
                    ForEach(model.categoryForecasts) { f in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(f.title).font(.system(size: 13, weight: .semibold))
                            Text(f.body).font(.caption).foregroundStyle(Theme.secondaryText)
                        }
                        .padding(12).elevatedCard(radius: 10)
                    }
                }

                if !model.continuousMonitor.watchEvents.isEmpty {
                    sectionTitle("Background watches")
                    ForEach(model.continuousMonitor.watchEvents.prefix(8)) { e in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(e.title).font(.system(size: 13, weight: .semibold))
                            Text(e.body).font(.caption).foregroundStyle(Theme.secondaryText)
                        }
                        .padding(12).elevatedCard(radius: 10)
                    }
                }

                sectionTitle("Proactive alerts")
                if model.proactiveAlerts.isEmpty {
                    Text("No proactive alerts — monitoring will flag growth and critical disk use.")
                        .foregroundStyle(Theme.secondaryText)
                } else {
                    ForEach(model.proactiveAlerts) { a in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(a.title).font(.system(size: 13, weight: .semibold))
                                Text(a.severity.uppercased())
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(a.severity == "critical" ? Theme.dangerRed : Theme.navy)
                                Spacer()
                            }
                            Text(a.explanation).font(.caption).foregroundStyle(Theme.secondaryText)
                            Text(a.recommendation).font(.caption.weight(.medium))
                            if let sec = a.relatedSection {
                                Button("Open \(sec.sidebarLabel)") { model.selectSection(sec) }
                                    .buttonStyle(.link).font(.caption)
                            }
                        }
                        .padding(12).elevatedCard(radius: 10)
                    }
                }

                if model.automation.cloudOptIn {
                    sectionTitle("Cloud cohort knowledge")
                    Text("Baselines + fleet-peer averages + optional remote feed. Opt-in only — no hostname or paths leave the device unless you set a contribute URL.")
                        .font(.caption).foregroundStyle(Theme.secondaryText)
                    HStack {
                        Button("Refresh remote feed") { model.refreshCohortFeed() }
                            .buttonStyle(SecondaryOutlineButtonStyle())
                    }
                    if let s = model.cohortStatus {
                        Text(s).font(.caption2).foregroundStyle(Theme.tertiaryText)
                    }
                    ForEach(model.cloudBenchmarks) { b in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(b.cohort).font(.system(size: 13, weight: .semibold))
                                Text(b.source.uppercased())
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Theme.secondaryText)
                                Spacer()
                            }
                            Text("You \(ByteText.string(b.yourBytes)) · cohort avg \(ByteText.string(b.averageBytes))")
                                .font(.caption).foregroundStyle(Theme.secondaryText)
                            if let n = b.sampleSize {
                                Text("Peer samples: \(n)").font(.caption2).foregroundStyle(Theme.tertiaryText)
                            }
                            Text(b.yourVsAvgText).font(.caption)
                            Text(b.recommendation).font(.caption).foregroundStyle(Theme.navy)
                        }
                        .padding(12).elevatedCard(radius: 10)
                    }
                }
            }
            .padding(20)
        }
        .background(Theme.bg)
        .onAppear { model.refreshIntelligence() }
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t).font(.system(size: 15, weight: .semibold)).padding(.top, 8)
    }

    private func historyPill(_ label: String, _ score: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(score)").font(.title3.monospacedDigit().weight(.bold)).foregroundStyle(Theme.navy)
            Text(label).font(.caption2).foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .elevatedCard(radius: 10)
    }

    private func insightCard(title: String, body: String, severity: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(body).font(.caption).foregroundStyle(Theme.secondaryText)
            Text(severity.uppercased()).font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.secondaryText)
        }
        .padding(12).elevatedCard(radius: 10)
    }
}

// MARK: - Learning Center

struct LearningCenterView: View {
    @EnvironmentObject var model: AppModel
    @State private var query = ""

    private var filtered: [LearningArticle] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return LearningCenter.articles }
        return LearningCenter.articles.filter {
            $0.title.lowercased().contains(q) || $0.category.lowercased().contains(q) || $0.what.lowercased().contains(q)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Learning Center").font(.system(size: 22, weight: .bold))
                Text("Every technical term — what it is, why it exists, when it’s safe to delete.")
                    .font(.subheadline).foregroundStyle(Theme.secondaryText)
                TextField("Search DerivedData, Docker, Ollama…", text: $query)
                    .textFieldStyle(.roundedBorder)
                ForEach(filtered) { a in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(a.title).font(.system(size: 15, weight: .semibold))
                            Text(a.category)
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Theme.navy.opacity(0.12), in: Capsule())
                        }
                        labeled("What is it?", a.what)
                        labeled("Why is it created?", a.whyCreated)
                        labeled("Why is it safe?", a.whySafe)
                        labeled("When should I delete?", a.whenDelete)
                        labeled("What happens after?", a.afterDelete)
                        Button("Ask Stoguard about this") {
                            model.selectSection(.ask)
                            model.seedLearningPrompt(for: a)
                        }
                        .buttonStyle(.link).font(.caption)
                    }
                    .padding(14).elevatedCard(radius: 12)
                }
            }
            .padding(20)
        }
        .background(Theme.bg)
    }

    private func labeled(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.secondaryText)
            Text(body).font(.system(size: 13))
        }
    }
}

// MARK: - Automation

struct AutomationView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Automation").font(.system(size: 22, weight: .bold))
                Text("Scheduled maintenance — scan daily, tidy safe caches on a cadence. Nothing destructive runs without your rules.")
                    .font(.subheadline).foregroundStyle(Theme.secondaryText)

                Toggle("Background monitoring (proactive alerts)", isOn: Binding(
                    get: { model.continuousMonitor.enabled },
                    set: { model.setContinuousMonitoring($0) }
                ))

                Toggle("Opt in to cloud cohort knowledge (anonymous category averages — baselines, fleet peers, optional remote)", isOn: Binding(
                    get: { model.automation.cloudOptIn },
                    set: { model.setCloudOptIn($0) }
                ))
                if model.automation.cloudOptIn {
                    Text(model.cohortStatus ?? "Peers accumulate as you scan / ingest fleet machines. Optional: set stoguard.cohortFeedURL / cohortContributeURL.")
                        .font(.caption).foregroundStyle(Theme.secondaryText)
                    Button("Refresh cohort feed") { model.refreshCohortFeed() }
                        .buttonStyle(SecondaryOutlineButtonStyle())
                }

                ForEach(model.automation.rules) { rule in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(rule.name).font(.system(size: 13, weight: .semibold))
                            Text("\(rule.schedule) · \(rule.action) · min \(ByteText.string(rule.minBytes))")
                                .font(.caption).foregroundStyle(Theme.secondaryText)
                            if let last = rule.lastRun {
                                Text("Last run \(last.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption2).foregroundStyle(Theme.tertiaryText)
                            }
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { rule.enabled },
                            set: { model.setAutomationRule(id: rule.id, enabled: $0) }
                        ))
                        .labelsHidden()
                    }
                    .padding(12).elevatedCard(radius: 10)
                }

                Button("Run due automation now") { model.runDueAutomation() }
                    .buttonStyle(PrimaryPillButtonStyle())
            }
            .padding(20)
        }
        .background(Theme.bg)
        .onAppear { model.refreshIntelligence() }
    }
}
