import SwiftUI

struct SectionDetailView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if model.canNavigateBack {
                SectionBackBar()
            }

            Group {
                switch model.selectedSection {
                case .overview: OverviewView()
                case .doctor: DoctorReportView()
                case .ask: AskStoguardView()
                case .pulse: SystemPulseView()
                case .envDoctor: EnvDoctorView()
                case .buildTrends: BuildTrendsView()
                case .aiCleanup: AICleanupView()
                case .aiModels: AIModelsView()
                case .duplicates: DuplicatesView()
                case .packageFinder: PackageFinderView()
                case .agentTools: AgentToolsView()
                case .gitRepos: GitReposView()
                case .codebase: CodebaseView()
                case .rulesPlugins: RulesPluginsView()
                case .fleet: FleetExportView()
                case .installedApps: InstalledAppsView()
                case .about: AboutView()
                case .trash: TrashView()
                default: CategoryDetailView()
                }
            }
        }
        .background(BackNavigationCapture())
        .id(model.selectedSection)
        .transition(.opacity)
        .animation(Theme.easeOut, value: model.selectedSection)
    }
}

private struct CategoryDetailView: View {
    @EnvironmentObject var model: AppModel

    private var section: AppSection { model.selectedSection }
    private var isScanningThis: Bool {
        model.isScanning && (model.scanningSection == section || model.scanningSection == nil)
    }
    private var hasResults: Bool { model.scannedSections.contains(section) }

    var body: some View {
        VStack(spacing: 0) {
            compactHeader
            if hasResults {
                CategorySplitView(section: section)
            } else if isScanningThis {
                Spacer()
                ProgressView("Measuring…").controlSize(.small)
                Spacer()
            } else {
                notScannedState
            }
        }
        .background(Theme.bg)
    }

    private var compactHeader: some View {
        HStack(spacing: 10) {
            SectionIconBadge(section: section, size: 28, filled: true)
            VStack(alignment: .leading, spacing: 1) {
                Text(section.rawValue).font(.system(size: 15, weight: .semibold))
                if hasResults {
                    Text("\(model.itemCount(for: section)) items · \(ByteText.string(model.totalBytes(for: section)))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.secondaryText)
                } else {
                    Text(section.blurb).font(.caption).foregroundStyle(Theme.secondaryText).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if model.isCleaning {
                BusyIndicator(label: "Cleaning…")
            }
            Button { model.scan(section: section) } label: {
                HStack(spacing: 6) {
                    if isScanningThis {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Image(systemName: hasResults ? "arrow.clockwise" : "magnifyingglass")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    Text(isScanningThis ? "Scanning…" : (hasResults ? "Rescan" : "Scan"))
                }
            }
            .buttonStyle(PrimaryPillButtonStyle())
            .disabled(model.isScanning || model.isCleaning)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.card)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var notScannedState: some View {
        VStack(spacing: 12) {
            Spacer()
            SectionIconBadge(section: section, size: 36, filled: true)
            Text("Not scanned yet").font(.headline)
            Button { model.scan(section: section) } label: { Text("Scan now") }
                .buttonStyle(PrimaryPillButtonStyle())
                .disabled(model.isScanning)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
