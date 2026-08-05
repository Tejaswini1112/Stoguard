import SwiftUI
import AppKit

struct TrashView: View {
    @EnvironmentObject var model: AppModel

    private var selectedItems: [TrashItem] {
        model.trashItems.filter { model.trashSelection.contains($0.id) }
    }

    private var selectedBytes: Int64 {
        selectedItems.reduce(0) { $0 + $1.sizeBytes }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            infoBanner
            listArea
            footer
        }
        .background(Theme.bg)
        .onAppear { model.loadTrash() }
        .alert("Put Back", isPresented: Binding(
            get: { model.trashRestoreNotice != nil },
            set: { if !$0 { model.trashRestoreNotice = nil } }
        )) {
            Button("OK") { model.trashRestoreNotice = nil }
        } message: {
            Text(model.trashRestoreNotice ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            SectionIconBadge(section: .trash, size: 28, filled: true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Trash — \(ByteText.storage(model.trashTotalBytes))")
                    .font(.system(size: 15, weight: .semibold))
                Text("Your Mac Trash — browse items, put them back, or permanently delete.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(2)
            }
            Spacer()
            if model.isCleaning {
                BusyIndicator(label: "Working…")
            }
            Button { model.loadTrash() } label: {
                HStack(spacing: 6) {
                    if model.isLoadingTrash {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                    }
                }
            }
            .buttonStyle(SecondaryOutlineButtonStyle())
            .disabled(model.isLoadingTrash || model.isCleaning)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.card)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var infoBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Theme.navy)
                .font(.system(size: 12))
            Text("Items here are in macOS Trash — you can restore them with Put Back until you empty Trash. Emptying Trash is final and cannot be undone.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.navy.opacity(0.06))
    }

    private var listArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if !model.trashItems.isEmpty {
                    selectionBar
                }

                if model.isLoadingTrash && model.trashItems.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView("Reading Trash…").controlSize(.small)
                        Spacer()
                    }
                    .padding(.vertical, 40)
                } else if model.trashItems.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "trash")
                            .font(.system(size: 32, weight: .thin))
                            .foregroundStyle(Theme.secondaryText)
                        Text("Trash is empty")
                            .font(.headline)
                        Text("When you delete files from Stoguard or Finder, they appear here.")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    VStack(spacing: 0) {
                        columnHeaders
                        ForEach(Array(model.trashItems.enumerated()), id: \.element.id) { idx, item in
                            trashRow(item)
                            if idx < model.trashItems.count - 1 {
                                Divider().padding(.leading, 36)
                            }
                        }
                    }
                    .elevatedCard(radius: 10)
                    .overlay(alignment: .top) {
                        if model.isLoadingTrash {
                            ProgressView().controlSize(.small)
                                .padding(8)
                                .background(.ultraThinMaterial, in: Capsule())
                                .padding(8)
                        }
                    }
                }
            }
            .padding(12)
        }
    }

    private var selectionBar: some View {
        HStack(spacing: 12) {
            Toggle(isOn: Binding(
                get: { model.trashAllSelected },
                set: { on in
                    if on { model.selectAllTrash() }
                    else { model.deselectAllTrash() }
                }
            )) {
                Text(selectionLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
            }
            .toggleStyle(.checkbox)

            if model.trashPartiallySelected {
                Button("Deselect All") { model.deselectAllTrash() }
                    .buttonStyle(GhostButtonStyle())
            }

            Spacer(minLength: 8)

            if !selectedItems.isEmpty {
                Button { model.restoreTrashSelection() } label: {
                    Label("Put Back", systemImage: "arrow.uturn.backward")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(SecondaryOutlineButtonStyle())
                .disabled(model.isCleaning)

                Button { model.requestPermanentlyDeleteTrashSelection() } label: {
                    Label("Delete Permanently", systemImage: "trash.slash")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(DestructivePillButtonStyle())
                .disabled(model.isCleaning)
            }

            if model.isCleaning {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.hairline.opacity(0.72), lineWidth: 1))
    }

    private var selectionLabel: String {
        let total = model.trashItems.count
        let selected = selectedItems.count
        if selected == 0 { return "Select All (\(total))" }
        if model.trashAllSelected { return "All \(total) selected" }
        return "\(selected) of \(total) selected"
    }

    private var columnHeaders: some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: 16)
            Text("Name").frame(maxWidth: .infinity, alignment: .leading)
            Text("Kind").frame(width: 88, alignment: .leading)
            Text("Trashed").frame(width: 72, alignment: .leading)
            Text("Size").frame(width: 64, alignment: .trailing)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(Theme.tertiaryText)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Theme.elevated.opacity(0.6))
    }

    private func trashRow(_ item: TrashItem) -> some View {
        let selected = model.trashSelection.contains(item.id)

        return HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { selected },
                set: { on in
                    if on { model.trashSelection.insert(item.id) }
                    else { model.trashSelection.remove(item.id) }
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            Image(nsImage: NSWorkspace.shared.icon(forFile: item.path))
                .resizable().aspectRatio(contentMode: .fit).frame(width: 18, height: 18)

            Text(item.name)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(item.kind)
                .font(.system(size: 10))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 88, alignment: .leading)
                .lineLimit(1)

            Text(item.dateAdded.map(formatDate) ?? "—")
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(Theme.tertiaryText)
                .frame(width: 72, alignment: .leading)

            Text(item.sizeText)
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? Theme.navy.opacity(0.06) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onTapGesture { model.toggleTrashSelection(item.id) }
        .contextMenu {
            Button {
                model.trashSelection = [item.id]
                model.restoreTrashSelection()
            } label: {
                Label("Put Back", systemImage: "arrow.uturn.backward")
            }
            Button {
                model.trashSelection = [item.id]
                model.requestPermanentlyDeleteTrashSelection()
            } label: {
                Label("Delete Permanently", systemImage: "trash.slash")
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if !selectedItems.isEmpty {
                Text("\(selectedItems.count) selected · \(ByteText.string(selectedBytes))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
            } else {
                Text("\(model.trashItems.count) items · \(ByteText.storage(model.trashTotalBytes))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
            }

            Spacer()

            Button { model.requestEmptyTrash() } label: {
                HStack(spacing: 6) {
                    if model.isCleaning {
                        ProgressView().controlSize(.small)
                    }
                    Label("Empty Trash", systemImage: "trash.fill")
                        .font(.system(size: 13, weight: .semibold))
                }
            }
            .buttonStyle(DestructivePillButtonStyle())
            .disabled(model.trashItems.isEmpty || model.isCleaning)
        }
        .padding(14)
        .background(Theme.card)
        .overlay(alignment: .top) { Divider() }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        return f.string(from: date)
    }
}
