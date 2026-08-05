import SwiftUI

// MARK: - Sidebar storage card (Purge pattern, monochrome)

struct SidebarStorageCard: View {
    @EnvironmentObject var model: AppModel

    private var usedFraction: Double {
        guard model.totalBytes > 0 else { return 0 }
        return Double(model.totalBytes - model.freeBytes) / Double(model.totalBytes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("STORAGE")
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(Theme.tertiaryText)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.hairline.opacity(0.35))
                    Capsule()
                        .fill(Theme.navy)
                        .frame(width: max(4, geo.size.width * usedFraction))
                }
            }
            .frame(height: 5)

            HStack {
                Text(ByteText.storage(model.totalBytes - model.freeBytes) + " used")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                Text(ByteText.storage(model.freeBytes) + " free")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
            }

            Text("Whole disk · same accounting as System Settings")
                .font(.system(size: 8.5))
                .foregroundStyle(Theme.tertiaryText)

            if model.reclaimableSafe > 0 {
                Divider().padding(.vertical, 2)

                Text("SAFE TO CLEAN")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.tertiaryText)

                Text(ByteText.string(model.reclaimableSafe))
                    .font(.system(size: 26, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.primaryText)
                    .displayTitle()

                Button {
                    model.requestCleanAllSafe()
                } label: {
                    Text("Clean \(ByteText.string(model.reclaimableSafe))")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryPillButtonStyle())
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(model.hasFullDiskAccess ? Theme.safeGreen : Theme.secondaryText)
                    .frame(width: 5, height: 5)
                Text(model.hasFullDiskAccess ? "Full Disk Access granted" : "Access needed")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.tertiaryText)
            }
            .padding(.top, 2)
        }
        .padding(10)
        .elevatedCard(radius: 10)
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }
}

// MARK: - Smart Scan hero

struct SmartCareHero: View {
    @EnvironmentObject var model: AppModel
    let hasScanResults: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(hasScanResults ? "SCAN COMPLETE" : "SMART SCAN")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.heroSubtext)

                Text(hasScanResults ? "Ready to reclaim" : "Find what's eating your disk")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.heroText.opacity(0.92))

                Text(ByteText.string(hasScanResults ? model.reclaimableSafe : 0))
                    .font(.system(size: 32, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.heroText)
                    .displayTitle()
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.35, dampingFraction: 1), value: model.reclaimableSafe)

                if hasScanResults {
                    let n = model.categoriesWithData
                    Text("across \(n) categor\(n == 1 ? "y" : "ies")\(model.isScanning ? " · scanning" : "") · trash-safe")
                        .font(.caption)
                        .foregroundStyle(Theme.heroSubtext)
                }

                HStack(spacing: 10) {
                    if hasScanResults && model.overviewSelectedSafeBytes > 0 {
                        Button {
                            model.requestCleanOverviewSelected()
                        } label: {
                            Label(
                                "Clean Selected (\(ByteText.string(model.overviewSelectedSafeBytes)))",
                                systemImage: "trash"
                            )
                            .font(.system(size: 13, weight: .semibold))
                        }
                        .buttonStyle(PrimaryPillButtonStyle(inverted: true))
                    }

                    Button {
                        model.scan(section: nil)
                    } label: {
                        Text(model.isScanning && model.scanningSection == nil ? "Scanning…" : "Scan again")
                    }
                    .buttonStyle(SecondaryOutlineButtonStyle(lightOnDark: true))
                    .disabled(model.isScanning)
                }
                .padding(.top, 6)
            }

            Spacer(minLength: 0)

            DiskStackGraphic()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [Theme.heroTop, Theme.heroBottom], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
    }
}

private struct DiskStackGraphic: View {
    var body: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(0.05 + Double(i) * 0.035))
                    .frame(width: 68 - CGFloat(i * 5), height: 12)
                    .offset(y: CGFloat(i) * -9)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                            .frame(width: 68 - CGFloat(i * 5), height: 12)
                            .offset(y: CGFloat(i) * -9)
                    )
            }
        }
        .frame(width: 72, height: 56)
    }
}

// MARK: - Overview selection bar

struct OverviewSelectionBar: View {
    @EnvironmentObject var model: AppModel

    private var visibleCount: Int { model.overviewRows.count }
    private var selectedCount: Int { model.overviewSelectedCount }

    var body: some View {
        HStack(spacing: 12) {
            Toggle(isOn: Binding(
                get: { model.overviewAllSelected },
                set: { on in
                    if on { model.selectAllOverviewSections() }
                    else { model.deselectAllOverviewSections() }
                }
            )) {
                Text(selectionLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
            }
            .toggleStyle(.checkbox)

            if selectedCount > 0 && !model.overviewAllSelected {
                Button("Deselect All") { model.deselectAllOverviewSections() }
                    .buttonStyle(GhostButtonStyle())
            }

            Spacer(minLength: 8)

            if model.overviewSelectedSafeBytes > 0 {
                Button { model.requestCleanOverviewSelected() } label: {
                    Label(
                        "Clean Selected (\(ByteText.string(model.overviewSelectedSafeBytes)))",
                        systemImage: "trash"
                    )
                    .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(PrimaryPillButtonStyle())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.hairline.opacity(0.72), lineWidth: 1))
    }

    private var selectionLabel: String {
        if selectedCount == 0 { return "Select All" }
        if model.overviewAllSelected { return "All \(visibleCount) selected" }
        return "\(selectedCount) of \(visibleCount) selected"
    }
}

// MARK: - Category review card

private let categoryPreviewLimit = 4

struct CategoryReviewCard: View {
    @EnvironmentObject var model: AppModel

    let section: AppSection
    let total: Int64
    let safe: Int64
    let itemCount: Int
    let safeItems: [ScanItem]
    let allItems: [ScanItem]
    let onReview: () -> Void

    @State private var showAllItems = false

    private var previewItems: [ScanItem] {
        model.overviewPreviewItems(for: section, limit: categoryPreviewLimit)
    }

    private var selectedSafeBytes: Int64 { model.selectedSafeBytes(in: section) }
    private var selectedCheckCount: Int { model.selectedCheckCount(in: section) }
    private var cardHighlighted: Bool { model.hasOverviewSelection(in: section) }

    private var selectionCaption: String? {
        var parts: [String] = []
        if selectedSafeBytes > 0 {
            parts.append("\(ByteText.string(selectedSafeBytes)) safe for clean")
        }
        if selectedCheckCount > 0 {
            parts.append("\(selectedCheckCount) check first marked")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Toggle("", isOn: Binding(
                    get: { model.overviewSectionAllSafeSelected(section) },
                    set: { on in
                        if on { model.selectAllSafe(in: section) }
                        else { model.deselectAllSafe(in: section) }
                    }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
                Spacer()
                SectionIconBadge(section: section, size: 28, filled: true)
            }

            Text(ByteText.string(total))
                .font(.system(size: 22, weight: .bold))
                .monospacedDigit()
                .displayTitle()
                .foregroundStyle(Theme.primaryText)
                .padding(.top, 8)

            Text(section.rawValue)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
                .padding(.top, 2)

            Text("\(itemCount) items found")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)

            if let selectionCaption {
                Text(selectionCaption)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.safeGreen)
                    .padding(.top, 2)
            } else if safe > 0 {
                Text("\(ByteText.string(safe)) safe to clean")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.top, 2)
            }

            if !previewItems.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(previewItems) { item in
                        CategoryOverviewItemChip(
                            item: item,
                            included: model.isItemSelected(item),
                            onToggle: { model.toggleItemSelection(item) }
                        )
                    }
                }
                .padding(.top, 8)
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                if allItems.count > categoryPreviewLimit
                    || model.items(for: section).filter({ model.canToggleInOverview($0) && model.isItemSelected($0) }).count > categoryPreviewLimit {
                    Button("Show more") { showAllItems = true }
                        .buttonStyle(GhostButtonStyle())
                        .controlSize(.small)
                }
                Spacer()
                Button("Review", action: onReview)
                    .buttonStyle(SecondaryOutlineButtonStyle())
                    .controlSize(.small)
            }
        }
        .padding(12)
        .frame(minHeight: 168)
        .softTintCard(selected: cardHighlighted)
        .sheet(isPresented: $showAllItems) {
            CategoryItemsSheet(
                section: section,
                items: allItems,
                onReview: {
                    showAllItems = false
                    onReview()
                }
            )
            .environmentObject(model)
        }
    }
}

/// Compact boxed row on overview cards — tap to include or skip.
struct CategoryOverviewItemChip: View {
    let item: ScanItem
    let included: Bool
    let onToggle: () -> Void

    private var accent: Color {
        guard included else { return Theme.secondaryText }
        return item.safety == .safe ? Theme.safeGreen : Theme.checkAmber
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                Image(systemName: included ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accent)

                Text(item.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)

                Text(item.sizeText)
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(included ? accent : Theme.secondaryText)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(included ? accent.opacity(0.10) : Theme.primaryText.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        included ? accent.opacity(0.42) : Theme.hairline.opacity(0.9),
                        lineWidth: included ? 1.25 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .help(included ? "Click to skip \(item.name)" : "Click to include \(item.name)")
    }
}

/// Full category item list from overview “Show more”.
struct CategoryItemsSheet: View {
    @EnvironmentObject var model: AppModel

    let section: AppSection
    let items: [ScanItem]
    let onReview: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var safeSelectedCount: Int {
        items.filter { $0.safety == .safe && model.isItemSelected($0) }.count
    }

    private var checkMarkedCount: Int {
        items.filter { $0.safety == .check && model.isItemSelected($0) }.count
    }

    private var toggleableSelectedCount: Int {
        items.filter { model.canToggleInOverview($0) && model.isItemSelected($0) }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                SectionIconBadge(section: section, size: 36, filled: true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(section.rawValue)
                        .font(.system(size: 18, weight: .bold))
                        .displayTitle()
                    Text(subtitleText)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.secondaryText.opacity(0.65))
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tap to select or skip. Safe items bulk-clean from Overview; Check first items need confirmation in Review.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    if toggleableSelectedCount > 0 {
                        HStack {
                            Spacer()
                            Button("Deselect all") {
                                model.deselectAllOverview(in: section)
                            }
                            .buttonStyle(GhostButtonStyle())
                            .controlSize(.small)
                        }
                    }

                    ForEach(items) { item in
                        CategorySheetItemRow(
                            item: item,
                            included: model.isItemSelected(item),
                            onToggle: model.canToggleInOverview(item) ? { model.toggleItemSelection(item) } : nil
                        )
                    }
                }
                .padding(20)
            }

            Divider()

            HStack {
                Button("Close") { dismiss() }
                    .buttonStyle(SecondaryOutlineButtonStyle())
                Spacer()
                Button("Open full Review") { onReview() }
                    .buttonStyle(PrimaryPillButtonStyle())
            }
            .padding(16)
        }
        .frame(minWidth: 440, minHeight: 360, idealHeight: 480)
        .background(Theme.bg)
    }

    private var subtitleText: String {
        var parts = ["\(items.count) items", "\(safeSelectedCount) safe for clean"]
        if checkMarkedCount > 0 {
            parts.append("\(checkMarkedCount) check first marked")
        }
        return parts.joined(separator: " · ")
    }
}

struct CategorySheetItemRow: View {
    let item: ScanItem
    let included: Bool
    var onToggle: (() -> Void)?

    private var accent: Color {
        guard included else { return Theme.secondaryText }
        return item.safety == .safe ? Theme.safeGreen : Theme.checkAmber
    }

    var body: some View {
        Group {
            if let onToggle {
                Button(action: onToggle) { rowContent }
                    .buttonStyle(.plain)
                    .help(included ? "Click to skip" : "Click to include")
            } else {
                rowContent
            }
        }
    }

    private var rowContent: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: included ? "checkmark.circle.fill" : (onToggle != nil ? "circle" : "minus.circle"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(included ? accent : Theme.secondaryText.opacity(0.55))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(item.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                    SafetyChip(safety: item.safety, libraryRisk: item.isLibraryProfileRisk)
                }
                if item.isLibraryProfileRisk {
                    Text("May change app behavior or remove profiles / settings.")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.dangerRed)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(item.note)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.path)
                    .font(.system(size: 10).monospaced())
                    .foregroundStyle(Theme.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            Text(item.sizeText)
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(included ? accent : Theme.primaryText)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(included ? accent.opacity(0.09) : Theme.elevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    included ? accent.opacity(0.45) : Theme.hairline.opacity(0.85),
                    lineWidth: included ? 1.5 : 1
                )
        )
    }
}

// MARK: - Selection bar (PureMac + Purge)

struct SelectionActionBar: View {
    let totalCount: Int
    let selectedCount: Int
    let selectedBytes: Int64
    var isBusy = false
    let onSelectAll: () -> Void
    let onDeselectAll: () -> Void
    let onClean: () -> Void

    private var allSelected: Bool { totalCount > 0 && selectedCount == totalCount }

    var body: some View {
        HStack(spacing: 12) {
            Toggle(isOn: Binding(
                get: { allSelected },
                set: { on in if on { onSelectAll() } else { onDeselectAll() } }
            )) {
                Text("\(selectedCount) of \(totalCount) selected")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
            }
            .toggleStyle(.checkbox)

            Spacer()

            if isBusy {
                BusyIndicator(label: "Cleaning…")
            }

            if selectedCount > 0 {
                Text(ByteText.string(selectedBytes))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.primaryText)
            }

            if selectedCount > 0 && selectedBytes > 0 {
                Button(action: onClean) {
                    Label(
                        "Clean Selected (\(ByteText.string(selectedBytes)))",
                        systemImage: "trash"
                    )
                    .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(DestructivePillButtonStyle())
                .disabled(isBusy)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.hairline.opacity(0.72), lineWidth: 1))
    }
}

// MARK: - Busy indicator (clean / delete in progress)

struct BusyIndicator: View {
    var label: String = "Working…"

    var body: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
        }
    }
}

// MARK: - Filter pills

struct SafetyFilterPills: View {
    @Binding var filter: SafetyFilter

    var body: some View {
        HStack(spacing: 6) {
            ForEach(SafetyFilter.allCases) { f in
                let selected = filter == f
                Button { withAnimation(.easeOut(duration: 0.15)) { filter = f } } label: {
                    Text(f.rawValue)
                        .font(.system(size: 11, weight: selected ? .semibold : .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selected ? Theme.navy : Theme.elevated, in: Capsule())
                        .foregroundStyle(selected ? .white : Theme.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
