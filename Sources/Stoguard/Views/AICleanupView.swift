import SwiftUI

/// Single place for AI-related cleanup: model stores, skills/MCP, and AI app caches.
struct AICleanupView: View {
    @EnvironmentObject var model: AppModel

    private var aiScanItems: [ScanItem] {
        model.items.filter { $0.category == "AI Tools" }.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    private var safeAIItems: [ScanItem] {
        aiScanItems.filter { $0.safety == .safe }
    }

    private var safeAIBytes: Int64 {
        safeAIItems.reduce(0) { $0 + $1.sizeBytes }
    }

    private var modelsBytes: Int64 {
        model.aiModels.reduce(0) { $0 + $1.sizeBytes }
    }

    private var agentBytes: Int64 {
        model.agentToolFindings.reduce(0) { $0 + $1.sizeBytes }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                summaryCards
                if safeAIBytes > 0 {
                    Button {
                        model.requestCleanSafe(in: .aiTools)
                    } label: {
                        Text("Clean safe AI caches now (\(ByteText.string(safeAIBytes)))")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryPillButtonStyle())
                }

                sectionTitle("Local AI models", subtitle: "Ollama, Hugging Face, LM Studio, and related stores")
                if model.isLoadingModels {
                    ProgressView().padding(.vertical, 8)
                } else if model.aiModels.isEmpty {
                    empty("No local model stores found.")
                } else {
                    ForEach(model.aiModels) { m in
                        aiCard(
                            title: "\(m.provider) · \(m.name)",
                            path: m.path,
                            size: m.sizeBytes,
                            detail: m.removeHint.isEmpty
                                ? "Local model weights or cache. Removing frees disk; you’ll re-download to use again."
                                : m.removeHint,
                            onTrash: { model.trashAIModel(m) }
                        )
                    }
                }

                sectionTitle("Skills & MCP", subtitle: "Agent skills, MCP servers, idle editor extensions")
                if model.isLoadingAgentTools {
                    ProgressView().padding(.vertical, 8)
                } else if model.agentToolFindings.isEmpty {
                    empty("No MCP configs, skills, or large AI extensions found.")
                } else {
                    ForEach(model.agentToolFindings) { f in
                        aiCard(
                            title: f.name,
                            path: f.path,
                            size: f.sizeBytes,
                            detail: f.detail,
                            stale: f.isStale
                        )
                    }
                }

                sectionTitle("AI app caches", subtitle: "From Smart Scan — Claude, ChatGPT, IDE AI data, etc.")
                if aiScanItems.isEmpty {
                    empty("Run Smart Scan to measure AI app caches.")
                } else {
                    ForEach(aiScanItems) { item in
                        ScanItemCard(item: item)
                    }
                }
            }
            .padding(20)
        }
        .background(Theme.bg)
        .onAppear {
            if !model.modelsLoaded { model.loadAIModels() }
            if !model.agentToolsLoaded { model.loadAgentTools() }
            if !model.scannedSections.contains(.aiTools) {
                model.scan(section: .aiTools)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("AI Cleanup")
                .font(.system(size: 22, weight: .bold))
            Text("All advanced AI clutter in one place — models, skills, MCP servers, and AI app caches. Clean safe items immediately; review the rest.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private var summaryCards: some View {
        HStack(spacing: 10) {
            metric("Safe to clean", ByteText.string(safeAIBytes))
            metric("Models", ByteText.string(modelsBytes))
            metric("Skills / MCP", ByteText.string(agentBytes))
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.tertiaryText)
            Text(value)
                .font(.system(size: 16, weight: .semibold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .elevatedCard(radius: 10)
    }

    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(subtitle).font(.caption).foregroundStyle(Theme.secondaryText)
        }
        .padding(.top, 8)
    }

    private func empty(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Theme.secondaryText)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .elevatedCard(radius: 10)
    }

    private func aiCard(
        title: String, path: String, size: Int64, detail: String,
        stale: Bool = false, onTrash: (() -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                if stale {
                    Text("STALE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.dangerRed)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Theme.dangerRed.opacity(0.12), in: Capsule())
                }
                Spacer()
                Text(ByteText.string(size)).font(.caption.monospacedDigit())
            }
            Text(path).font(.system(size: 10).monospaced()).foregroundStyle(Theme.secondaryText).lineLimit(1)
            Text(detail).font(.caption).foregroundStyle(Theme.secondaryText)
            HStack {
                Button("Reveal") { model.revealInFinder(path) }
                    .buttonStyle(.link)
                    .font(.caption)
                if let onTrash {
                    Button("Move to Trash…") { onTrash() }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
        }
        .padding(12)
        .elevatedCard(radius: 10)
    }
}

private struct ScanItemCard: View {
    @EnvironmentObject var model: AppModel
    let item: ScanItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.name).font(.system(size: 13, weight: .semibold))
                SafetyChip(safety: item.safety, libraryRisk: item.isLibraryProfileRisk)
                Spacer()
                Text(item.sizeText).font(.caption.monospacedDigit())
            }
            Text(item.path).font(.system(size: 10).monospaced()).foregroundStyle(Theme.secondaryText).lineLimit(1)
            Text(item.note).font(.caption).foregroundStyle(Theme.secondaryText)
            HStack {
                Button("Reveal") { model.revealInFinder(item.path) }.buttonStyle(.link).font(.caption)
                if item.safety == .safe || item.safety == .check {
                    Button("Move to Trash…") { model.requestTrash(item) }.buttonStyle(.link).font(.caption)
                }
            }
        }
        .padding(12)
        .elevatedCard(radius: 10)
    }
}
