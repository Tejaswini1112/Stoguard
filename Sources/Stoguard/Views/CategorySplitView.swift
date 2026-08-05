import SwiftUI

struct CategorySplitView: View {
    @EnvironmentObject var model: AppModel
    let section: AppSection

    private var rows: [ScanItem] { model.filteredItems(for: section) }
    private var hasDetail: Bool {
        if case .scanItem = model.detailTarget { return true }
        return false
    }
    private var selectedID: String? {
        if case .scanItem(let item) = model.detailTarget { item.id }
        else { nil }
    }

    var body: some View {
        Group {
            if hasDetail {
                HSplitView {
                    listPane.frame(minWidth: 260, idealWidth: 320)
                    detailPane
                        .frame(minWidth: 280)
                        .detailTransition(active: hasDetail)
                }
            } else {
                listPane
            }
        }
    }

    private var listPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                filterBar
                if rows.isEmpty {
                    Text("No items match this filter.")
                        .font(.callout)
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.vertical, 20)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { idx, item in
                            SelectableItemRow(
                                item: item,
                                isSelected: selectedID == item.id
                            ) { model.openScanItemDetail(item) }
                            if idx < rows.count - 1 { Divider().padding(.leading, 60) }
                        }
                    }
                    .elevatedCard(radius: 10)
                }
            }
            .padding(12)
        }
        .background(Theme.bg)
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SafetyFilterPills(filter: $model.safetyFilter)
                Spacer(minLength: 0)
                Picker("Sort", selection: $model.sortOrder) {
                    ForEach(SortOrder.allCases) { s in Text(s.rawValue).tag(s) }
                }
                .pickerStyle(.menu)
                .fixedSize()
            }
            SelectionActionBar(
                totalCount: rows.count,
                selectedCount: model.selectedCount(in: section),
                selectedBytes: model.selectedSafeBytes(in: section),
                isBusy: model.isCleaning,
                onSelectAll: { model.selectAll(in: section) },
                onDeselectAll: { model.deselectAll(in: section) },
                onClean: { model.requestCleanSelected(in: section) }
            )
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if case .scanItem(let item) = model.detailTarget {
            DetailPanelView(
                title: item.name,
                subtitle: item.path,
                icon: ScanItemIcon.image(for: item),
                systemIcon: nil,
                groups: model.detailGroups,
                selectedPaths: $model.detailSelectedPaths,
                isLoading: model.isLoadingDetail
            )
        }
    }
}

struct SelectableItemRow: View {
    let item: ScanItem
    let isSelected: Bool
    let onSelect: () -> Void
    @EnvironmentObject var model: AppModel
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Toggle("", isOn: Binding(
                get: { model.selection.contains(item.id) },
                set: { on in
                    if on { model.selection.insert(item.id) }
                    else { model.selection.remove(item.id) }
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            ScanItemIconView(item: item, size: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name).font(.system(size: 13, weight: .medium))
                    SafetyChip(safety: item.safety, libraryRisk: item.isLibraryProfileRisk)
                }
                if item.isLibraryProfileRisk {
                    Text("May affect profiles / settings")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.dangerRed)
                        .lineLimit(1)
                }
                Text(item.note).font(.system(size: 11)).foregroundStyle(Theme.secondaryText).lineLimit(1)
                Text(item.path).font(.system(size: 9.5).monospaced()).foregroundStyle(Theme.tertiaryText).lineLimit(1)
            }

            Spacer(minLength: 4)
            Text(item.sizeText).font(.system(size: 12, weight: .semibold).monospacedDigit())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            isSelected ? Theme.navy.opacity(0.08) : (hovering ? Theme.elevated : Color.clear),
            in: RoundedRectangle(cornerRadius: 6)
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { hovering = $0 }
    }
}
