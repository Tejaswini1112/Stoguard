import SwiftUI
import AppKit

struct InstalledAppsView: View {
    @EnvironmentObject var model: AppModel

    private var hasDetail: Bool {
        if case .installedApp = model.detailTarget { return true }
        return false
    }

    var body: some View {
        Group {
            if hasDetail {
                HSplitView {
                    appListPane.frame(minWidth: 240, idealWidth: 280)
                    detailPane
                        .frame(minWidth: 280)
                        .detailTransition(active: hasDetail)
                }
            } else {
                appListPane
            }
        }
        .background(Theme.bg)
        .onAppear {
            if !model.installedAppsLoaded { model.loadInstalledApps() }
        }
    }

    private var appListPane: some View {
        VStack(spacing: 0) {
            compactHeader

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                TextField("Search apps", text: $model.appSearchQuery)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline.opacity(0.35), lineWidth: 0.5))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            HStack {
                Text("\(model.filteredInstalledApps.count) apps")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                Picker("Sort", selection: $model.sortOrder) {
                    ForEach(SortOrder.allCases) { s in Text(s.rawValue).tag(s) }
                }
                .pickerStyle(.menu)
                .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)

            if model.isLoadingApps && !model.installedAppsLoaded {
                Spacer()
                ProgressView("Loading…").controlSize(.small)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.filteredInstalledApps) { app in
                            appRow(app)
                            if app.id != model.filteredInstalledApps.last?.id {
                                Divider().padding(.leading, 48)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                }
            }
        }
    }

    private var compactHeader: some View {
        HStack(spacing: 10) {
            SectionIconBadge(section: .installedApps, size: 28, filled: true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Installed Apps")
                    .font(.system(size: 15, weight: .semibold))
                if model.installedAppsLoaded {
                    Text("\(model.installedApps.count) apps")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            Spacer()
            Button { model.loadInstalledApps() } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(SecondaryOutlineButtonStyle())
            .disabled(model.isLoadingApps)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func appRow(_ app: InstalledApp) -> some View {
        let selected = {
            if case .installedApp(let a) = model.detailTarget { a.id == app.id }
            else { false }
        }()

        Button { model.openInstalledAppDetail(app) } label: {
            HStack(spacing: 10) {
                Image(nsImage: AppScanner.appIcon(for: app.appPath))
                    .resizable().aspectRatio(contentMode: .fit).frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    if let bid = app.bundleID {
                        Text(bid).font(.system(size: 9.5).monospaced()).foregroundStyle(Theme.tertiaryText).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                Text(app.sizeText).font(.system(size: 12, weight: .semibold).monospacedDigit())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Theme.navy.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(NavRowButtonStyle())
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var detailPane: some View {
        if case .installedApp(let app) = model.detailTarget {
            DetailPanelView(
                title: app.name, subtitle: app.bundleID,
                icon: AppScanner.appIcon(for: app.appPath), systemIcon: nil,
                groups: model.detailGroups,
                selectedPaths: $model.detailSelectedPaths,
                isLoading: model.isLoadingDetail,
                installedApp: app
            )
        }
    }
}
