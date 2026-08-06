import Foundation
import CryptoKit

// MARK: - Duplicate finder (thorough)

/// Confirmed duplicate vs related-but-distinct (differences shown with icons).
enum DuplicateVerdict: String, Codable, Sendable {
    case duplicate
    case related

    var badge: String {
        switch self {
        case .duplicate: return "DUPLICATE"
        case .related: return "NOT A DUPLICATE"
        }
    }

    var icon: String {
        switch self {
        case .duplicate: return "doc.on.doc.fill"
        case .related: return "arrow.left.arrow.right.circle"
        }
    }
}

struct DifferenceFact: Identifiable, Hashable, Sendable {
    let id: String
    let icon: String
    let label: String
    let detail: String
}

struct DuplicateGroup: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let kind: String
    let explanation: String
    let verdict: DuplicateVerdict
    let differences: [DifferenceFact]
    let entries: [DuplicateEntry]

    var totalBytes: Int64 { entries.reduce(0) { $0 + $1.sizeBytes } }

    /// Only meaningful for confirmed duplicates (bytes beyond the largest keep).
    var wasteBytes: Int64 {
        guard verdict == .duplicate, entries.count > 1 else { return 0 }
        let sorted = entries.sorted { $0.sizeBytes > $1.sizeBytes }
        return sorted.dropFirst().reduce(0) { $0 + $1.sizeBytes }
    }
}

struct DuplicateEntry: Identifiable, Hashable, Sendable {
    var id: String { path }
    let name: String
    let path: String
    let sizeBytes: Int64
    let detail: String
    let fingerprint: String?
}

enum DuplicateFinder {
    static func scan() -> [DuplicateGroup] {
        var groups: [DuplicateGroup] = []
        groups += analyzeVersionRoot(
            id: "nvm",
            titleBase: "Node.js (nvm)",
            kind: "Node",
            root: PathUtil.expand("~/.nvm/versions/node"),
            binaryRelative: "bin/node",
            uninstallHint: "`nvm uninstall <version>`"
        )
        groups += analyzeVersionRoot(
            id: "pyenv",
            titleBase: "Python (pyenv)",
            kind: "Python",
            root: PathUtil.expand("~/.pyenv/versions"),
            binaryRelative: "bin/python",
            uninstallHint: "`pyenv uninstall <version>`"
        )
        groups += analyzeVersionRoot(
            id: "rustup",
            titleBase: "Rust toolchains",
            kind: "Rust",
            root: PathUtil.expand("~/.rustup/toolchains"),
            binaryRelative: "bin/rustc",
            uninstallHint: "`rustup toolchain uninstall <name>`"
        )
        groups += simulatorRuntimes()
        groups += ollamaTags()
        groups += contentIdenticalFiles()
        return groups.sorted { a, b in
            if a.verdict != b.verdict { return a.verdict == .duplicate }
            return a.wasteBytes > b.wasteBytes || a.totalBytes > b.totalBytes
        }
    }

    // MARK: Version roots — fingerprint binaries before calling something a duplicate

    private static func analyzeVersionRoot(
        id: String,
        titleBase: String,
        kind: String,
        root: String,
        binaryRelative: String,
        uninstallHint: String
    ) -> [DuplicateGroup] {
        let kids = listChildren(root)
        guard kids.count >= 2 else { return [] }

        var entries: [DuplicateEntry] = []
        for kid in kids {
            let bin = (kid.path as NSString).appendingPathComponent(binaryRelative)
            let fp = fileFingerprint(bin) ?? folderFingerprint(kid.path)
            entries.append(DuplicateEntry(
                name: kid.name,
                path: kid.path,
                sizeBytes: kid.bytes,
                detail: FileManager.default.fileExists(atPath: bin) ? "Binary: \(binaryRelative)" : "Install folder",
                fingerprint: fp
            ))
        }

        var groups: [DuplicateGroup] = []

        // True duplicates: same fingerprint across differently named (or same) installs.
        var byFP: [String: [DuplicateEntry]] = [:]
        for e in entries {
            guard let fp = e.fingerprint, !fp.isEmpty else { continue }
            byFP[fp, default: []].append(e)
        }
        for (fp, list) in byFP where list.count > 1 {
            let names = list.map(\.name).joined(separator: " · ")
            groups.append(DuplicateGroup(
                id: "dup-\(id)-\(fp.prefix(10))",
                title: "\(titleBase) — confirmed duplicate installs",
                kind: kind,
                explanation: "Same binary fingerprint across \(list.count) installs (\(names)). Safe to keep one; remove extras with \(uninstallHint).",
                verdict: .duplicate,
                differences: [
                    DifferenceFact(id: "fp", icon: "checkmark.seal.fill", label: "Fingerprint", detail: "Identical \(binaryRelative) content signature"),
                    DifferenceFact(id: "waste", icon: "internaldrive.fill", label: "Reclaimable", detail: ByteText.string(waste(list))),
                ],
                entries: list
            ))
        }

        // Same version name appearing twice (rare — different roots).
        var byName: [String: [DuplicateEntry]] = [:]
        for e in entries { byName[e.name.lowercased(), default: []].append(e) }
        for (name, list) in byName where list.count > 1 {
            // Skip if already covered by fingerprint group
            if list.compactMap(\.fingerprint).allSatisfy({ fp in byFP[fp]?.count ?? 0 > 1 }) { continue }
            groups.append(DuplicateGroup(
                id: "dup-\(id)-name-\(name)",
                title: "\(titleBase) — same version installed twice",
                kind: kind,
                explanation: "Version “\(name)” exists at multiple paths.",
                verdict: .duplicate,
                differences: pathDifferences(list),
                entries: list
            ))
        }

        // Related but NOT duplicates: different versions with distinct fingerprints.
        let uniqueFP = Set(entries.compactMap(\.fingerprint))
        let covered = Set(groups.flatMap { $0.entries.map(\.path) })
        let related = entries.filter { !covered.contains($0.path) }
        if related.count >= 2, uniqueFP.count >= 2 || related.contains(where: { $0.fingerprint == nil }) {
            groups.append(DuplicateGroup(
                id: "rel-\(id)",
                title: "\(titleBase) — related installs (not duplicates)",
                kind: kind,
                explanation: "These are different versions/toolchains. They are not duplicates — keep what your projects need. \(uninstallHint) for ones you don’t use.",
                verdict: .related,
                differences: relatedDifferences(related),
                entries: related
            ))
        }

        return groups
    }

    private static func simulatorRuntimes() -> [DuplicateGroup] {
        let roots = [
            PathUtil.expand("~/Library/Developer/CoreSimulator/Profiles/Runtimes"),
            PathUtil.expand("/Library/Developer/CoreSimulator/Profiles/Runtimes"),
        ]
        var entries: [DuplicateEntry] = []
        for dir in roots {
            for kid in listChildren(dir) {
                let fp = folderFingerprint(kid.path)
                entries.append(DuplicateEntry(
                    name: kid.name, path: kid.path, sizeBytes: kid.bytes,
                    detail: "Simulator runtime", fingerprint: fp
                ))
            }
        }
        guard entries.count >= 2 else { return [] }

        var groups: [DuplicateGroup] = []
        var byFP: [String: [DuplicateEntry]] = [:]
        for e in entries {
            if let fp = e.fingerprint { byFP[fp, default: []].append(e) }
        }
        for (fp, list) in byFP where list.count > 1 {
            groups.append(DuplicateGroup(
                id: "dup-sim-\(fp.prefix(8))",
                title: "Simulator runtime — confirmed duplicate",
                kind: "Xcode",
                explanation: "Identical runtime content at multiple paths.",
                verdict: .duplicate,
                differences: [
                    DifferenceFact(id: "same", icon: "checkmark.seal.fill", label: "Content", detail: "Matching runtime fingerprint"),
                ] + pathDifferences(list),
                entries: list
            ))
        }

        var byName: [String: [DuplicateEntry]] = [:]
        for e in entries { byName[normalizeRuntimeName(e.name), default: []].append(e) }
        for (name, list) in byName where list.count > 1 {
            let paths = Set(list.map(\.path))
            if groups.contains(where: { Set($0.entries.map(\.path)) == paths }) { continue }
            // Same display name, check fingerprint
            let fps = Set(list.compactMap(\.fingerprint))
            if fps.count == 1 {
                groups.append(DuplicateGroup(
                    id: "dup-sim-name-\(name)",
                    title: "Simulator “\(name)” — duplicate copies",
                    kind: "Xcode",
                    explanation: "Same runtime name with matching content.",
                    verdict: .duplicate,
                    differences: pathDifferences(list),
                    entries: list
                ))
            }
        }

        let covered = Set(groups.flatMap { $0.entries.map(\.path) })
        let related = entries.filter { !covered.contains($0.path) }
        if related.count >= 2 {
            groups.append(DuplicateGroup(
                id: "rel-sim",
                title: "Simulator runtimes — related (not duplicates)",
                kind: "Xcode",
                explanation: "Different iOS/platform versions. Not duplicates — remove unused ones in Xcode → Settings → Platforms.",
                verdict: .related,
                differences: relatedDifferences(related),
                entries: related
            ))
        }
        return groups
    }

    private static func ollamaTags() -> [DuplicateGroup] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["ollama", "list"]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do { try proc.run() } catch { return [] }
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return [] }
        let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)

        struct Row { let name: String; let modelID: String; let sizeBytes: Int64; let sizeText: String }
        var rows: [Row] = []
        for line in text.split(separator: "\n").dropFirst() {
            let parts = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard parts.count >= 3 else { continue }
            let name = parts[0]
            let modelID = parts.count >= 2 ? parts[1] : ""
            rows.append(Row(name: name, modelID: modelID, sizeBytes: parseOllamaSize(parts), sizeText: parts.count >= 3 ? parts[2] : "?"))
        }
        guard rows.count >= 2 else { return [] }

        var groups: [DuplicateGroup] = []
        let root = PathUtil.expand("~/.ollama/models")

        // True duplicate: same model ID / digest
        var byID: [String: [Row]] = [:]
        for r in rows where !r.modelID.isEmpty { byID[r.modelID, default: []].append(r) }
        for (mid, list) in byID where list.count > 1 {
            let entries = list.map {
                DuplicateEntry(name: $0.name, path: root, sizeBytes: $0.sizeBytes,
                               detail: "Ollama ID \(mid.prefix(12))…", fingerprint: mid)
            }
            groups.append(DuplicateGroup(
                id: "dup-ollama-id-\(mid.prefix(10))",
                title: "Ollama — confirmed duplicate tags",
                kind: "AI Models",
                explanation: "Multiple tags point at the same model blob. Remove extras with `ollama rm <name>`.",
                verdict: .duplicate,
                differences: [
                    DifferenceFact(id: "id", icon: "checkmark.seal.fill", label: "Model ID", detail: String(mid.prefix(16))),
                ],
                entries: entries
            ))
        }

        // Related: same family, different tags / different IDs
        var byFamily: [String: [Row]] = [:]
        for r in rows {
            let family = r.name.split(separator: ":").first.map(String.init) ?? r.name
            byFamily[family, default: []].append(r)
        }
        let dupPaths = Set(groups.flatMap { $0.entries.map(\.name) })
        for (family, list) in byFamily {
            let distinct = list.filter { !dupPaths.contains($0.name) }
            let ids = Set(distinct.map(\.modelID)).filter { !$0.isEmpty }
            guard distinct.count > 1, ids.count > 1 || distinct.map(\.name).count > 1 else { continue }
            // If all same ID already handled; if different IDs → related
            if ids.count <= 1 && distinct.count > 1 {
                // Same ID already grouped; skip
                continue
            }
            let entries = distinct.map {
                DuplicateEntry(name: $0.name, path: root, sizeBytes: $0.sizeBytes,
                               detail: "Tag · \($0.sizeText)", fingerprint: $0.modelID)
            }
            var diffs: [DifferenceFact] = [
                DifferenceFact(id: "tags", icon: "tag.fill", label: "Tags", detail: distinct.map(\.name).joined(separator: ", ")),
            ]
            if ids.count > 1 {
                diffs.append(DifferenceFact(id: "ids", icon: "number", label: "Model IDs", detail: "Different blobs — not the same file"))
            }
            diffs.append(contentsOf: sizeDifferences(entries))
            groups.append(DuplicateGroup(
                id: "rel-ollama-\(family)",
                title: "Ollama \(family) — related tags (not duplicates)",
                kind: "AI Models",
                explanation: "Same family, different tags/sizes. These are not duplicates unless they share a model ID.",
                verdict: .related,
                differences: diffs,
                entries: entries
            ))
        }
        return groups
    }

    /// Byte-identical large files (true duplicates) under common user folders.
    private static func contentIdenticalFiles() -> [DuplicateGroup] {
        let roots = [
            PathUtil.expand("~/Downloads"),
            PathUtil.expand("~/Desktop"),
            PathUtil.expand("~/Documents"),
        ]
        let fm = FileManager.default
        var buckets: [String: [DuplicateEntry]] = [:]
        for root in roots {
            guard fm.fileExists(atPath: root),
                  let enumerator = fm.enumerator(
                    at: URL(fileURLWithPath: root),
                    includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                  )
            else { continue }
            var n = 0
            while let url = enumerator.nextObject() as? URL {
                n += 1
                if n > 8_000 { break }
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                guard size >= 5_000_000 else { continue }
                guard let fp = fileFingerprint(url.path) else { continue }
                let key = "\(size)|\(fp)"
                buckets[key, default: []].append(DuplicateEntry(
                    name: url.lastPathComponent,
                    path: url.path,
                    sizeBytes: size,
                    detail: "Content match",
                    fingerprint: fp
                ))
            }
        }
        return buckets.compactMap { key, list -> DuplicateGroup? in
            guard list.count > 1 else { return nil }
            let names = Set(list.map(\.name))
            var diffs = pathDifferences(list)
            if names.count > 1 {
                diffs.insert(DifferenceFact(
                    id: "names", icon: "textformat", label: "Names differ",
                    detail: names.sorted().joined(separator: " · ")
                ), at: 0)
            }
            diffs.insert(DifferenceFact(
                id: "bytes", icon: "checkmark.seal.fill", label: "Content",
                detail: "Identical fingerprint + size — true duplicate"
            ), at: 0)
            return DuplicateGroup(
                id: "dup-file-\(key.hashValue)",
                title: "Identical files — confirmed duplicates",
                kind: "Files",
                explanation: "\(list.count) copies of the same content. Keep one; Trash the rest.",
                verdict: .duplicate,
                differences: diffs,
                entries: list
            )
        }
    }

    // MARK: Difference helpers

    private static func relatedDifferences(_ entries: [DuplicateEntry]) -> [DifferenceFact] {
        var facts: [DifferenceFact] = []
        let names = entries.map(\.name)
        facts.append(DifferenceFact(
            id: "versions", icon: "tag.fill", label: "Versions / names",
            detail: names.joined(separator: " · ")
        ))
        facts.append(contentsOf: sizeDifferences(entries))
        let fps = entries.compactMap(\.fingerprint)
        if Set(fps).count > 1 {
            facts.append(DifferenceFact(
                id: "fp", icon: "xmark.seal.fill", label: "Binaries differ",
                detail: "Different content fingerprints — not the same install"
            ))
        }
        facts.append(contentsOf: pathDifferences(entries))
        return facts
    }

    private static func sizeDifferences(_ entries: [DuplicateEntry]) -> [DifferenceFact] {
        guard let maxE = entries.max(by: { $0.sizeBytes < $1.sizeBytes }),
              let minE = entries.min(by: { $0.sizeBytes < $1.sizeBytes }),
              maxE.sizeBytes != minE.sizeBytes
        else {
            return [DifferenceFact(id: "size-same", icon: "scalemass", label: "Sizes", detail: "Similar disk use")]
        }
        let delta = maxE.sizeBytes - minE.sizeBytes
        return [DifferenceFact(
            id: "size", icon: "scalemass.fill", label: "Size gap",
            detail: "\(ByteText.string(minE.sizeBytes)) → \(ByteText.string(maxE.sizeBytes)) (Δ \(ByteText.string(delta)))"
        )]
    }

    private static func pathDifferences(_ entries: [DuplicateEntry]) -> [DifferenceFact] {
        entries.prefix(6).enumerated().map { i, e in
            DifferenceFact(
                id: "path-\(i)",
                icon: "folder.fill",
                label: e.name,
                detail: e.path
            )
        }
    }

    private static func waste(_ entries: [DuplicateEntry]) -> Int64 {
        let sorted = entries.sorted { $0.sizeBytes > $1.sizeBytes }
        return sorted.dropFirst().reduce(0) { $0 + $1.sizeBytes }
    }

    private static func normalizeRuntimeName(_ name: String) -> String {
        name.replacingOccurrences(of: ".simruntime", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    // MARK: Fingerprints

    /// Sampled content hash — size + head + mid + tail (thorough enough without full-file SHA).
    private static func fileFingerprint(_ path: String) -> String? {
        guard let fh = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? fh.close() }
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 0 else { return nil }

        func chunk(at offset: UInt64, len: Int) -> Data {
            do {
                try fh.seek(toOffset: offset)
                return fh.readData(ofLength: len)
            } catch { return Data() }
        }

        let sample = 64 * 1024
        var data = Data()
        data.append(contentsOf: withUnsafeBytes(of: size.bigEndian) { Data($0) })
        data.append(chunk(at: 0, len: sample))
        if size > Int64(sample * 3) {
            data.append(chunk(at: UInt64(size / 2), len: sample))
            data.append(chunk(at: UInt64(max(0, size - Int64(sample))), len: sample))
        }
        return SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
    }

    private static func folderFingerprint(_ path: String) -> String? {
        // Prefer a primary executable if present; else hash directory listing + sizes.
        let candidates = ["bin/node", "bin/python", "bin/python3", "bin/rustc", "Contents/Info.plist"]
        for rel in candidates {
            let p = (path as NSString).appendingPathComponent(rel)
            if let fp = fileFingerprint(p) { return fp }
        }
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: path) else { return nil }
        var material = Data(names.sorted().joined(separator: "|").utf8)
        let size = Shell.size(path)
        material.append(contentsOf: withUnsafeBytes(of: size.bigEndian) { Data($0) })
        return SHA256.hash(data: material).compactMap { String(format: "%02x", $0) }.joined()
    }

    private static func parseOllamaSize(_ parts: [String]) -> Int64 {
        for p in parts {
            let u = p.uppercased()
            if u.hasSuffix("GB"), let v = Double(u.replacingOccurrences(of: "GB", with: "")) {
                return Int64(v * 1_000_000_000)
            }
            if u.hasSuffix("MB"), let v = Double(u.replacingOccurrences(of: "MB", with: "")) {
                return Int64(v * 1_000_000)
            }
        }
        return 0
    }

    private static func listChildren(_ root: String) -> [(name: String, path: String, bytes: Int64)] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root),
              let names = try? fm.contentsOfDirectory(atPath: root)
        else { return [] }
        return names.compactMap { name -> (String, String, Int64)? in
            if name.hasPrefix(".") { return nil }
            let path = (root as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return nil }
            let bytes = Shell.size(path)
            guard bytes > 0 else { return nil }
            return (name, path, bytes)
        }.sorted { $0.2 > $1.2 }
    }
}

// MARK: - Local AI model manager

struct AIModelEntry: Identifiable, Hashable, Sendable {
    let id: String
    let provider: String
    let name: String
    let path: String
    let sizeBytes: Int64
    let lastActivity: Date?
    let removeHint: String
    var quantization: String? = nil
    var formatHint: String? = nil
    var suggestedAction: String? = nil
    var duplicateGroupKey: String? = nil
    /// Estimated RAM if loaded (rough: size × 1.1 for Q4, ×1.2 for fp16 heuristics).
    var estimatedRAMBytes: Int64? = nil

    var daysIdle: Int? {
        guard let lastActivity else { return nil }
        return max(0, Int(Date().timeIntervalSince(lastActivity) / 86_400))
    }
}

enum LocalModelManager {
    static func inventory() -> [AIModelEntry] {
        var out: [AIModelEntry] = []
        out += scanTree(
            provider: "Ollama",
            root: PathUtil.expand("~/.ollama/models"),
            removeHint: "ollama rm <model>"
        )
        out += scanTree(
            provider: "Hugging Face",
            root: PathUtil.expand("~/.cache/huggingface/hub"),
            removeHint: "Delete the model folder; libraries re-download on next use."
        )
        out += scanTree(
            provider: "LM Studio",
            root: PathUtil.expand("~/.cache/lm-studio"),
            removeHint: "Remove in LM Studio or delete the folder."
        )
        out += scanTree(
            provider: "Diffusers",
            root: PathUtil.expand("~/.cache/huggingface/diffusers"),
            removeHint: "Delete unused pipeline folders."
        )
        out += scanTree(
            provider: "Stable Diffusion",
            root: firstExisting([
                "~/stable-diffusion-webui/models",
                "~/stable-diffusion/models",
                "~/.cache/stable-diffusion",
                "~/Library/Application Support/StabilityMatrix/Models",
            ]),
            removeHint: "Remove unused checkpoints/VAE/LoRA folders you no longer use."
        )
        out += scanTree(
            provider: "ComfyUI",
            root: firstExisting([
                "~/ComfyUI/models",
                "~/Documents/ComfyUI/models",
                "~/.comfyui/models",
            ]),
            removeHint: "Remove unused checkpoints from ComfyUI models."
        )
        out += scanTree(
            provider: "Whisper",
            root: PathUtil.expand("~/.cache/whisper"),
            removeHint: "Delete unused Whisper weight files."
        )
        out += scanTree(
            provider: "llama.cpp",
            root: firstExisting(["~/llama.cpp/models", "~/.cache/llama.cpp"]),
            removeHint: "Delete unused GGUF files."
        )
        out += scanTree(
            provider: "Open WebUI",
            root: firstExisting([
                "~/.open-webui",
                "~/Library/Application Support/open-webui",
            ]),
            removeHint: "Remove unused cached assets; models may live under Ollama."
        )
        out = enrich(out)
        return out.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    private static func enrich(_ models: [AIModelEntry]) -> [AIModelEntry] {
        let byBase = Dictionary(grouping: models) { baseName($0.name) }
        return models.map { m in
            var copy = m
            let q = detectQuantization(m.name)
            copy.quantization = q
            copy.formatHint = detectFormat(m.name, path: m.path)
            copy.duplicateGroupKey = baseName(m.name)
            let siblings = byBase[baseName(m.name)] ?? [m]
            if siblings.count > 1 {
                copy.suggestedAction = "Duplicate base name across \(siblings.count) entries — keep one quant, archive extras."
            } else if (m.daysIdle ?? 0) >= 45 {
                copy.suggestedAction = "Idle \(m.daysIdle ?? 45)+ days — Archive (recoverable) or Trash."
            } else if m.sizeBytes > 20_000_000_000 {
                copy.suggestedAction = "Very large — prefer a smaller quant if quality allows."
            } else {
                copy.suggestedAction = "Keep if actively used; Archive when switching models."
            }
            let factor: Double = {
                switch q?.lowercased() {
                case .some(let s) where s.contains("q2") || s.contains("q3"): return 0.9
                case .some(let s) where s.contains("q4"): return 1.05
                case .some(let s) where s.contains("q5") || s.contains("q6"): return 1.15
                case .some(let s) where s.contains("q8") || s.contains("fp16") || s.contains("f16"): return 1.25
                default: return 1.15
                }
            }()
            copy.estimatedRAMBytes = Int64(Double(m.sizeBytes) * factor)
            return copy
        }
    }

    private static func baseName(_ name: String) -> String {
        var n = name.lowercased()
        for token in ["-q2", "-q3", "-q4", "-q5", "-q6", "-q8", "_q2", "_q4", ".q4", ".gguf", "-gguf", "-fp16", "-f16", "-int4", "-int8"] {
            if let r = n.range(of: token) { n = String(n[..<r.lowerBound]) }
        }
        return n.trimmingCharacters(in: CharacterSet(charactersIn: "-_."))
    }

    private static func detectQuantization(_ name: String) -> String? {
        let n = name.lowercased()
        let tokens = ["q2_k", "q3_k", "q4_0", "q4_k_m", "q4_k", "q5_k", "q6_k", "q8_0", "iq4", "fp16", "f16", "int4", "int8", "bf16"]
        for t in tokens where n.contains(t) { return t.uppercased() }
        if n.contains("q4") { return "Q4" }
        if n.contains("q5") { return "Q5" }
        if n.contains("q8") { return "Q8" }
        return nil
    }

    private static func detectFormat(_ name: String, path: String) -> String? {
        let n = (name + path).lowercased()
        if n.contains(".gguf") || n.contains("gguf") { return "GGUF" }
        if n.contains("safetensors") { return "safetensors" }
        if n.contains(".ggml") { return "GGML" }
        if n.contains("diffusers") { return "diffusers" }
        if n.contains("blob") || n.contains("ollama") { return "Ollama blob" }
        return nil
    }

    private static func firstExisting(_ paths: [String]) -> String {
        for p in paths {
            let abs = PathUtil.expand(p)
            if FileManager.default.fileExists(atPath: abs) { return abs }
        }
        return PathUtil.expand(paths[0])
    }

    private static func scanTree(provider: String, root: String, removeHint: String) -> [AIModelEntry] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root) else { return [] }
        let children = (try? fm.contentsOfDirectory(atPath: root)) ?? []
        var entries: [AIModelEntry] = []
        for name in children where !name.hasPrefix(".") {
            let path = (root as NSString).appendingPathComponent(name)
            let bytes = Shell.size(path)
            guard bytes > 20_000_000 else { continue }
            entries.append(AIModelEntry(
                id: "\(provider):\(path)",
                provider: provider,
                name: name,
                path: path,
                sizeBytes: bytes,
                lastActivity: PathActivity.lastActivity(at: path),
                removeHint: removeHint
            ))
        }
        if entries.isEmpty {
            let bytes = Shell.size(root)
            if bytes > 50_000_000 {
                entries.append(AIModelEntry(
                    id: "\(provider):\(root)",
                    provider: provider,
                    name: (root as NSString).lastPathComponent,
                    path: root,
                    sizeBytes: bytes,
                    lastActivity: PathActivity.lastActivity(at: root),
                    removeHint: removeHint
                ))
            }
        }
        return entries
    }
}
