import SwiftUI
import AppKit

struct InstalledPackagesView: View {
    @EnvironmentObject var model: AppModel
    @State private var copiedCommandID: String?

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            infoBanner

            if model.isLoadingPackages && !model.installedPackagesLoaded {
                ScrollView { SkeletonGrid(columns: 3, rows: 4) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.filteredInstalledPackages.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Text(model.installedPackagesLoaded ? "No packages match your search." : "No packages found.")
                        .font(.headline)
                    Text("Installs from Homebrew, npm global, pip, and PATH binaries appear here.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: 10) {
                        ForEach(model.filteredInstalledPackages) { pkg in
                            packageCard(pkg)
                        }
                    }
                    .padding(12)
                    .padding(.bottom, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 96) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
        .onAppear {
            if !model.installedPackagesLoaded { model.loadInstalledPackages() }
        }
    }

    private var header: some View {
        TabHeaderWithCenteredSearch(
            leading: {
                HStack(spacing: 10) {
                    SectionIconBadge(section: .installedPackages, size: 28, filled: true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Installed Packages")
                            .font(.system(size: 15, weight: .semibold))
                        if model.installedPackagesLoaded {
                            Text("\(model.installedPackages.count) packages found")
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                }
            },
            placeholder: "Search packages",
            searchText: $model.packageSearchQuery,
            trailing: {
                Button { model.loadInstalledPackages() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(SecondaryOutlineButtonStyle())
                .disabled(model.isLoadingPackages)
            }
        )
    }

    private var infoBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Theme.navy)
                .font(.system(size: 12))
            Text("Forgotten CLI tools and package installs — copy the uninstall command and paste into Terminal.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.navy.opacity(0.06))
    }

    private func packageCard(_ pkg: InstalledPackage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                DiscoveryIconView(glyph: DiscoveryItemIcon.package(pkg), size: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text(pkg.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(pkg.source.uppercased())
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.3)
                        .foregroundStyle(Theme.navy)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.navy.opacity(0.08), in: Capsule())
                }
                Spacer(minLength: 4)
                Text(pkg.sizeText)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
            }

            if let label = pkg.modifiedLabel {
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.tertiaryText)
            }

            if let cmd = pkg.uninstallCommand {
                Text(cmd)
                    .font(.system(size: 10.5).monospaced())
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }

            HStack(spacing: 8) {
                if let cmd = pkg.uninstallCommand {
                    Button {
                        copyCommand(cmd, id: pkg.id)
                    } label: {
                        Label(
                            copiedCommandID == pkg.id ? "Copied" : "Copy",
                            systemImage: copiedCommandID == pkg.id ? "checkmark" : "doc.on.doc"
                        )
                        .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(SecondaryOutlineButtonStyle())
                }
                Spacer(minLength: 0)
                Button {
                    NSWorkspace.shared.selectFile(pkg.path, inFileViewerRootedAtPath: "")
                } label: {
                    Label("Reveal", systemImage: DiscoveryItemIcon.revealSymbol)
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(RevealButtonStyle())
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.hairline.opacity(0.85), lineWidth: 1))
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.selectFile(pkg.path, inFileViewerRootedAtPath: "")
            }
            if let cmd = pkg.uninstallCommand {
                Button("Copy command") { copyCommand(cmd, id: pkg.id) }
            }
        }
    }

    private func copyCommand(_ cmd: String, id: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(cmd, forType: .string)
        copiedCommandID = id
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run {
                if copiedCommandID == id { copiedCommandID = nil }
            }
        }
    }
}
