import SwiftUI
import AppKit

struct AboutView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                checkUpdatesRow
                lifetimeCard
                comparisonCard
                whatWeCleanCard
                legalCard
                actionList
                footer
            }
            .padding(20)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.bg)
    }

    private var header: some View {
        VStack(spacing: 10) {
            AppMark(size: 72)
            Text(AppInfo.name)
                .font(.system(size: 28, weight: .bold))
                .displayTitle()
            Text(AppInfo.tagline)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
            Text("Version \(AppInfo.versionLabel)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.tertiaryText)
        }
        .padding(.top, 8)
    }

    private var checkUpdatesRow: some View {
        AboutActionRow(icon: "arrow.clockwise", title: "Check for updates") {
            if let url = AppInfo.releasesURL {
                NSWorkspace.shared.open(url)
            } else {
                model.pathSafetyNotice = "Stoguard updates ship with the download site — no third-party GitHub release page is linked yet."
            }
        }
    }

    private var lifetimeCard: some View {
        VStack(spacing: 10) {
            Text("LIFETIME MOVED TO TRASH")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(Theme.tertiaryText)

            Text(ByteText.string(model.lifetimeTrashedBytes))
                .font(.system(size: 36, weight: .bold))
                .monospacedDigit()
                .displayTitle()

            if model.lifetimeTrashedBytes > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "internaldrive")
                        .font(.system(size: 11))
                    Text(AppInfo.sizeAnalogy(for: model.lifetimeTrashedBytes))
                        .font(.caption)
                }
                .foregroundStyle(Theme.secondaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Theme.elevated, in: Capsule())
            } else {
                Text("Nothing trashed yet — your first clean will show up here.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .softTintCard()
    }

    private var comparisonCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("HOW STOGUARD COMPARES")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.tertiaryText)
                Text("Feature comparison against other Mac cleaners.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }

            ComparisonTableView(rows: AppInfo.toolComparisons)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .softTintCard()
    }

    private var whatWeCleanCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("WHAT STOGUARD CAN CLEAN")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(Theme.tertiaryText)

            ForEach(Array(AppInfo.cleanCategories.enumerated()), id: \.offset) { _, cat in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: cat.icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.navy)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cat.title)
                            .font(.system(size: 13, weight: .semibold))
                        Text(cat.detail)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Text("Stoguard never uses admin privileges for normal cleanup, prefers Trash over permanent delete, and explains each cache before you act. Personal documents, photos, and project source code are never targeted.")
                .font(.caption2)
                .foregroundStyle(Theme.tertiaryText)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .softTintCard()
    }

    private var legalCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LICENSE & USE")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(Theme.tertiaryText)

            Text(AppInfo.licenseNotice)
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .softTintCard()
    }

    private var actionList: some View {
        VStack(spacing: 8) {
            AboutActionRow(icon: "chevron.left.forwardslash.chevron.right", title: "View the full allowlist") {
                if let url = AppInfo.allowlistURL {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
            if let bugURL = AppInfo.bugReportURL {
                AboutActionRow(icon: "ladybug", title: "Report a bug") {
                    NSWorkspace.shared.open(bugURL)
                }
            }
            AboutActionRow(icon: "arrow.counterclockwise", title: "Replay onboarding") {
                model.showOnboarding = true
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text("Made by \(AppInfo.author)")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
            Text("Version \(AppInfo.versionLabel) · \(AppInfo.licenseName)")
                .font(.caption2)
                .foregroundStyle(Theme.tertiaryText)
            Text("© \(AppInfo.copyrightYear) \(AppInfo.author). Unauthorized copying prohibited.")
                .font(.caption2)
                .foregroundStyle(Theme.tertiaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
        .padding(.bottom, 16)
    }
}

private struct AboutActionRow: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 22)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.tertiaryText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.hairline.opacity(0.72), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Comparison table

private struct ComparisonTableView: View {
    let rows: [ToolComparisonRow]

    private let columns = ["Stoguard", "Purge", "macOS", "CMM"]
    private let colWidth: CGFloat = 54

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                ComparisonLegend(symbol: "✓", label: "Full", color: Theme.navy)
                ComparisonLegend(symbol: "~", label: "Partial", color: .orange)
                ComparisonLegend(symbol: "—", label: "None", color: Theme.tertiaryText)
            }

            VStack(spacing: 0) {
                headerRow
                Divider()
                ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                    ComparisonTableRow(
                        row: row,
                        colWidth: colWidth,
                        isEven: idx.isMultiple(of: 2)
                    )
                    if idx < rows.count - 1 { Divider() }
                }
            }
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.hairline.opacity(0.72), lineWidth: 1)
            )
        }
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            Text("Feature")
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(Array(columns.enumerated()), id: \.offset) { idx, title in
                Text(title)
                    .frame(width: colWidth)
                    .multilineTextAlignment(.center)
                    .background(idx == 0 ? Theme.navy.opacity(0.06) : Color.clear)
            }
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(Theme.tertiaryText)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.elevated.opacity(0.65))
    }
}

private struct ComparisonLegend: View {
    let symbol: String
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Text(symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Theme.secondaryText)
        }
    }
}

private struct ComparisonTableRow: View {
    let row: ToolComparisonRow
    let colWidth: CGFloat
    let isEven: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                Text(row.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 8)

            ComparisonCell(strength: row.vacs, colWidth: colWidth, emphasized: true)
            ComparisonCell(strength: row.purge, colWidth: colWidth, emphasized: false)
            ComparisonCell(strength: row.macOS, colWidth: colWidth, emphasized: false)
            ComparisonCell(strength: row.cleanMyMac, colWidth: colWidth, emphasized: false)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isEven ? Color.clear : Theme.elevated.opacity(0.35))
    }
}

private struct ComparisonCell: View {
    let strength: ComparisonStrength
    let colWidth: CGFloat
    let emphasized: Bool

    var body: some View {
        Text(symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: colWidth, height: 32)
            .background(
                emphasized ? Theme.navy.opacity(0.07) : Color.clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
    }

    private var symbol: String {
        switch strength {
        case .strong: return "✓"
        case .partial: return "~"
        case .none: return "—"
        }
    }

    private var color: Color {
        switch strength {
        case .strong: return emphasized ? Theme.navy : Theme.safeGreen
        case .partial: return .orange
        case .none: return Theme.tertiaryText.opacity(0.55)
        }
    }
}
