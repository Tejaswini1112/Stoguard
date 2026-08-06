import SwiftUI

struct DoctorReportView: View {
    @EnvironmentObject var model: AppModel

    private var report: DoctorReport { model.doctorReport }
    private var hasScan: Bool { !model.items.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if hasScan {
                    summaryCard
                    if !report.growth.isEmpty { growthSection }
                    if !report.timeline.isEmpty { timelineSection }
                    recommendationsSection
                    largestFilesSection
                    engineFooter
                } else if model.isScanning {
                    scanningCard
                } else {
                    emptyCard
                }
            }
            .padding(14)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.bg)
        .onAppear {
            if hasScan && report.recommendations.isEmpty {
                // Rebuild if we navigated here after a partial refresh.
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Workstation Doctor")
                .font(.system(size: 22, weight: .bold))
                .displayTitle()
            Text("Explain → teach → act. Every recommendation tells you what a term means before you delete anything.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DIAGNOSIS")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(Theme.heroSubtext)

            Text(report.headline)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.heroText)
                .displayTitle()

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(report.summaryLines.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .top, spacing: 8) {
                        Text("·")
                            .foregroundStyle(Theme.heroSubtext)
                        Text(line)
                            .font(.callout)
                            .foregroundStyle(Theme.heroText.opacity(0.88))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            HStack(spacing: 16) {
                metric(label: "Safe", value: ByteText.string(report.reclaimableSafe))
                metric(label: "Review", value: ByteText.string(report.reclaimableCheck))
            }

            HStack(spacing: 10) {
                if report.reclaimableSafe > 0 {
                    Button {
                        model.requestCleanAllSafe()
                    } label: {
                        Text("Clean safe \(ByteText.string(report.reclaimableSafe))")
                    }
                    .buttonStyle(PrimaryPillButtonStyle(inverted: true))
                }
                Button {
                    model.selectSection(.ask)
                    model.askWhySSDFull()
                } label: {
                    Text("Why is my SSD full?")
                }
                .buttonStyle(SecondaryOutlineButtonStyle(lightOnDark: true))
                Spacer(minLength: 0)
                Button {
                    model.scan(section: nil)
                } label: {
                    Text(model.isScanning ? "Scanning…" : "Rescan")
                }
                .buttonStyle(SecondaryOutlineButtonStyle(lightOnDark: true))
                .disabled(model.isScanning)
            }
            .padding(.top, 4)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(
                    colors: [Theme.heroTop, Theme.heroBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        )
    }

    private func metric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(Theme.heroSubtext)
            Text(value)
                .font(.system(size: 16, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.heroText)
        }
    }

    private var growthSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Storage changes").font(.headline)
            Text("Compared with your previous scan.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)

            ForEach(report.growth.prefix(6)) { insight in
                HStack(alignment: .top, spacing: 10) {
                    Text(insight.deltaText)
                        .font(.system(size: 13, weight: .bold).monospacedDigit())
                        .foregroundStyle(insight.deltaBytes >= 0 ? Theme.navy : Theme.safeGreen)
                        .frame(width: 72, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(insight.category)
                            .font(.system(size: 13, weight: .semibold))
                        Text(insight.detail)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .elevatedCard(radius: 10)
            }
        }
    }

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Storage timeline").font(.headline)
            Text("Safe-to-clean totals from recent scans.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)

            GeometryReader { geo in
                let entries = Array(report.timeline.suffix(10))
                let maxVal = max(entries.map(\.reclaimableSafe).max() ?? 1, 1)
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(entries) { entry in
                        let h = max(4, CGFloat(entry.reclaimableSafe) / CGFloat(maxVal) * 56)
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Theme.navy.opacity(0.75))
                                .frame(width: max(10, (geo.size.width - 40) / CGFloat(max(entries.count, 1)) - 6), height: h)
                            Text(shortDate(entry.date))
                                .font(.system(size: 8))
                                .foregroundStyle(Theme.tertiaryText)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            .frame(height: 88)
            .padding(12)
            .elevatedCard(radius: 10)
        }
    }

    private var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recommendations").font(.headline)
            if report.recommendations.isEmpty {
                Text("No strong recommendations yet — your machine looks tidy, or items need a closer look in categories.")
                    .font(.callout)
                    .foregroundStyle(Theme.secondaryText)
                    .padding(12)
                    .elevatedCard(radius: 10)
            } else {
                ForEach(report.recommendations) { rec in
                    RecommendationCard(rec: rec)
                }
            }
        }
    }

    private var largestFilesSection: some View {
        let big = model.items
            .filter { !$0.largestChildren.isEmpty }
            .sorted { $0.sizeBytes > $1.sizeBytes }
            .prefix(8)

        return Group {
            if !big.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Largest files inside hotspots").font(.headline)
                    Text("Click a child to reveal it in Finder.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)

                    ForEach(Array(big)) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(item.name)
                                    .font(.system(size: 13, weight: .semibold))
                                Spacer()
                                Text(item.sizeText)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(Theme.secondaryText)
                            }
                            ForEach(item.largestChildren) { child in
                                Button {
                                    model.revealInFinder(child.path)
                                } label: {
                                    HStack {
                                        Image(systemName: "doc.fill")
                                            .font(.system(size: 10))
                                            .foregroundStyle(Theme.secondaryText)
                                        Text(child.name)
                                            .font(.system(size: 12))
                                            .foregroundStyle(Theme.primaryText)
                                            .lineLimit(1)
                                        Spacer()
                                        Text(child.sizeText)
                                            .font(.system(size: 11).monospacedDigit())
                                            .foregroundStyle(Theme.secondaryText)
                                        Image(systemName: "arrow.right.circle")
                                            .font(.system(size: 11))
                                            .foregroundStyle(Theme.tertiaryText)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(12)
                        .elevatedCard(radius: 10)
                    }
                }
            }
        }
    }

    private var engineFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scan engine")
                .font(.headline)
            HStack(spacing: 16) {
                Label("\(model.lastScanCacheHits) cache hits", systemImage: "bolt.fill")
                Label("\(model.adaptiveSkippedCount) paths skipped", systemImage: "eye.slash")
            }
            .font(.caption)
            .foregroundStyle(Theme.secondaryText)

            Text("Unused tool paths are skipped after \(AdaptiveProfile.autoSkipAfterMisses) empty scans. Fingerprints avoid re-measuring unchanged folders.")
                .font(.caption)
                .foregroundStyle(Theme.tertiaryText)

            if model.adaptiveSkippedCount > 0 {
                Button("Reset skipped paths") {
                    model.resetAdaptiveSkips()
                }
                .buttonStyle(SecondaryOutlineButtonStyle())
            }
        }
        .padding(12)
        .elevatedCard(radius: 10)
    }

    private var scanningCard: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Diagnosing workstation… parallel scan in progress.")
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 72)
        .elevatedCard()
    }

    private var emptyCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "stethoscope")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Theme.navy.opacity(0.5))
            Text("No diagnosis yet").font(.headline)
            Text("Run a full scan. Doctor will explain what grew, what's idle, and what's safe to reclaim — with plain-English terms.")
                .font(.callout)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
            Button { model.scan(section: nil) } label: {
                Text("Analyze my Mac")
            }
            .buttonStyle(PrimaryPillButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .elevatedCard()
    }

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f.string(from: date)
    }
}

private struct RecommendationCard: View {
    @EnvironmentObject var model: AppModel
    let rec: DoctorRecommendation
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(rec.title)
                        .font(.system(size: 14, weight: .semibold))
                    if let days = rec.daysUnused {
                        Text("Idle ~\(days) days · \(rec.bytesText)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.secondaryText)
                    } else {
                        Text(rec.bytesText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                Spacer()
                actionButton
            }

            Text(rec.advice)
                .font(.callout)
                .foregroundStyle(Theme.primaryText)

            Button {
                withAnimation(Theme.easeOut) { expanded.toggle() }
            } label: {
                Label(expanded ? "Hide explanation" : "What does this mean?", systemImage: expanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.navy)
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text(rec.explanation)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    if let ex = rec.explainability {
                        explainRow("Why?", ex.why)
                        explainRow("What happens if I do this?", ex.whatHappens)
                        explainRow("Can I undo it?", ex.canUndo)
                        explainRow("What rebuilds automatically?", ex.whatRebuilds)
                        explainRow("Is this common?", ex.isCommon)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.navy.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(12)
        .elevatedCard(radius: 10)
    }

    private func explainRow(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.navy.opacity(0.8))
            Text(body).font(.caption).foregroundStyle(Theme.secondaryText).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch rec.action {
        case .trashSafe:
            Button {
                model.requestTrashRecommendation(rec)
            } label: {
                Text("Trash")
            }
            .buttonStyle(DestructivePillButtonStyle())
        case .runCommand:
            Button {
                model.requestTrashRecommendation(rec)
            } label: {
                Text("Copy CLI")
            }
            .buttonStyle(SecondaryOutlineButtonStyle())
        case .review, .info:
            Button {
                model.requestTrashRecommendation(rec)
            } label: {
                Text("Review")
            }
            .buttonStyle(SecondaryOutlineButtonStyle())
        }
    }
}
