import Foundation
import AppKit
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var items: [ScanItem] = []
    @Published var isScanning = false
    @Published var isCleaning = false
    @Published var scanningSection: AppSection?
    @Published var selection: Set<String> = []
    @Published var freeBytes: Int64 = 0
    @Published var totalBytes: Int64 = 0
    @Published var lastCleanedBytes: Int64 = 0
    @Published var lifetimeTrashedBytes: Int64 = {
        if let s = UserDefaults.standard.string(forKey: "lifetimeTrashedBytes"), let v = Int64(s) { return v }
        return Int64(UserDefaults.standard.integer(forKey: "lifetimeTrashedBytes"))
    }()
    @Published var showOnboarding = false
    @Published var selectedSection: AppSection = .overview
    @Published var safetyFilter: SafetyFilter = .all
    @Published var sortOrder: SortOrder = .largest
    @Published var hasFullDiskAccess = false
    @Published private(set) var scannedSections: Set<AppSection> = []

    // Drill-down panel (PureMac-style)
    @Published var detailTarget: DetailTarget?
    @Published var detailGroups: [FileGroup] = []
    @Published var detailSelectedPaths: Set<String> = []
    @Published var isLoadingDetail = false
    @Published var detailBreadcrumbs: [DetailBreadcrumb] = []
    /// Installed-app root shows grouped caches/support; drilled folders show flat contents.
    @Published private(set) var detailShowsGroupedRoot = false

    // Installed apps
    @Published var installedApps: [InstalledApp] = []
    @Published var installedAppsLoaded = false
    @Published var isLoadingApps = false
    @Published var appSearchQuery = ""

    /// macOS Trash (~/.Trash) — browse, restore, or permanently delete.
    @Published var trashItems: [TrashItem] = []
    @Published var trashRestoreNotice: String?
    @Published var trashSelection: Set<String> = []
    @Published var isLoadingTrash = false
    @Published var trashTotalBytes: Int64 = 0
    @Published var trashLoaded = false

    /// Category cards selected on Overview (PureMac Smart Care).
    @Published var overviewSelectedSections: Set<AppSection> = []

    /// Workstation Doctor report (generated after each full scan).
    @Published var doctorReport: DoctorReport = .empty
    @Published var lastScanCacheHits: Int = 0
    @Published var lastScanSkippedRules: Int = 0
    @Published var pathSafetyNotice: String?

    // Platform labs
    @Published var chatMessages: [WorkstationChat.Message] = []
    @Published var chatInput: String = ""
    @Published var chatBusy = false
    @Published var systemPulse: SystemPulse?
    @Published var envFindings: [EnvFinding] = []
    @Published var envLoaded = false
    @Published var isLoadingEnv = false
    @Published var duplicateGroups: [DuplicateGroup] = []
    @Published var duplicatesLoaded = false
    @Published var isLoadingDuplicates = false
    @Published var packageFindings: [PackageFinding] = []
    @Published var packagesLoaded = false
    @Published var isLoadingPackages = false
    @Published var agentToolFindings: [AgentToolFinding] = []
    @Published var agentToolsLoaded = false
    @Published var isLoadingAgentTools = false
    @Published var aiModels: [AIModelEntry] = []
    @Published var modelsLoaded = false
    @Published var isLoadingModels = false
    @Published var gitReports: [GitRepoReport] = []
    @Published var gitLoaded = false
    @Published var isLoadingGit = false
    @Published var codebasePath: String = NSHomeDirectory() + "/Developer"
    @Published var codebaseFindings: [CodebaseFinding] = []
    @Published var isLoadingCodebase = false
    @Published var buildTrends = BuildTrendStore.load()
    @Published var rulesMeta: CloudRules.Meta?
    @Published var rulesRefreshing = false
    @Published var rulesStatus: String?
    @Published var plugins: [PluginLoader.PluginFile] = []
    @Published var fleetExportURL: URL?
    @Published var fleetStatus: String?
    @Published var useOllamaChat: Bool = UserDefaults.standard.bool(forKey: "stoguard.useOllamaChat")
    @Published var monitorAlert: String?

    /// Shown before any trash operation — user must confirm every time.
    @Published var cleanPrompt: CleanPrompt?

    private var scanner = Scanner(rules: Scanner.loadRules())
    private let permission = PermissionChecker()
    private var fingerprintCache = ScanFingerprintCache.load()
    private var adaptiveProfile = AdaptiveProfile.load()
    private var scanHistory = ScanHistoryStore.load()
    let continuousMonitor = ContinuousMonitor()

    var ruleCount: Int { scanner.rules.count }
    var adaptiveSkippedCount: Int { adaptiveProfile.autoSkippedCount }
    var scanHistoryEntries: [ScanHistoryEntry] { scanHistory.entries }

    var reclaimableSafe: Int64 {
        items.filter { $0.safety == .safe }.reduce(0) { $0 + $1.sizeBytes }
    }

    var overviewSelectedSafeBytes: Int64 {
        items.filter { selection.contains($0.id) && $0.safety == .safe }
            .reduce(0) { $0 + $1.sizeBytes }
    }

    var overviewVisibleSections: [AppSection] {
        overviewRows.map(\.section)
    }

    var overviewSelectedCount: Int {
        overviewVisibleSections.filter { selectedSafeBytes(in: $0) > 0 }.count
    }

    var overviewAllSelected: Bool {
        let visible = overviewVisibleSections
        guard !visible.isEmpty else { return false }
        return visible.allSatisfy { section in
            let safe = safeItems(for: section)
            return safe.isEmpty || safe.allSatisfy { selection.contains($0.id) }
        }
    }

    func selectAllOverviewSections() {
        for section in overviewVisibleSections {
            selectAllSafe(in: section)
        }
    }

    func deselectAllOverviewSections() {
        for section in overviewVisibleSections {
            deselectAllSafe(in: section)
        }
    }

    func selectAllSafe(in section: AppSection) {
        for item in safeItems(for: section) { selection.insert(item.id) }
        if !safeItems(for: section).isEmpty {
            overviewSelectedSections.insert(section)
        }
    }

    func deselectAllSafe(in section: AppSection) {
        for item in safeItems(for: section) { selection.remove(item.id) }
        overviewSelectedSections.remove(section)
    }

    func deselectAllOverview(in section: AppSection) {
        for item in items(for: section) where canToggleInOverview(item) {
            selection.remove(item.id)
        }
        overviewSelectedSections.remove(section)
    }

    func toggleItemSelection(_ item: ScanItem) {
        guard item.safety == .safe || item.safety == .check else { return }
        if selection.contains(item.id) { selection.remove(item.id) }
        else { selection.insert(item.id) }
        if item.safety == .safe {
            syncOverviewSection(forCategory: item.category)
        }
    }

    func canToggleInOverview(_ item: ScanItem) -> Bool {
        item.safety == .safe || item.safety == .check
    }

    func isItemSelected(_ item: ScanItem) -> Bool {
        selection.contains(item.id)
    }

    func overviewSectionAllSafeSelected(_ section: AppSection) -> Bool {
        let safe = safeItems(for: section)
        return !safe.isEmpty && safe.allSatisfy { selection.contains($0.id) }
    }

    private func syncOverviewSection(forCategory category: String) {
        guard let section = AppSection.section(forCategory: category) else { return }
        if safeItems(for: section).contains(where: { selection.contains($0.id) }) {
            overviewSelectedSections.insert(section)
        } else {
            overviewSelectedSections.remove(section)
        }
    }

    func recordTrashReclaimed(_ bytes: Int64) {
        guard bytes > 0 else { return }
        lastCleanedBytes += bytes
        lifetimeTrashedBytes += bytes
        UserDefaults.standard.set(String(lifetimeTrashedBytes), forKey: "lifetimeTrashedBytes")
    }

    func itemCount(for section: AppSection) -> Int {
        items(for: section).count
    }

    func cleanOverviewSelected() async {
        for section in overviewSelectedSections {
            await cleanSafe(in: section)
        }
    }

    // MARK: - Trash confirmation (always prompt before moving to Trash)

    func requestTrash(_ targets: [ScanItem]) {
        guard !targets.isEmpty else { return }
        let bytes = targets.reduce(0) { $0 + $1.sizeBytes }
        cleanPrompt = .scanItems(
            targets,
            summary: "\(targets.count) items · \(ByteText.string(bytes))"
        )
    }

    func requestTrash(_ item: ScanItem) { requestTrash([item]) }

    func requestCleanAllSafe() {
        requestTrash(items.filter { $0.safety == .safe })
    }

    func requestCleanSafeSelected() {
        requestTrash(items.filter { selection.contains($0.id) && $0.safety == .safe })
    }

    func requestCleanOverviewSelected() {
        requestTrash(items.filter { selection.contains($0.id) && $0.safety == .safe })
    }

    func requestCleanSelected(in section: AppSection) {
        requestTrash(items(for: section).filter { selection.contains($0.id) && $0.safety == .safe })
    }

    func requestCleanSafe(in section: AppSection) {
        requestTrash(items(for: section).filter { $0.safety == .safe })
    }

    func requestTrashDetailSelection() {
        let paths = detailSelectedPaths
        guard !paths.isEmpty else { return }
        let entries = detailGroups.flatMap(\.entries).filter { paths.contains($0.id) }
        let bytes = entries.reduce(0) { $0 + $1.sizeBytes }
        cleanPrompt = .detailPaths(
            paths: paths,
            summary: "\(entries.count) files · \(ByteText.string(bytes))"
        )
    }

    func requestUninstall(appOnly: Bool) {
        guard case .installedApp(let app) = detailTarget, !app.isSystemApp else { return }
        let paths: Set<String> = appOnly
            ? [app.appPath]
            : Set(detailGroups.flatMap(\.entries).map(\.path))
        guard !paths.isEmpty else { return }
        let bytes = detailGroups.flatMap(\.entries)
            .filter { paths.contains($0.path) }
            .reduce(0) { $0 + $1.sizeBytes }
        cleanPrompt = .uninstall(
            appName: app.name,
            paths: paths,
            summary: "\(paths.count) items · \(ByteText.string(bytes))",
            complete: !appOnly
        )
    }

    func cancelCleanPrompt() { cleanPrompt = nil }

    /// Run a confirmed clean — prompt is passed in so alert dismissal cannot clear it first.
    func executeCleanPrompt(_ prompt: CleanPrompt) async {
        cleanPrompt = nil
        isCleaning = true
        defer { isCleaning = false }

        switch prompt {
        case .scanItems(let targets, _):
            if await trashPaths(targets) > 0 { SystemSound.playMoveToTrash() }
        case .detailPaths(let paths, _):
            if await executeTrashDetail(paths: paths) > 0 { SystemSound.playMoveToTrash() }
        case .uninstall(_, let paths, _, _):
            if await executeTrashDetail(paths: paths, allowApplications: true) > 0 {
                SystemSound.playMoveToTrash()
            }
        case .permanentlyDeleteTrash(let paths, _):
            if await permanentlyDeleteTrashItems(paths) > 0 { SystemSound.playDeletePermanently() }
        case .emptyTrash:
            if await emptyTrash() > 0 { SystemSound.playDeletePermanently() }
        }
    }

    func confirmCleanPrompt() async {
        guard let prompt = cleanPrompt else { return }
        await executeCleanPrompt(prompt)
    }

    func refreshPermission() {
        hasFullDiskAccess = permission.hasFullDiskAccess()
    }

    func refreshDisk() {
        let d = DiskInfo.homeVolume()
        freeBytes = d.free
        totalBytes = d.total
        refreshTrashSummary()
    }

    func selectSection(_ section: AppSection) {
        guard selectedSection != section else { return }
        withAnimation(Theme.easeOut) {
            selectedSection = section
            closeDetail()
        }
        if section == .installedApps && !installedAppsLoaded {
            loadInstalledApps()
        }
        if section == .trash {
            loadTrash()
        }
        if section == .pulse {
            refreshPulse()
        }
        if section == .envDoctor && !envLoaded {
            loadEnvDoctor()
        }
        if section == .duplicates && !duplicatesLoaded {
            loadDuplicates()
        }
        if section == .aiModels && !modelsLoaded {
            loadAIModels()
        }
        if section == .gitRepos && !gitLoaded {
            loadGitRepos()
        }
        if section == .rulesPlugins {
            refreshPluginsList()
            rulesMeta = CloudRules.loadMeta()
        }
        if section == .ask && chatMessages.isEmpty {
            seedChatWelcome()
        }
        if section == .buildTrends {
            buildTrends = BuildTrendStore.load()
        }
    }

    /// Back from detail drill-down, otherwise return to Overview.
    var canNavigateBack: Bool {
        detailTarget != nil || selectedSection != .overview
    }

    var backNavigationTitle: String {
        detailTarget != nil ? "Back" : "Overview"
    }

    func navigateBack() {
        guard canNavigateBack else { return }
        if detailTarget != nil {
            closeDetail()
            return
        }
        withAnimation(Theme.easeOut) {
            selectedSection = .overview
        }
    }

    func bootstrapPlatform() {
        PluginLoader.ensureScaffold()
        rulesMeta = CloudRules.loadMeta()
        continuousMonitor.start { [weak self] _ in
            self?.monitorAlert = self?.continuousMonitor.alert
        }
        // Background rules refresh (non-blocking)
        Task { await refreshCloudRules(silent: true) }
    }

    // MARK: - macOS Trash (browse · restore · permanent delete)

    func refreshTrashSummary() {
        guard hasFullDiskAccess else { return }
        Task.detached(priority: .utility) {
            let items = TrashScanner.listItems()
            let total = TrashScanner.totalBytes(in: items)
            await MainActor.run {
                self.trashTotalBytes = total
                if self.selectedSection == .trash, !self.isLoadingTrash {
                    self.trashItems = items
                }
            }
        }
    }

    func loadTrash() {
        guard hasFullDiskAccess else { return }
        isLoadingTrash = true
        Task.detached(priority: .userInitiated) {
            let items = TrashScanner.listItems()
            let total = TrashScanner.totalBytes(in: items)
            await MainActor.run {
                self.isLoadingTrash = false
                guard self.selectedSection == .trash else { return }
                self.trashItems = items
                self.trashTotalBytes = total
                self.trashSelection = []
                self.trashLoaded = true
            }
        }
    }

    func requestPermanentlyDeleteTrashSelection() {
        let paths = trashItems.filter { trashSelection.contains($0.id) }.map(\.path)
        guard !paths.isEmpty else { return }
        let bytes = trashItems.filter { trashSelection.contains($0.id) }.reduce(0) { $0 + $1.sizeBytes }
        cleanPrompt = .permanentlyDeleteTrash(
            paths: paths,
            summary: "\(paths.count) items · \(ByteText.string(bytes))"
        )
    }

    func requestEmptyTrash() {
        guard !trashItems.isEmpty else { return }
        cleanPrompt = .emptyTrash(
            summary: "\(trashItems.count) items · \(ByteText.string(trashTotalBytes))"
        )
    }

    var trashAllSelected: Bool {
        !trashItems.isEmpty && trashSelection.count == trashItems.count
    }

    var trashPartiallySelected: Bool {
        !trashSelection.isEmpty && !trashAllSelected
    }

    func selectAllTrash() {
        trashSelection = Set(trashItems.map(\.id))
    }

    func deselectAllTrash() {
        trashSelection = []
    }

    func toggleTrashSelection(_ id: String) {
        if trashSelection.contains(id) { trashSelection.remove(id) }
        else { trashSelection.insert(id) }
    }

    func restoreTrashSelection() {
        let items = trashItems.filter { trashSelection.contains($0.id) }
        guard !items.isEmpty else { return }
        isCleaning = true
        let paths = items.map(\.path)
        Task {
            let outcome = await TrashScanner.restore(paths: paths)
            await MainActor.run {
                self.isCleaning = false
                if outcome.restored > 0 { SystemSound.playPutBack() }
                self.loadTrash()
                self.refreshDisk()
                if let message = outcome.message {
                    self.trashRestoreNotice = message
                }
            }
        }
    }

    @discardableResult
    private func permanentlyDeleteTrashItems(_ paths: [String]) async -> Int {
        guard !paths.isEmpty else { return 0 }
        let bytes = await Task.detached {
            TrashScanner.permanentlyDelete(paths: paths)
        }.value
        trashSelection.subtract(paths)
        trashItems.removeAll { paths.contains($0.id) }
        trashTotalBytes = TrashScanner.totalBytes(in: trashItems)
        if bytes > 0 { recordTrashReclaimed(bytes) }
        refreshDisk()
        return bytes > 0 ? paths.count : 0
    }

    @discardableResult
    private func emptyTrash() async -> Int {
        let paths = trashItems.map(\.path)
        return await permanentlyDeleteTrashItems(paths)
    }

    func items(for section: AppSection) -> [ScanItem] {
        guard let cat = section.ruleCategory else { return [] }
        let list = items.filter { $0.category == cat }
        switch sortOrder {
        case .largest: return list.sorted { $0.sizeBytes > $1.sizeBytes }
        case .name: return list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    func filteredItems(for section: AppSection) -> [ScanItem] {
        items(for: section).filter { safetyFilter.matches($0.safety) }
    }

    func totalBytes(for section: AppSection) -> Int64 {
        items(for: section).reduce(0) { $0 + $1.sizeBytes }
    }

    func safeBytes(for section: AppSection) -> Int64 {
        items(for: section).filter { $0.safety == .safe }.reduce(0) { $0 + $1.sizeBytes }
    }

    func safeItems(for section: AppSection) -> [ScanItem] {
        items(for: section)
            .filter { $0.safety == .safe }
            .sorted { $0.sizeBytes > $1.sizeBytes }
    }

    var overviewRows: [(section: AppSection, total: Int64, safe: Int64)] {
        AppSection.scannable.map { s in
            (s, totalBytes(for: s), safeBytes(for: s))
        }.filter { $0.total > 0 || scannedSections.contains($0.section) }
    }

    /// Live count while scan streams results (not only after scan finishes).
    var categoriesWithData: Int {
        Set(items.filter { $0.sizeBytes > 0 }.compactMap { AppSection.section(forCategory: $0.category) }).count
    }

    var filteredInstalledApps: [InstalledApp] {
        let q = appSearchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        var list = installedApps
        if !q.isEmpty {
            list = list.filter {
                $0.name.lowercased().contains(q) ||
                ($0.bundleID?.lowercased().contains(q) ?? false)
            }
        }
        switch sortOrder {
        case .largest: return list.sorted { $0.totalBytes > $1.totalBytes }
        case .name: return list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    func loadInstalledApps() {
        guard !isLoadingApps else { return }
        isLoadingApps = true
        Task.detached(priority: .userInitiated) {
            let apps = AppScanner.listApps()
            await MainActor.run {
                self.installedApps = apps
                self.installedAppsLoaded = true
                self.isLoadingApps = false
            }
        }
    }

    func openScanItemDetail(_ item: ScanItem) {
        detailTarget = .scanItem(item)
        detailGroups = []
        detailSelectedPaths = []
        detailShowsGroupedRoot = false
        detailBreadcrumbs = [DetailBreadcrumb(name: item.name, path: item.path)]
        loadFolderDetail(path: item.path, ruleID: item.id, selectAll: true)
    }

    func openInstalledAppDetail(_ app: InstalledApp) {
        detailTarget = .installedApp(app)
        detailGroups = []
        detailSelectedPaths = []
        detailShowsGroupedRoot = true
        detailBreadcrumbs = [DetailBreadcrumb(name: app.name, path: app.appPath)]
        isLoadingDetail = true
        let path = app.appPath
        let bid = app.bundleID
        let name = app.name
        Task.detached(priority: .userInitiated) {
            let groups = AppScanner.relatedFiles(appPath: path, bundleID: bid, appName: name)
            await MainActor.run {
                guard case .installedApp(let current) = self.detailTarget, current.id == app.id else { return }
                self.detailGroups = groups
                self.detailSelectedPaths = Set(groups.flatMap(\.entries)
                    .filter { $0.kind != .application && !$0.requiresConfirm }
                    .map(\.id))
                self.isLoadingDetail = false
            }
        }
    }

    func drillIntoFolder(_ entry: FileEntry) {
        guard entry.isDrillable else { return }
        detailShowsGroupedRoot = false
        detailBreadcrumbs.append(DetailBreadcrumb(name: entry.name, path: entry.path))
        let ruleID: String? = {
            if detailBreadcrumbs.count == 2, case .scanItem(let item) = detailTarget { return item.id }
            return nil
        }()
        loadFolderDetail(path: entry.path, ruleID: ruleID, selectAll: false)
    }

    func detailGoBack() {
        guard detailBreadcrumbs.count > 1 else {
            closeDetail()
            return
        }
        detailBreadcrumbs.removeLast()
        reloadCurrentDetailView(selectAll: false)
    }

    func detailJumpTo(_ index: Int) {
        guard index >= 0, index < detailBreadcrumbs.count - 1 else { return }
        detailBreadcrumbs = Array(detailBreadcrumbs.prefix(index + 1))
        reloadCurrentDetailView(selectAll: false)
    }

    private func loadFolderDetail(path: String, ruleID: String?, selectAll: Bool) {
        isLoadingDetail = true
        Task.detached(priority: .userInitiated) {
            let groups = AppScanner.folderContents(path: path, ruleID: ruleID)
            await MainActor.run {
                guard self.detailBreadcrumbs.last?.path == path else { return }
                self.detailGroups = groups
                self.detailSelectedPaths = selectAll
                    ? Set(groups.flatMap(\.entries).map(\.id))
                    : []
                self.isLoadingDetail = false
            }
        }
    }

    private func reloadCurrentDetailView(selectAll: Bool) {
        guard let current = detailBreadcrumbs.last else { return }
        if detailBreadcrumbs.count == 1, case .installedApp(let app) = detailTarget {
            detailShowsGroupedRoot = true
            isLoadingDetail = true
            let path = app.appPath
            let bid = app.bundleID
            let name = app.name
            Task.detached(priority: .userInitiated) {
                let groups = AppScanner.relatedFiles(appPath: path, bundleID: bid, appName: name)
                await MainActor.run {
                    guard case .installedApp(let current) = self.detailTarget, current.id == app.id else { return }
                    self.detailGroups = groups
                    if selectAll {
                        self.detailSelectedPaths = Set(groups.flatMap(\.entries).map(\.id))
                    }
                    self.isLoadingDetail = false
                }
            }
            return
        }
        detailShowsGroupedRoot = false
        let ruleID: String? = {
            if detailBreadcrumbs.count == 1, case .scanItem(let item) = detailTarget { return item.id }
            return nil
        }()
        loadFolderDetail(path: current.path, ruleID: ruleID, selectAll: selectAll)
    }

    func closeDetail() {
        detailTarget = nil
        detailGroups = []
        detailSelectedPaths = []
        detailBreadcrumbs = []
        detailShowsGroupedRoot = false
    }

    func trashDetailSelection() async {
        await executeTrashDetail(paths: detailSelectedPaths)
    }

    @discardableResult
    private func executeTrashDetail(paths: Set<String>, allowApplications: Bool = false) async -> Int {
        guard !paths.isEmpty else { return 0 }
        let filtered = PathSafety.filterSafeTrashURLs(Array(paths), allowApplications: allowApplications)
        if !filtered.rejected.isEmpty {
            pathSafetyNotice = "Skipped \(filtered.rejected.count) path(s) that failed safety checks."
        }
        guard !filtered.safe.isEmpty else { return 0 }
        let urls = filtered.safe
        let allowed = Set(urls.map(\.path))
        let reclaimed = detailGroups.flatMap(\.entries)
            .filter { (paths.contains($0.id) || paths.contains($0.path)) && allowed.contains($0.path) }
            .reduce(0) { $0 + $1.sizeBytes }

        let mapping: [URL: URL] = await withCheckedContinuation { cont in
            NSWorkspace.shared.recycle(urls) { result, _ in
                cont.resume(returning: result)
            }
        }
        TrashOriginStore.recordRecycleResult(mapping)
        let trashed = Set(mapping.keys.map(\.path))

        guard !trashed.isEmpty else { return 0 }

        // Refresh detail after trash
        if case .installedApp(let app) = detailTarget {
            if trashed.contains(app.appPath) {
                closeDetail()
                loadInstalledApps()
            } else {
                reloadCurrentDetailView(selectAll: false)
                detailSelectedPaths.subtract(trashed)
                detailSelectedPaths.subtract(paths)
            }
            recordTrashReclaimed(reclaimed)
            rebuildDoctorReport()
            refreshDisk()
            refreshTrashSummary()
            loadTrash()
            return trashed.count
        } else if case .scanItem(let item) = detailTarget {
            if let idx = items.firstIndex(where: { $0.id == item.id }) {
                let old = items[idx]
                let newSize = Shell.size(item.path)
                if newSize > 0 {
                    items[idx] = ScanItem(
                        id: old.id, name: old.name, path: old.path,
                        category: old.category, safety: old.safety,
                        note: old.note, command: old.command,
                        sizeBytes: newSize, known: old.known,
                        lastActivity: PathActivity.lastActivity(at: item.path),
                        largestChildren: newSize >= Scanner.childDrillThreshold
                            ? Scanner.largestChildren(of: item.path, limit: Scanner.maxChildren)
                            : [],
                        fromCache: false
                    )
                } else {
                    items.remove(at: idx)
                    closeDetail()
                    recordTrashReclaimed(reclaimed)
                    rebuildDoctorReport()
                    refreshDisk()
                    refreshTrashSummary()
                    loadTrash()
                    return trashed.count
                }
            }
        }
        reloadCurrentDetailView(selectAll: false)
        detailSelectedPaths.subtract(trashed)
        recordTrashReclaimed(reclaimed)
        rebuildDoctorReport()
        refreshDisk()
        refreshTrashSummary()
        loadTrash()
        return trashed.count
    }

    func scan(section: AppSection? = nil) {
        guard !isScanning, hasFullDiskAccess else { return }
        closeDetail()
        isScanning = true
        scanningSection = section
        refreshDisk()

        if let section, section.ruleCategory != nil {
            items.removeAll { $0.category == section.ruleCategory }
        } else {
            items = []
            selection = []
            scannedSections = []
        }

        let scanner = self.scanner
        let session = Scanner.ScanSession(cache: fingerprintCache, profile: adaptiveProfile)
        let mode: ScanMode = {
            if let cat = section?.ruleCategory {
                if section == .heavyFolders { return .discoveryOnly }
                return .category(cat)
            }
            return .all
        }()

        Task {
            for await item in Self.scanStream(scanner: scanner, mode: mode, session: session) {
                insert(item)
            }

            self.fingerprintCache = session.cache
            self.adaptiveProfile = session.profile
            self.fingerprintCache.save()
            self.adaptiveProfile.save()
            self.lastScanCacheHits = session.snapshotCacheHits()
            self.lastScanSkippedRules = session.profile.autoSkippedCount

            if let section, section.ruleCategory != nil {
                self.scannedSections.insert(section)
                for item in self.items(for: section) where item.safety == .safe {
                    self.selection.insert(item.id)
                }
                self.rebuildDoctorReport()
            } else {
                self.scannedSections = Set(AppSection.scannable)
                self.overviewSelectedSections = Set(
                    AppSection.scannable.filter { self.safeBytes(for: $0) > 0 }
                )
                for item in self.items where item.safety == .safe {
                    self.selection.insert(item.id)
                }
                self.recordHistoryAndBuildDoctor()
                self.buildTrends.record()
                self.buildTrends = BuildTrendStore.load()
            }
            self.isScanning = false
            self.scanningSection = nil
            self.refreshDisk()
            self.refreshPulse()
        }
    }

    func resetAdaptiveSkips() {
        adaptiveProfile.resetSkips()
        adaptiveProfile.save()
        lastScanSkippedRules = 0
    }

    func revealInFinder(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func item(id: String) -> ScanItem? {
        items.first { $0.id == id }
    }

    func requestTrashRecommendation(_ rec: DoctorRecommendation) {
        guard let id = rec.relatedItemID, let item = item(id: id) else { return }
        if item.safety == .safe {
            requestTrash(item)
        } else if item.safety == .command, item.command != nil {
            copyCommand(item)
            pathSafetyNotice = "Command copied — paste it in Terminal."
        } else {
            if let section = AppSection.section(forCategory: item.category) {
                selectSection(section)
            }
            openScanItemDetail(item)
        }
    }

    private func recordHistoryAndBuildDoctor() {
        let entry = DoctorEngine.historyEntry(
            items: items,
            freeBytes: freeBytes,
            totalBytes: totalBytes
        )
        scanHistory.append(entry)
        rebuildDoctorReport()
    }

    private func rebuildDoctorReport() {
        doctorReport = DoctorEngine.build(
            items: items,
            history: scanHistory.entries,
            freeBytes: freeBytes,
            totalBytes: totalBytes,
            skippedRules: adaptiveProfile.autoSkippedCount,
            cacheHits: lastScanCacheHits
        )
    }

    private func insert(_ item: ScanItem) {
        items.removeAll { $0.id == item.id }
        items.append(item)
        if let section = AppSection.section(forCategory: item.category) {
            scannedSections.insert(section)
        }
    }

    private enum ScanMode {
        case all
        case category(String)
        case discoveryOnly
    }

    private nonisolated static func scanStream(
        scanner: Scanner,
        mode: ScanMode,
        session: Scanner.ScanSession
    ) -> AsyncStream<ScanItem> {
        AsyncStream { continuation in
            Task.detached(priority: .userInitiated) {
                var knownPaths = Set<String>()
                let pathLock = NSLock()
                switch mode {
                case .all:
                    _ = scanner.scanKnownParallel(categories: nil, session: session) { item in
                        pathLock.lock()
                        knownPaths.insert(item.path)
                        pathLock.unlock()
                        continuation.yield(item)
                    }
                    ProjectScanner.scan { continuation.yield($0) }
                    scanner.scanUnknown(knownPaths: knownPaths) { continuation.yield($0) }
                case .category(let cat):
                    _ = scanner.scanKnownParallel(categories: Set([cat]), session: session) { item in
                        pathLock.lock()
                        knownPaths.insert(item.path)
                        pathLock.unlock()
                        continuation.yield(item)
                    }
                    if cat == "Developer" {
                        ProjectScanner.scan { continuation.yield($0) }
                    }
                case .discoveryOnly:
                    for rule in scanner.rules {
                        knownPaths.insert(PathUtil.expand(rule.path))
                    }
                    scanner.scanUnknown(knownPaths: knownPaths) { continuation.yield($0) }
                }
                continuation.finish()
            }
        }
    }

    // MARK: - Actions

    func copyCommand(_ item: ScanItem) {
        guard let cmd = item.command else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(cmd, forType: .string)
    }

    func trash(_ item: ScanItem) async { await trashPaths([item]) }

    func cleanSafe(in section: AppSection) async {
        let targets = items(for: section).filter { $0.safety == .safe }
        await trashPaths(targets)
    }

    func cleanSafeSelected() async {
        let targets = items.filter { selection.contains($0.id) && $0.safety == .safe }
        await trashPaths(targets)
    }

    func cleanAllSafe() async {
        let targets = items.filter { $0.safety == .safe }
        await trashPaths(targets)
    }

    func cleanSelected(in section: AppSection) async {
        let targets = items(for: section).filter { selection.contains($0.id) && $0.safety == .safe }
        await trashPaths(targets)
    }

    func selectAll(in section: AppSection, filter: SafetyFilter? = nil) {
        let f = filter ?? safetyFilter
        for item in items(for: section) where f.matches(item.safety) {
            selection.insert(item.id)
        }
    }

    func deselectAll(in section: AppSection) {
        for item in items(for: section) { selection.remove(item.id) }
    }

    func selectedCount(in section: AppSection) -> Int {
        items(for: section).filter { selection.contains($0.id) }.count
    }

    func selectedSafeBytes(in section: AppSection) -> Int64 {
        items(for: section)
            .filter { selection.contains($0.id) && $0.safety == .safe }
            .reduce(0) { $0 + $1.sizeBytes }
    }

    func selectedCheckCount(in section: AppSection) -> Int {
        items(for: section).filter { $0.safety == .check && selection.contains($0.id) }.count
    }

    /// Selected items first, then unselected safe — for overview card chips (max 4).
    func overviewPreviewItems(for section: AppSection, limit: Int = 4) -> [ScanItem] {
        let selected = items(for: section)
            .filter { canToggleInOverview($0) && selection.contains($0.id) }
            .sorted { $0.sizeBytes > $1.sizeBytes }
        if selected.count >= limit { return Array(selected.prefix(limit)) }
        let selectedIDs = Set(selected.map(\.id))
        let filler = safeItems(for: section).filter { !selectedIDs.contains($0.id) }
        return selected + filler.prefix(limit - selected.count)
    }

    func hasOverviewSelection(in section: AppSection) -> Bool {
        items(for: section).contains { canToggleInOverview($0) && selection.contains($0.id) }
    }

    @discardableResult
    private func trashPaths(_ targets: [ScanItem]) async -> Int {
        guard !targets.isEmpty else { return 0 }

        // Map each ScanItem to a PathSafety-standardized URL (recycle keys use these paths).
        var itemURL: [(ScanItem, URL)] = []
        var rejected: [(String, PathSafety.Failure)] = []
        for item in targets {
            switch PathSafety.validateForTrash(item.path) {
            case .success(let url): itemURL.append((item, url))
            case .failure(let err): rejected.append((item.path, err))
            }
        }
        if !rejected.isEmpty {
            let names = rejected.prefix(3).map { ($0.0 as NSString).lastPathComponent }
            pathSafetyNotice = "Skipped \(rejected.count) unsafe path(s): \(names.joined(separator: ", "))"
        }
        guard !itemURL.isEmpty else { return 0 }

        let urls = itemURL.map(\.1)
        let mapping: [URL: URL] = await withCheckedContinuation { cont in
            NSWorkspace.shared.recycle(urls) { result, _ in
                cont.resume(returning: result)
            }
        }
        TrashOriginStore.recordRecycleResult(mapping)

        // Match by standardized path — raw ScanItem.path often differs slightly.
        let trashedStd = Set(mapping.keys.map { $0.standardizedFileURL.path })
        let removed = itemURL.filter { trashedStd.contains($0.1.standardizedFileURL.path) }.map(\.0)
        let removedIDs = Set(removed.map(\.id))
        guard !removedIDs.isEmpty else {
            pathSafetyNotice = "macOS did not move the selection to Trash. Check Full Disk Access, then try again."
            return 0
        }

        let reclaimed = removed.reduce(Int64(0)) { $0 + $1.sizeBytes }
        items.removeAll { removedIDs.contains($0.id) }
        selection.subtract(removedIDs)
        if case .scanItem(let open)? = detailTarget,
           removedIDs.contains(open.id) || removed.contains(where: { $0.path == open.path }) {
            closeDetail()
        }
        fingerprintCache.invalidate(ids: removedIDs)
        fingerprintCache.save()
        recordTrashReclaimed(reclaimed)
        rebuildDoctorReport()
        refreshDisk()
        refreshTrashSummary()
        loadTrash() // keep Trash browser in sync immediately
        return removedIDs.count
    }

    // MARK: - Platform labs

    func refreshPulse() {
        Task.detached(priority: .utility) {
            let pulse = SystemHealth.snapshot()
            await MainActor.run { self.systemPulse = pulse }
        }
    }

    func loadEnvDoctor() {
        guard !isLoadingEnv else { return }
        isLoadingEnv = true
        Task.detached(priority: .userInitiated) {
            let findings = EnvDoctor.diagnose()
            await MainActor.run {
                self.envFindings = findings
                self.envLoaded = true
                self.isLoadingEnv = false
            }
        }
    }

    func loadDuplicates() {
        guard !isLoadingDuplicates else { return }
        isLoadingDuplicates = true
        Task.detached(priority: .userInitiated) {
            let groups = DuplicateFinder.scan()
            await MainActor.run {
                self.duplicateGroups = groups
                self.duplicatesLoaded = true
                self.isLoadingDuplicates = false
            }
        }
    }

    func loadPackageFinder() {
        guard !isLoadingPackages else { return }
        isLoadingPackages = true
        Task.detached(priority: .userInitiated) {
            let findings = PackageFinder.scan()
            await MainActor.run {
                self.packageFindings = findings
                self.packagesLoaded = true
                self.isLoadingPackages = false
            }
        }
    }

    func loadAgentTools() {
        guard !isLoadingAgentTools else { return }
        isLoadingAgentTools = true
        Task.detached(priority: .userInitiated) {
            let findings = AgentToolsScanner.scan()
            await MainActor.run {
                self.agentToolFindings = findings
                self.agentToolsLoaded = true
                self.isLoadingAgentTools = false
            }
        }
    }

    func loadAIModels() {
        guard !isLoadingModels else { return }
        isLoadingModels = true
        Task.detached(priority: .userInitiated) {
            let models = LocalModelManager.inventory()
            await MainActor.run {
                self.aiModels = models
                self.modelsLoaded = true
                self.isLoadingModels = false
            }
        }
    }

    func loadGitRepos() {
        guard !isLoadingGit else { return }
        isLoadingGit = true
        Task.detached(priority: .userInitiated) {
            let repos = GitOptimizer.scan()
            await MainActor.run {
                self.gitReports = repos
                self.gitLoaded = true
                self.isLoadingGit = false
            }
        }
    }

    func analyzeCodebase() {
        let path = codebasePath
        isLoadingCodebase = true
        Task.detached(priority: .userInitiated) {
            let findings = CodebaseAnalyzer.analyze(root: path)
            await MainActor.run {
                self.codebaseFindings = findings
                self.isLoadingCodebase = false
            }
        }
    }

    func recordBuildTrend() {
        buildTrends.record()
        buildTrends = BuildTrendStore.load()
    }

    func refreshCloudRules(silent: Bool = false) async {
        if !silent { rulesRefreshing = true }
        let result = await CloudRules.refresh()
        let plugins = PluginLoader.loadRules(platform: "macos")
        scanner = Scanner(rules: CloudRules.resolveRules(
            bundled: Scanner.loadBundledRules(),
            plugins: plugins
        ))
        rulesMeta = result.meta
        if let err = result.error {
            rulesStatus = "Feed unreachable (\(err)). Using cached/bundled + plugins · \(scanner.rules.count) rules."
        } else {
            rulesStatus = "Synced · feed \(result.meta.ruleCount) · active \(scanner.rules.count) (plugins merged)."
        }
        rulesRefreshing = false
        refreshPluginsList()
    }

    func refreshPluginsList() {
        plugins = PluginLoader.listPlugins()
    }

    func openPluginsFolder() {
        PluginLoader.ensureScaffold()
        NSWorkspace.shared.open(PluginLoader.pluginsDirectory)
    }

    func setOllamaChat(_ on: Bool) {
        useOllamaChat = on
        UserDefaults.standard.set(on, forKey: "stoguard.useOllamaChat")
    }

    func setContinuousMonitoring(_ on: Bool) {
        continuousMonitor.setEnabled(on) { [weak self] _ in
            self?.monitorAlert = self?.continuousMonitor.alert
            self?.refreshPulse()
        }
    }

    func seedChatWelcome() {
        let welcome = WorkstationChat.Message(
            id: UUID(), role: .assistant,
            text: "Hi — I’m grounded in your last scan. Try “Why is my SSD full?”, “Why is my Mac slow?”, “Explain DerivedData”, or “Show duplicate Node versions”.",
            createdAt: Date()
        )
        chatMessages = [welcome]
    }

    func sendChat() {
        let q = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !chatBusy else { return }
        chatInput = ""
        chatMessages.append(.init(id: UUID(), role: .user, text: q, createdAt: Date()))
        chatBusy = true
        let ctx = chatContext()
        Task {
            let answer = await WorkstationChat.answer(q, context: ctx)
            await MainActor.run {
                self.chatMessages.append(.init(id: UUID(), role: .assistant, text: answer, createdAt: Date()))
                self.chatBusy = false
            }
        }
    }

    func askWhySSDFull() {
        chatInput = "Why is my SSD full?"
        sendChat()
    }

    private func chatContext() -> WorkstationChat.Context {
        WorkstationChat.Context(
            items: items,
            report: doctorReport,
            pulse: systemPulse ?? continuousMonitor.lastPulse,
            duplicates: duplicateGroups,
            models: aiModels,
            env: envFindings
        )
    }

    func trashAIModel(_ model: AIModelEntry) {
        let item = ScanItem(
            id: model.id, name: "\(model.provider) · \(model.name)", path: model.path,
            category: "AI Tools", safety: .check,
            note: model.removeHint, command: nil,
            sizeBytes: model.sizeBytes, known: true,
            lastActivity: model.lastActivity
        )
        requestTrash(item)
    }

    func exportFleetReport() {
        let report = FleetExport.build(
            items: items,
            free: freeBytes,
            total: totalBytes,
            env: envFindings,
            duplicates: duplicateGroups,
            rulesVersion: rulesMeta?.version
        )
        do {
            let url = try FleetExport.writeJSON(report)
            fleetExportURL = url
            fleetStatus = "Wrote \(url.lastPathComponent)"
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            fleetStatus = "Export failed: \(error.localizedDescription)"
        }
    }
}
