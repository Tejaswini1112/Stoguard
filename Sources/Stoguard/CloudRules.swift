import Foundation

/// Versioned remote rules — download when newer, fall back to bundled `rules.json`.
enum CloudRules {
    /// Optional remote rules feed. Set UserDefaults `stoguard.rulesFeedURL` to enable.
    /// No default third-party URL — Stoguard ships bundled rules.
    static var feedURL: URL? {
        for key in ["stoguard.rulesFeedURL", "vacs.rulesFeedURL"] {
            if let s = UserDefaults.standard.string(forKey: key),
               let u = URL(string: s), !s.isEmpty {
                return u
            }
        }
        return nil
    }

    static var manifestURL: URL? {
        for key in ["stoguard.rulesManifestURL", "vacs.rulesManifestURL"] {
            if let s = UserDefaults.standard.string(forKey: key),
               let u = URL(string: s), !s.isEmpty {
                return u
            }
        }
        return nil
    }

    private static var cacheFile: URL {
        SupportPaths.directory.appendingPathComponent("rules-cloud.json")
    }

    private static var metaFile: URL {
        SupportPaths.directory.appendingPathComponent("rules-meta.json")
    }

    struct Meta: Codable {
        var etag: String?
        var fetchedAt: Date?
        var source: String
        var ruleCount: Int
        var version: String?
    }

    struct Manifest: Codable {
        var version: String
        var updated: String?
        var rulesURL: String?
        var minAppVersion: String?
    }

    static func loadCachedRules() -> [Rule]? {
        guard let data = try? Data(contentsOf: cacheFile),
              let rules = try? JSONDecoder().decode([Rule].self, from: data),
              !rules.isEmpty
        else { return nil }
        return rules
    }

    static func loadMeta() -> Meta? {
        guard let data = try? Data(contentsOf: metaFile) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(Meta.self, from: data)
    }

    /// Merge: plugins + cloud/cached + bundled (first id wins).
    static func resolveRules(bundled: [Rule], plugins: [Rule]) -> [Rule] {
        var seen = Set<String>()
        var out: [Rule] = []
        for r in plugins + (loadCachedRules() ?? []) + bundled {
            if seen.insert(r.id).inserted { out.append(r) }
        }
        return out
    }

    @discardableResult
    static func refresh(timeout: TimeInterval = 12) async -> (rules: [Rule]?, meta: Meta, error: String?) {
        SupportPaths.ensureDirectory()
        var meta = loadMeta() ?? Meta(etag: nil, fetchedAt: nil, source: "bundled", ruleCount: 0, version: nil)

        guard let feedURL else {
            meta.source = "bundled"
            meta.fetchedAt = Date()
            saveMeta(meta)
            return (loadCachedRules(), meta, "No remote feed configured — using bundled rules + plugins.")
        }

        do {
            if let manifestURL, let manifest = try? await fetchManifest(from: manifestURL) {
                meta.version = manifest.version
            }

            var request = URLRequest(url: feedURL, timeoutInterval: timeout)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            if let etag = meta.etag {
                request.setValue(etag, forHTTPHeaderField: "If-None-Match")
            }

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return (loadCachedRules(), meta, "Invalid response")
            }

            if http.statusCode == 304, let cached = loadCachedRules() {
                meta.fetchedAt = Date()
                saveMeta(meta)
                return (cached, meta, nil)
            }

            guard (200..<300).contains(http.statusCode) else {
                return (loadCachedRules(), meta, "HTTP \(http.statusCode)")
            }

            let rules = try JSONDecoder().decode([Rule].self, from: data)
            guard !rules.isEmpty else {
                return (loadCachedRules(), meta, "Empty rules feed")
            }

            try data.write(to: cacheFile, options: .atomic)
            meta.etag = http.value(forHTTPHeaderField: "ETag")
            meta.fetchedAt = Date()
            meta.source = feedURL.absoluteString
            meta.ruleCount = rules.count
            saveMeta(meta)
            return (rules, meta, nil)
        } catch {
            return (loadCachedRules(), meta, error.localizedDescription)
        }
    }

    private static func fetchManifest(from url: URL) async throws -> Manifest? {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return nil
        }
        return try? JSONDecoder().decode(Manifest.self, from: data)
    }

    private static func saveMeta(_ meta: Meta) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(meta) else { return }
        try? data.write(to: metaFile, options: .atomic)
    }
}

/// Drop-in technology plugins: `~/Library/Application Support/Stoguard/Plugins/*.json`
enum PluginLoader {
    struct PluginFile: Codable, Identifiable {
        var id: String
        var name: String
        var version: String?
        /// macOS | windows | linux | any
        var platforms: [String]?
        /// Human summary for the plugin pack.
        var description: String? = nil
        var documentationURL: String? = nil
        var author: String? = nil
        var rules: [Rule]

        var displayRisk: String {
            let levels = rules.compactMap(\.riskLevel)
            if levels.contains(where: { $0.lowercased() == "high" }) { return "high" }
            if levels.contains(where: { $0.lowercased() == "medium" }) { return "medium" }
            if levels.contains(where: { $0.lowercased() == "low" }) { return "low" }
            return rules.map(\.safety.rawValue).contains("never") ? "high" : "low"
        }
    }

    static var pluginsDirectory: URL {
        SupportPaths.directory.appendingPathComponent("Plugins", isDirectory: true)
    }

    static func ensureScaffold() {
        SupportPaths.ensureDirectory()
        try? FileManager.default.createDirectory(at: pluginsDirectory, withIntermediateDirectories: true)
        seedBundledExamplesIfNeeded()
        let readme = pluginsDirectory.appendingPathComponent("README.txt")
        if !FileManager.default.fileExists(atPath: readme.path) {
            let body = """
            Stoguard Plugin SDK
            See docs/PLUGIN_SDK.md — each plugin declares detection paths, explanation, risk, safe actions, and docs links.
            Packs: Plugins/<id>.json or Plugins/<id>/rules.json
            """
            try? body.data(using: .utf8)?.write(to: readme, options: .atomic)
        }
    }

    /// Copy repo example packs into Application Support once (non-destructive).
    private static func seedBundledExamplesIfNeeded() {
        let marker = pluginsDirectory.appendingPathComponent(".seeded-v2")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }

        let example = """
        {
          "id": "example-rust",
          "name": "Rust extras",
          "version": "1.1.0",
          "platforms": ["macos", "linux"],
          "description": "Extra Cargo caches beyond the bundled rules.",
          "documentationURL": "https://doc.rust-lang.org/cargo/",
          "author": "Stoguard",
          "rules": [
            {
              "id": "plugin-cargo-git",
              "name": "Cargo git checkouts",
              "path": "~/.cargo/git",
              "category": "Package Managers",
              "safety": "check",
              "note": "Plugin-provided rule. Cargo git dependency checkouts.",
              "explanation": "Cargo clones git dependencies here for builds.",
              "riskLevel": "low",
              "docsURL": "https://doc.rust-lang.org/cargo/guide/cargo-home.html",
              "safeActions": ["Review folder", "cargo cache clean (when available)", "Trash unused checkouts"],
              "whatRebuilds": "Next cargo build re-fetches needed git deps.",
              "canUndo": "Put Back from Trash if you Trashed the folder.",
              "isCommon": "Common on Rust shops that use git dependencies."
            }
          ]
        }
        """
        let url = pluginsDirectory.appendingPathComponent("example-rust.json")
        if !FileManager.default.fileExists(atPath: url.path) {
            try? example.data(using: .utf8)?.write(to: url, options: .atomic)
        }

        // Best-effort: seed from app bundle PluginExamples if present.
        if let res = Bundle.main.resourceURL?.appendingPathComponent("PluginExamples", isDirectory: true),
           let names = try? FileManager.default.contentsOfDirectory(atPath: res.path) {
            for name in names where name.hasSuffix(".json") {
                let dest = pluginsDirectory.appendingPathComponent(name)
                if !FileManager.default.fileExists(atPath: dest.path) {
                    try? FileManager.default.copyItem(at: res.appendingPathComponent(name), to: dest)
                }
            }
        }
        try? Data("ok".utf8).write(to: marker, options: .atomic)
    }

    static func loadRules(platform: String = "macos") -> [Rule] {
        ensureScaffold()
        var rules: [Rule] = []
        for plugin in listPlugins() {
            let plats = (plugin.platforms ?? ["any"]).map { $0.lowercased() }
            if plats.contains("any") || plats.contains(platform) {
                rules.append(contentsOf: plugin.rules)
            }
        }
        return rules
    }

    static func listPlugins() -> [PluginFile] {
        ensureScaffold()
        return pluginJSONURLs().compactMap { url -> PluginFile? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(PluginFile.self, from: data)
        }
    }

    /// Supports both `Plugins/foo.json` and `Plugins/docker/rules.json` packs.
    private static func pluginJSONURLs() -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: pluginsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var urls: [URL] = []
        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "json" else { continue }
            urls.append(url)
        }
        return urls.sorted { $0.path < $1.path }
    }
}
