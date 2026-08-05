import SwiftUI

struct OverviewView: View {
    @EnvironmentObject var model: AppModel

    private var hasResults: Bool { !model.items.isEmpty || !model.overviewRows.isEmpty }
    private var report: DoctorReport { model.doctorReport }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Smart Scan")
                        .font(.system(size: 22, weight: .bold))
                        .displayTitle()
                    Text("Choose what to keep, then clean in one pass — or open Doctor for a full diagnosis.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }

                SmartCareHero(hasScanResults: hasResults)

                if hasResults {
                    healthTeaser
                    doctorTeaser
                    reviewSection
                } else if model.isScanning && model.scanningSection == nil {
                    scanningPlaceholder
                } else {
                    emptyHero
                }
            }
            .padding(14)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.bg)
    }

    private var healthTeaser: some View {
        HStack(spacing: 14) {
            VStack(spacing: 2) {
                Text(model.healthReport.map { "\($0.overall)" } ?? "—")
                    .font(.system(size: 36, weight: .bold).monospacedDigit())
                    .foregroundStyle(Theme.navy)
                Text("Health").font(.caption).foregroundStyle(Theme.secondaryText)
            }
            .frame(width: 72)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.healthReport?.headline ?? "Scan to unlock your health score.")
                    .font(.system(size: 13, weight: .semibold))
                if let tip = model.predictiveInsights.first {
                    Text(tip.title).font(.caption).foregroundStyle(Theme.secondaryText)
                } else if let alert = model.proactiveAlerts.first {
                    Text(alert.title).font(.caption).foregroundStyle(Theme.secondaryText)
                }
            }
            Spacer()
            Button("Health") { model.selectSection(.health) }
                .buttonStyle(SecondaryOutlineButtonStyle())
        }
        .padding(12)
        .elevatedCard(radius: 12)
        .onAppear { model.refreshIntelligence() }
    }

    private var doctorTeaser: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Workstation Doctor", systemImage: "stethoscope")
                    .font(.headline)
                Spacer()
                Button("Ask why") {
                    model.selectSection(.ask)
                    model.askWhySSDFull()
                }
                .buttonStyle(GhostButtonStyle())
                Button("Open report") {
                    model.selectSection(.doctor)
                }
                .buttonStyle(SecondaryOutlineButtonStyle())
            }

            Text(report.headline)
                .font(.system(size: 15, weight: .semibold))

            if let line = report.summaryLines.first {
                Text(line)
                    .font(.callout)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let top = report.recommendations.first {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb")
                        .foregroundStyle(Theme.navy)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(top.title)
                            .font(.system(size: 13, weight: .semibold))
                        Text(top.advice)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.navy.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            if !report.growth.isEmpty, let g = report.growth.first {
                Text("Recent change: \(g.category) \(g.deltaText)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(12)
        .elevatedCard(radius: 10)
    }

    private var reviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Review what was found").font(.headline)

            OverviewSelectionBar()

            Text("Tap items to include or skip. Category checkbox selects all safe items in that group.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 10)],
                spacing: 10
            ) {
                ForEach(model.overviewRows, id: \.section) { row in
                    CategoryReviewCard(
                        section: row.section,
                        total: row.total,
                        safe: row.safe,
                        itemCount: model.itemCount(for: row.section),
                        safeItems: model.safeItems(for: row.section),
                        allItems: model.items(for: row.section),
                        onReview: { model.selectSection(row.section) }
                    )
                }
            }
        }
    }

    private var scanningPlaceholder: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Measuring folders in parallel…").foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .elevatedCard()
    }

    private var emptyHero: some View {
        VStack(spacing: 12) {
            Image(systemName: "internaldrive")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Theme.navy.opacity(0.5))
            Text("Run your first scan").font(.headline)
            Text("Stoguard measures every dev cache, explains what it is, and notes what's safe to reclaim.")
                .font(.callout)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
            Button { model.scan(section: nil) } label: {
                Text("Scan all categories")
            }
            .buttonStyle(PrimaryPillButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .elevatedCard()
    }
}
