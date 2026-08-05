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
    struct PluginFile: Codable {
        var id: String
        var name: String
        var version: String?
        /// macOS | windows | linux | any
        var platforms: [String]?
        var rules: [Rule]
    }

    static var pluginsDirectory: URL {
        SupportPaths.directory.appendingPathComponent("Plugins", isDirectory: true)
    }

    static func ensureScaffold() {
        SupportPaths.ensureDirectory()
        try? FileManager.default.createDirectory(at: pluginsDirectory, withIntermediateDirectories: true)
        let example = pluginsDirectory.appendingPathComponent("example-rust.json")
        if !FileManager.default.fileExists(atPath: example.path) {
            let sample = """
            {
              "id": "example-rust",
              "name": "Rust extras",
              "version": "1.0",
              "platforms": ["macos", "linux"],
              "rules": [
                {
                  "id": "plugin-cargo-git",
                  "name": "Cargo git checkouts",
                  "path": "~/.cargo/git",
                  "category": "Package Managers",
                  "safety": "check",
                  "note": "Plugin-provided rule. Cargo git dependency checkouts."
                }
              ]
            }
            """
            try? sample.data(using: .utf8)?.write(to: example, options: .atomic)
        }
    }

    static func loadRules(platform: String = "macos") -> [Rule] {
        ensureScaffold()
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: pluginsDirectory, includingPropertiesForKeys: nil)
        else { return [] }

        var rules: [Rule] = []
        for url in files where url.pathExtension.lowercased() == "json" {
            guard let data = try? Data(contentsOf: url),
                  let plugin = try? JSONDecoder().decode(PluginFile.self, from: data)
            else { continue }
            let plats = (plugin.platforms ?? ["any"]).map { $0.lowercased() }
            if plats.contains("any") || plats.contains(platform) {
                rules.append(contentsOf: plugin.rules)
            }
        }
        return rules
    }

    static func listPlugins() -> [PluginFile] {
        ensureScaffold()
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: pluginsDirectory, includingPropertiesForKeys: nil)
        else { return [] }
        return files.compactMap { url -> PluginFile? in
            guard url.pathExtension.lowercased() == "json",
                  let data = try? Data(contentsOf: url)
            else { return nil }
            return try? JSONDecoder().decode(PluginFile.self, from: data)
        }
    }
}
