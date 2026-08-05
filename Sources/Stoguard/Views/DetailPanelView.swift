import SwiftUI
import AppKit

/// PureMac-style right panel: grouped files, checkboxes, nested folder drill-down, Move to Trash.
struct DetailPanelView: View {
    let title: String
    let subtitle: String?
    let icon: NSImage?
    let systemIcon: String?
    let groups: [FileGroup]
    @Binding var selectedPaths: Set<String>
    let isLoading: Bool
    var showBack = true
    var installedApp: InstalledApp?

    @EnvironmentObject var model: AppModel
    @State private var showUninstallOptions = false

    private var allEntries: [FileEntry] { groups.flatMap(\.entries) }
    private var selectedEntries: [FileEntry] {
        allEntries.filter { selectedPaths.contains($0.id) }
    }
    private var selectedBytes: Int64 {
        selectedEntries.reduce(0) { $0 + $1.sizeBytes }
    }

    private var completeUninstallBytes: Int64 {
        allEntries.reduce(0) { $0 + $1.sizeBytes }
    }

    private var displayTitle: String {
        model.detailBreadcrumbs.last?.name ?? title
    }

    private var displayPath: String {
        model.detailBreadcrumbs.last?.path ?? subtitle ?? ""
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if model.detailBreadcrumbs.count > 1 {
                breadcrumbBar
                Divider()
            } else {
                Divider()
            }
            if isLoading {
                Spacer()
                ProgressView("Scanning folder contents…")
                Spacer()
            } else if groups.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 36, weight: .thin))
                        .foregroundStyle(Theme.secondaryText)
                    Text("No files found in this folder")
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(groups) { group in
                            groupSection(group)
                        }
                    }
                    .padding(10)
                }
            }
            Divider()
            footer
        }
        .background(Theme.bg)
    }

    private var header: some View {
        HStack(spacing: 10) {
            if showBack {
                Button {
                    if model.detailBreadcrumbs.count > 1 {
                        model.detailGoBack()
                    } else {
                        model.closeDetail()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(GhostButtonStyle())
            }

            Group {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else if let systemIcon {
                    Image(systemName: systemIcon)
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.primaryText)
                }
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text(displayTitle)
                    .font(.title3.weight(.semibold))
                Text(displayPath)
                    .font(.caption.monospaced())
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(allEntries.count) items · \(ByteText.string(allEntries.reduce(0) { $0 + $1.sizeBytes }))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
            }

            Spacer(minLength: 8)

            if let app = installedApp, !app.isSystemApp {
                Button { showUninstallOptions = true } label: {
                    Label("Uninstall", systemImage: "trash")
                }
                .buttonStyle(UninstallPillButtonStyle())
                .disabled(model.isCleaning || isLoading)
                .confirmationDialog(
                    "Uninstall \(app.name)?",
                    isPresented: $showUninstallOptions,
                    titleVisibility: .visible
                ) {
                    Button("Uninstall Completely (\(ByteText.string(completeUninstallBytes)))", role: .destructive) {
                        model.requestUninstall(appOnly: false)
                    }
                    Button("App Only (\(app.sizeText))") {
                        model.requestUninstall(appOnly: true)
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Complete removes containers, caches, and preferences. App only keeps your data if you plan to reinstall.")
                }
            }
        }
        .padding(16)
        .background(Theme.card)
        .shadow(color: .black.opacity(0.03), radius: 4, y: 1)
    }

    private var breadcrumbBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(model.detailBreadcrumbs.enumerated()), id: \.offset) { idx, crumb in
                    if idx > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.tertiaryText)
                    }
                    Button {
                        if idx < model.detailBreadcrumbs.count - 1 {
                            model.detailJumpTo(idx)
                        }
                    } label: {
                        Text(crumb.name)
                            .font(.system(size: 11, weight: idx == model.detailBreadcrumbs.count - 1 ? .semibold : .medium))
                            .foregroundStyle(idx == model.detailBreadcrumbs.count - 1 ? Theme.primaryText : Theme.secondaryText)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .disabled(idx == model.detailBreadcrumbs.count - 1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .background(Theme.elevated.opacity(0.5))
    }

    @ViewBuilder
    private func groupSection(_ group: FileGroup) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                let allSelected = group.entries.allSatisfy { selectedPaths.contains($0.id) }
                Toggle("", isOn: Binding(
                    get: { allSelected },
                    set: { on in
                        if on { group.entries.forEach { selectedPaths.insert($0.id) } }
                        else { group.entries.forEach { selectedPaths.remove($0.id) } }
                    }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()

                Image(systemName: group.kind.icon)
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 18)
                Text(group.kind.rawValue)
                    .font(.system(size: 13, weight: .semibold))
                Text("\(group.entries.count)")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.elevated.opacity(0.8), in: Capsule())
                Spacer()
                Text(ByteText.string(group.totalBytes))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.card.opacity(0.6))

            ForEach(Array(group.entries.enumerated()), id: \.element.id) { idx, entry in
                fileRow(entry)
                if idx < group.entries.count - 1 {
                    Divider().padding(.leading, 44)
                }
            }
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.hairline.opacity(0.72), lineWidth: 1))
    }

    private func fileRow(_ entry: FileEntry) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { selectedPaths.contains(entry.id) },
                set: { on in
                    if on { selectedPaths.insert(entry.id) }
                    else { selectedPaths.remove(entry.id) }
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            Image(nsImage: NSWorkspace.shared.icon(forFile: entry.path))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(entry.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    if entry.isDrillable {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.tertiaryText)
                    }
                }
                Text(entry.path)
                    .font(.system(size: 10).monospaced())
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 4)

            Text(entry.sizeText)
                .font(.system(size: 12, weight: .medium).monospacedDigit())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(entry.isDrillable ? Color.clear : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            if entry.isDrillable {
                model.drillIntoFolder(entry)
            } else {
                if selectedPaths.contains(entry.id) { selectedPaths.remove(entry.id) }
                else { selectedPaths.insert(entry.id) }
            }
        }
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: entry.path)])
            }
            if entry.isDrillable {
                Button("Open folder") { model.drillIntoFolder(entry) }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Select All") {
                selectedPaths = Set(allEntries.map(\.id))
            }
            .buttonStyle(GhostButtonStyle())
            Button("Deselect All") {
                selectedPaths = []
            }
            .buttonStyle(GhostButtonStyle())
            Spacer()
            if model.isCleaning {
                BusyIndicator(label: "Moving to Trash…")
            }
            Text("\(selectedEntries.count) selected · \(ByteText.string(selectedBytes))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.secondaryText)
            Button {
                model.requestTrashDetailSelection()
            } label: {
                HStack(spacing: 6) {
                    if model.isCleaning {
                        ProgressView().controlSize(.small)
                    }
                    Text("Move \(selectedEntries.count) to Trash")
                }
            }
            .buttonStyle(DestructivePillButtonStyle())
            .disabled(selectedEntries.isEmpty || model.isCleaning)
        }
        .padding(14)
        .background(Theme.card)
        .shadow(color: .black.opacity(0.03), radius: 4, y: -1)
    }
}
