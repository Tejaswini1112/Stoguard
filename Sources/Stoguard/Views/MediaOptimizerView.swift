import SwiftUI

struct MediaOptimizerView: View {
    @EnvironmentObject var model: AppModel
    @State private var mode: MediaOptimizeMode = .losslessKeepResolution
    @State private var targetValue: String = "50"
    @State private var targetUnit: MediaSizeUnit = .mb
    @State private var kindFilter: MediaKind? = nil

    private var filtered: [MediaAsset] {
        let base = model.mediaAssets
        guard let kindFilter else { return base }
        return base.filter { $0.kind == kindFilter }
    }

    private var selectedAssets: [MediaAsset] {
        filtered.filter { model.mediaSelection.contains($0.id) }
    }

    private var targetBytes: Int64 {
        let v = Double(targetValue.replacingOccurrences(of: ",", with: "")) ?? 50
        return targetUnit.toBytes(max(0.001, v))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                controls
                if model.isLoadingMedia {
                    ProgressView("Scanning Downloads, Documents, Desktop, Pictures, Movies…")
                        .padding(.vertical, 24)
                } else if filtered.isEmpty {
                    empty
                } else {
                    list
                }
                if !model.mediaOptimizeResults.isEmpty {
                    results
                }
            }
            .padding(16)
            .frame(maxWidth: 920, alignment: .leading)
        }
        .background(Theme.bg)
        .onAppear {
            if !model.mediaLoaded { model.scanMediaAssets() }
        }
        .sheet(item: $model.mediaOptimizePrompt) { prompt in
            approvalSheet(prompt)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Media Optimizer").font(.system(size: 22, weight: .bold))
            Text("Detects large images, videos, and documents. Optimizes only after you approve — resolution stays the same unless you pick a target size.")
                .font(.subheadline).foregroundStyle(Theme.secondaryText)
            if model.mediaLoaded {
                Text("\(model.mediaAssets.count) large files · \(ByteText.string(model.mediaAssets.reduce(0) { $0 + $1.sizeBytes }))")
                    .font(.caption.monospacedDigit()).foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button(model.isLoadingMedia ? "Scanning…" : "Scan for large media") {
                    model.scanMediaAssets()
                }
                .buttonStyle(PrimaryPillButtonStyle())
                .disabled(model.isLoadingMedia || model.isOptimizingMedia)

                Picker("Kind", selection: Binding(
                    get: { kindFilter.map { $0.rawValue } ?? "all" },
                    set: { kindFilter = $0 == "all" ? nil : MediaKind(rawValue: $0) }
                )) {
                    Text("All").tag("all")
                    ForEach(MediaKind.allCases, id: \.rawValue) { k in
                        Text(k.label).tag(k.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
            }

            Picker("Mode", selection: $mode) {
                ForEach(MediaOptimizeMode.allCases) { m in
                    Text(m.title).tag(m)
                }
            }
            .pickerStyle(.radioGroup)

            Text(mode.detail)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)

            if mode == .targetSize {
                HStack(spacing: 8) {
                    Text("Target size").font(.caption.weight(.semibold))
                    TextField("50", text: $targetValue)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                    Picker("", selection: $targetUnit) {
                        ForEach(MediaSizeUnit.allCases) { u in
                            Text(u.rawValue).tag(u)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 70)
                    Text("per file (\(ByteText.string(targetBytes)))")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }

            HStack {
                Button("Select all shown") {
                    model.mediaSelection.formUnion(filtered.map(\.id))
                }
                .buttonStyle(SecondaryOutlineButtonStyle())
                Button("Clear selection") { model.mediaSelection = [] }
                    .buttonStyle(GhostButtonStyle())
                Spacer()
                Button(model.isOptimizingMedia ? "Optimizing…" : "Optimize selected…") {
                    model.requestMediaOptimize(mode: mode, targetBytes: mode == .targetSize ? targetBytes : nil)
                }
                .buttonStyle(PrimaryPillButtonStyle())
                .disabled(selectedAssets.isEmpty || model.isOptimizingMedia)
            }
        }
        .padding(12)
        .elevatedCard(radius: 12)
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 28))
                .foregroundStyle(Theme.navy)
            Text("No oversized media found yet")
                .font(.headline)
            Text("Thresholds: images ≥ 8 MB · videos ≥ 80 MB · documents ≥ 15 MB in Downloads / Documents / Desktop / Pictures / Movies.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .elevatedCard(radius: 12)
    }

    private var list: some View {
        VStack(spacing: 8) {
            ForEach(filtered) { asset in
                HStack(alignment: .top, spacing: 10) {
                    Toggle("", isOn: Binding(
                        get: { model.mediaSelection.contains(asset.id) },
                        set: { on in
                            if on { model.mediaSelection.insert(asset.id) }
                            else { model.mediaSelection.remove(asset.id) }
                        }
                    ))
                    .toggleStyle(.checkbox)
                    .labelsHidden()

                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(asset.name).font(.system(size: 13, weight: .semibold))
                            Text(asset.kind.label)
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Theme.navy.opacity(0.12), in: Capsule())
                        }
                        Text(asset.path)
                            .font(.system(size: 10).monospaced())
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(asset.note)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Spacer()
                    Text(asset.sizeText)
                        .font(.caption.monospacedDigit().weight(.semibold))
                    Button("Reveal") { model.revealInFinder(asset.path) }
                        .buttonStyle(.link)
                        .font(.caption)
                }
                .padding(10)
                .elevatedCard(radius: 10)
            }
        }
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last optimization").font(.headline)
            ForEach(model.mediaOptimizeResults) { r in
                VStack(alignment: .leading, spacing: 2) {
                    Text((r.path as NSString).lastPathComponent)
                        .font(.system(size: 12, weight: .semibold))
                    Text(r.message)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                    if r.savedBytes > 0 {
                        Text("\(ByteText.string(r.beforeBytes)) → \(ByteText.string(r.afterBytes))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.navy)
                    }
                }
                .padding(10)
                .elevatedCard(radius: 8)
            }
        }
    }

    private func approvalSheet(_ prompt: MediaOptimizePrompt) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Approve optimization")
                .font(.title2.bold())
            Text(prompt.summary)
                .font(.callout)
                .foregroundStyle(Theme.secondaryText)
            Text(prompt.mode.detail)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(prompt.assets) { a in
                        HStack {
                            Text(a.name).lineLimit(1)
                            Spacer()
                            Text(a.sizeText).font(.caption.monospacedDigit())
                        }
                        .font(.system(size: 12))
                    }
                }
            }
            .frame(maxHeight: 220)

            Text("Originals move to Trash first (recoverable). Optimized files keep the same path when possible.")
                .font(.caption2)
                .foregroundStyle(Theme.tertiaryText)

            HStack {
                Button("Cancel") { model.cancelMediaOptimize() }
                    .buttonStyle(SecondaryOutlineButtonStyle())
                Spacer()
                Button("Approve & optimize") {
                    Task { await model.executeMediaOptimize() }
                }
                .buttonStyle(PrimaryPillButtonStyle())
            }
        }
        .padding(20)
        .frame(width: 480, height: 420)
    }
}
