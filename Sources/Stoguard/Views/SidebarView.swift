import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                AppMark(size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(AppInfo.name)
                        .font(.system(size: 14, weight: .bold))
                    Text("\(model.ruleCount) paths")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    sectionHeader("Overview")
                    SidebarNavRow(section: .overview)

                    sectionHeader("Insights")
                    ForEach(AppSection.insightTools) { section in
                        SidebarNavRow(section: section)
                    }

                    sectionHeader("Optimize")
                    ForEach(AppSection.optimizeTools) { section in
                        SidebarNavRow(section: section)
                    }

                    sectionHeader("Platform")
                    ForEach(AppSection.platformTools) { section in
                        SidebarNavRow(section: section)
                    }

                    sectionHeader("Applications")
                    SidebarNavRow(section: .installedApps)

                    sectionHeader("Cleanup")
                    sectionHeader("Advanced Tools", subtle: true)
                    ForEach(AppSection.advancedTools) { section in
                        SidebarNavRow(section: section)
                    }
                    sectionHeader("More", subtle: true)
                    ForEach(AppSection.generalCleanup) { section in
                        SidebarNavRow(section: section)
                    }
                    SidebarNavRow(section: .trash)

                    sectionHeader("App")
                    SidebarNavRow(section: .about)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            SidebarStorageCard()
        }
        .frame(maxHeight: .infinity)
        .background(Theme.elevated)
    }

    private func sectionHeader(_ title: String, subtle: Bool = false) -> some View {
        Text(title.uppercased())
            .font(.system(size: subtle ? 9 : 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(subtle ? Theme.tertiaryText.opacity(0.85) : Theme.tertiaryText)
            .padding(.horizontal, 8)
            .padding(.top, subtle ? 6 : 10)
            .padding(.bottom, 4)
    }
}

private struct SidebarNavRow: View {
    @EnvironmentObject var model: AppModel
    let section: AppSection

    private var isSelected: Bool { model.selectedSection == section }

    var body: some View {
        Button {
            model.selectSection(section)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: section.icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? Theme.navy : Theme.secondaryText)
                    .frame(width: 18, alignment: .center)

                Text(section.sidebarLabel)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Theme.primaryText : Theme.secondaryText)
                    .lineLimit(1)

                Spacer(minLength: 4)

                badgeText
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(SidebarNavButtonStyle(isSelected: isSelected))
    }

    @ViewBuilder
    private var badgeText: some View {
        if section == .installedApps, model.installedAppsLoaded {
            Text("\(model.installedApps.count)")
        } else if section == .trash, model.trashTotalBytes > 0 {
            Text(ByteText.storage(model.trashTotalBytes))
        } else if section.ruleCategory != nil, model.scannedSections.contains(section) {
            let total = model.totalBytes(for: section)
            if total > 0 {
                Text(ByteText.string(total))
            }
        }
    }
}
