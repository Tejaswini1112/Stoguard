import SwiftUI
import AppKit

struct AISkillsView: View {
    @EnvironmentObject var model: AppModel

    private var flaggedCount: Int {
        model.aiSkillEntries.filter(\.needsAttention).count
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            infoBanner

            if model.isLoadingAISkills && !model.aiSkillsLoaded {
                ScrollView { SkeletonAppGrid() }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.filteredAISkillEntries.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Text(model.aiSkillsLoaded ? "No entries match your search." : "No AI skills or MCP configs found.")
                        .font(.headline)
                    Text("Cursor skills, Codex skills, and MCP server configs are scanned from your home folder.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                Spacer()
            } else {
                HStack {
                    Text("\(model.filteredAISkillEntries.count) entries")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.secondaryText)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 6)

                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 128, maximum: 156), spacing: 10)],
                        spacing: 10
                    ) {
                        ForEach(model.filteredAISkillEntries) { entry in
                            skillTile(entry)
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
            if !model.aiSkillsLoaded { model.loadAISkills() }
        }
    }

    private var header: some View {
        TabHeaderWithCenteredSearch(
            leading: {
                HStack(spacing: 10) {
                    SectionIconBadge(section: .aiSkills, size: 28, filled: true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("AI & Skills")
                            .font(.system(size: 15, weight: .semibold))
                        if model.aiSkillsLoaded {
                            if flaggedCount > 0 {
                                Text("\(flaggedCount) need attention · \(model.aiSkillEntries.count) total")
                                    .font(.caption)
                                    .foregroundStyle(Theme.dangerRed)
                            } else {
                                Text("\(model.aiSkillEntries.count) entries")
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        }
                    }
                }
            },
            placeholder: "Search skills & MCP",
            searchText: $model.aiSkillsSearchQuery,
            trailing: {
                Button { model.loadAISkills() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(SecondaryOutlineButtonStyle())
                .disabled(model.isLoadingAISkills)
            }
        )
    }

    private var infoBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.checkAmber)
                .font(.system(size: 12))
            Text("Review-only — Stoguard flags missing SKILL.md files, stale configs, and broken MCP paths.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.checkAmber.opacity(0.08))
    }

    private func skillTile(_ entry: AISkillEntry) -> some View {
        Button {
            NSWorkspace.shared.selectFile(entry.path, inFileViewerRootedAtPath: "")
        } label: {
            VStack(spacing: 6) {
                DiscoveryIconView(glyph: DiscoveryItemIcon.aiSkill(entry), size: 36)
                Text(entry.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.primaryText)
                Text(entry.kind.rawValue.uppercased())
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.3)
                    .foregroundStyle(entry.needsAttention ? Theme.dangerRed : Theme.navy)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        (entry.needsAttention ? Theme.dangerRed : Theme.navy).opacity(0.08),
                        in: Capsule()
                    )
                Text(entry.sizeText)
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
                if let issue = entry.issue {
                    Text(issue)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Theme.dangerRed)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                if let label = entry.modifiedLabel {
                    Text(label)
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.tertiaryText)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background(
                entry.needsAttention ? Theme.dangerRed.opacity(0.04) : Theme.card,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        entry.needsAttention ? Theme.dangerRed.opacity(0.35) : Theme.hairline.opacity(0.85),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.selectFile(entry.path, inFileViewerRootedAtPath: "")
            }
        }
    }
}
