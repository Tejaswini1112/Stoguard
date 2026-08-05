import Foundation

// MARK: - Duplicate finder

struct DuplicateGroup: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let kind: String
    let explanation: String
    let entries: [DuplicateEntry]
    var totalBytes: Int64 { entries.reduce(0) { $0 + $1.sizeBytes } }
    var wasteBytes: Int64 {
        guard entries.count > 1 else { return 0 }
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
}

enum DuplicateFinder {
    static func scan() -> [DuplicateGroup] {
        var groups: [DuplicateGroup] = []
        groups += nvmVersions()
        groups += pyenvVersions()
        groups += rustToolchains()
        groups += xcodeSimRuntimes()
        groups += ollamaDuplicateTags()
        return groups.filter { $0.entries.count > 1 }.sorted { $0.wasteBytes > $1.wasteBytes }
    }

    private static func nvmVersions() -> [DuplicateGroup] {
        let root = PathUtil.expand("~/.nvm/versions/node")
        return versionFolderGroup(
            id: "dup-nvm",
            title: "Multiple Node.js versions (nvm)",
            kind: "Node",
            explanation: "nvm installs a full Node runtime per version. Keep the ones your projects need; remove the rest with `nvm uninstall <version>`.",
            root: root
        )
    }

    private static func pyenvVersions() -> [DuplicateGroup] {
        let root = PathUtil.expand("~/.pyenv/versions")
        return versionFolderGroup(
            id: "dup-pyenv",
            title: "Multiple Python versions (pyenv)",
            kind: "Python",
            explanation: "Each pyenv version is a full interpreter. Remove unused ones with `pyenv uninstall <version>`.",
            root: root
        )
    }

    private static func rustToolchains() -> [DuplicateGroup] {
        let root = PathUtil.expand("~/.rustup/toolchains")
        return versionFolderGroup(
            id: "dup-rustup",
            title: "Multiple Rust toolchains",
            kind: "Rust",
            explanation: "rustup keeps separate toolchains (stable/nightly/targets). Remove with `rustup toolchain uninstall <name>`.",
            root: root
        )
    }

    private static func xcodeSimRuntimes() -> [DuplicateGroup] {
        let root = PathUtil.expand("~/Library/Developer/CoreSimulator/Profiles/Runtimes")
        // Also common path for dyld shared cache runtimes
        let alt = PathUtil.expand("/Library/Developer/CoreSimulator/Profiles/Runtimes")
        var entries: [DuplicateEntry] = []
        for dir in [root, alt] {
            entries += listChildren(dir).map {
                DuplicateEntry(name: $0.name, path: $0.path, sizeBytes: $0.bytes, detail: "Simulator runtime")
            }
        }
        guard entries.count > 1 else { return [] }
        return [DuplicateGroup(
            id: "dup-sim-runtimes",
            title: "Multiple iOS Simulator runtimes",
            kind: "Xcode",
            explanation: "Each runtime is multi‑GB. Remove unused platforms in Xcode → Settings → Platforms, or via `xcrun simctl runtime delete`.",
            entries: entries
        )]
    }

    private static func ollamaDuplicateTags() -> [DuplicateGroup] {
        // Best-effort: parse `ollama list` for same model family with multiple tags
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
        var byFamily: [String: [DuplicateEntry]] = [:]
        for line in text.split(separator: "\n").dropFirst() {
            let parts = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard parts.count >= 3 else { continue }
            let name = parts[0] // e.g. llama3:8b
            let family = name.split(separator: ":").first.map(String.init) ?? name
            let sizeText = parts.count >= 3 ? parts[2] : "?"
            let path = PathUtil.expand("~/.ollama/models")
            byFamily[family, default: []].append(
                DuplicateEntry(name: name, path: path, sizeBytes: parseOllamaSize(parts), detail: "Size column: \(sizeText)")
            )
        }
        return byFamily.compactMap { family, entries in
            guard entries.count > 1 else { return nil }
            return DuplicateGroup(
                id: "dup-ollama-\(family)",
                title: "Multiple Ollama tags for \(family)",
                kind: "AI Models",
                explanation: "Same model family with different tags wastes disk. Remove with `ollama rm <name>`.",
                entries: entries
            )
        }
    }

    private static func parseOllamaSize(_ parts: [String]) -> Int64 {
        // ollama list: NAME ID SIZE MODIFIED — size like "4.7 GB"
        guard parts.count >= 3 else { return 0 }
        // Find token ending with B
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

    private static func versionFolderGroup(
        id: String, title: String, kind: String, explanation: String, root: String
    ) -> [DuplicateGroup] {
        let kids = listChildren(root)
        guard kids.count > 1 else { return [] }
        let entries = kids.map {
            DuplicateEntry(name: $0.name, path: $0.path, sizeBytes: $0.bytes, detail: "Installed runtime")
        }
        return [DuplicateGroup(id: id, title: title, kind: kind, explanation: explanation, entries: entries)]
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
        return out.sorted { $0.sizeBytes > $1.sizeBytes }
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
        // Prefer depth-1 children; if root itself is the blob store, measure root once
        let children = (try? fm.contentsOfDirectory(atPath: root)) ?? []
        var entries: [AIModelEntry] = []
        for name in children where !name.hasPrefix(".") {
            let path = (root as NSString).appendingPathComponent(name)
            let bytes = Shell.size(path)
            guard bytes > 20_000_000 else { continue } // 20 MB+
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
