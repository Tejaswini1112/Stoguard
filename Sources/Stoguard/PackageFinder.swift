import Foundation

/// Finds installed developer packages / CLI tools the user may have forgotten about.
struct PackageFinding: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let source: String // brew, npm, pipx, pip, cargo, bin, app
    let path: String
    let sizeBytes: Int64
    /// What this package is / why someone installs it.
    let definition: String
    let detail: String
    var lastActivity: Date? = nil

    var sizeText: String { ByteText.string(sizeBytes) }
    var daysIdle: Int? {
        guard let lastActivity else { return nil }
        return max(0, Int(Date().timeIntervalSince(lastActivity) / 86_400))
    }
}

enum PackageFinder {
    static func scan() -> [PackageFinding] {
        // Descriptions are nice-to-have; never block listing installs on brew info.
        let brewDesc = loadBrewDescriptions()
        var out: [PackageFinding] = []
        out += brewPackages(descriptions: brewDesc)
        out += npmGlobals()
        out += pipxPackages()
        out += cargoBins()
        out += looseBins()
        out.sort {
            if $0.sizeBytes != $1.sizeBytes { return $0.sizeBytes > $1.sizeBytes }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        return out
    }

    private static func make(
        id: String, name: String, source: String, path: String,
        sizeBytes: Int64, detail: String, lastActivity: Date?,
        brewDesc: [String: String] = [:]
    ) -> PackageFinding {
        let catalog = PackageCatalog.definition(for: name, source: source)
        let fromBrew = brewDesc[name.lowercased()]
        let definition = (fromBrew?.isEmpty == false) ? fromBrew! : catalog
        return PackageFinding(
            id: id, name: name, source: source, path: path,
            sizeBytes: sizeBytes, definition: definition, detail: detail,
            lastActivity: lastActivity
        )
    }

    private static func loadBrewDescriptions() -> [String: String] {
        let brew = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
        guard let brew else { return [:] }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: brew)
        proc.arguments = ["info", "--json=v2", "--installed"]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do { try proc.run() } catch { return [:] }

        // Cap wait — listing Cellar must not hang if brew is slow.
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            proc.waitUntilExit()
            group.leave()
        }
        if group.wait(timeout: .now() + 8) == .timedOut {
            proc.terminate()
            return [:]
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let formulae = json["formulae"] as? [[String: Any]]
        else { return [:] }
        var map: [String: String] = [:]
        for f in formulae {
            guard let name = f["name"] as? String else { continue }
            let desc = (f["desc"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !desc.isEmpty { map[name.lowercased()] = desc }
        }
        return map
    }

    // MARK: - Homebrew

    private static func brewPackages(descriptions: [String: String]) -> [PackageFinding] {
        let cellarCandidates = [
            "/opt/homebrew/Cellar",
            "/usr/local/Cellar",
            (NSHomeDirectory() as NSString).appendingPathComponent("homebrew/Cellar"),
        ]
        var versionPaths: [(formula: String, ver: String, path: String)] = []
        let fm = FileManager.default
        for cellar in cellarCandidates where fm.fileExists(atPath: cellar) {
            guard let formulae = try? fm.contentsOfDirectory(atPath: cellar) else { continue }
            for formula in formulae {
                let formulaDir = (cellar as NSString).appendingPathComponent(formula)
                guard let versions = try? fm.contentsOfDirectory(atPath: formulaDir), !versions.isEmpty
                else { continue }
                for ver in versions {
                    let path = (formulaDir as NSString).appendingPathComponent(ver)
                    var isDir: ObjCBool = false
                    guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { continue }
                    versionPaths.append((formula, ver, path))
                }
            }
        }

        // Size in parallel — sequential `du` over 100+ formulae felt like “not found”.
        let lock = NSLock()
        var findings: [PackageFinding] = []
        DispatchQueue.concurrentPerform(iterations: versionPaths.count) { i in
            let item = versionPaths[i]
            let size = Shell.size(item.path)
            guard size > 500_000 else { return } // include smaller CLIs too
            let finding = make(
                id: "brew-\(item.formula)-\(item.ver)",
                name: item.formula,
                source: "Homebrew",
                path: item.path,
                sizeBytes: size,
                detail: "Cellar \(item.ver) · \(ByteText.string(size)). Uninstall: brew uninstall \(item.formula)",
                lastActivity: PathActivity.lastActivity(at: item.path),
                brewDesc: descriptions
            )
            lock.lock()
            findings.append(finding)
            lock.unlock()
        }
        return findings
    }

    // MARK: - npm global

    private static func npmGlobals() -> [PackageFinding] {
        let roots = [
            "/opt/homebrew/lib/node_modules",
            "/usr/local/lib/node_modules",
            (NSHomeDirectory() as NSString).appendingPathComponent(".npm-global/lib/node_modules"),
            (NSHomeDirectory() as NSString).appendingPathComponent(".local/lib/node_modules"),
        ]
        var findings: [PackageFinding] = []
        let fm = FileManager.default
        for root in roots where fm.fileExists(atPath: root) {
            guard let names = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for name in names where !name.hasPrefix(".") {
                if name == "npm" || name == "corepack" { continue }
                let path = (root as NSString).appendingPathComponent(name)
                let size = Shell.size(path)
                guard size > 200_000 else { continue }
                let pkgDesc = readNpmDescription(at: path)
                var brewLike: [String: String] = [:]
                if let pkgDesc, !pkgDesc.isEmpty { brewLike[name.lowercased()] = pkgDesc }
                findings.append(make(
                    id: "npm-\(name)-\(path.hashValue)",
                    name: name,
                    source: "npm global",
                    path: path,
                    sizeBytes: size,
                    detail: "\(ByteText.string(size)) on disk. Remove: npm uninstall -g \(name)",
                    lastActivity: PathActivity.lastActivity(at: path),
                    brewDesc: brewLike
                ))
            }
        }
        return findings
    }

    // MARK: - pipx

    private static func pipxPackages() -> [PackageFinding] {
        let root = (NSHomeDirectory() as NSString).appendingPathComponent(".local/share/pipx/venvs")
        let fm = FileManager.default
        guard fm.fileExists(atPath: root),
              let names = try? fm.contentsOfDirectory(atPath: root) else { return [] }
        return names.compactMap { name -> PackageFinding? in
            let path = (root as NSString).appendingPathComponent(name)
            let size = Shell.size(path)
            guard size > 500_000 else { return nil }
            return make(
                id: "pipx-\(name)",
                name: name,
                source: "pipx",
                path: path,
                sizeBytes: size,
                detail: "\(ByteText.string(size)) pipx env. Remove: pipx uninstall \(name)",
                lastActivity: PathActivity.lastActivity(at: path)
            )
        }
    }

    private static func readNpmDescription(at path: String) -> String? {
        let pkg = (path as NSString).appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: pkg)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let desc = json["description"] as? String
        else { return nil }
        let t = desc.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    // MARK: - cargo bins

    private static func cargoBins() -> [PackageFinding] {
        let root = (NSHomeDirectory() as NSString).appendingPathComponent(".cargo/bin")
        return binaries(in: root, source: "Cargo bin", detailPrefix: "Rust cargo-installed binary")
    }

    private static func looseBins() -> [PackageFinding] {
        let roots = [
            (NSHomeDirectory() as NSString).appendingPathComponent(".local/bin"),
        ]
        var out: [PackageFinding] = []
        for root in roots {
            out += binaries(in: root, source: "User bin", detailPrefix: "Executable on your PATH")
        }
        return out
    }

    private static func binaries(in root: String, source: String, detailPrefix: String) -> [PackageFinding] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: root) else { return [] }
        var out: [PackageFinding] = []
        for name in names {
            let path = (root as NSString).appendingPathComponent(name)
            guard let attrs = try? fm.attributesOfItem(atPath: path) else { continue }
            let type = attrs[.type] as? FileAttributeType
            if type == .typeSymbolicLink { continue }
            let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            guard size > 200_000 else { continue }
            out.append(make(
                id: "bin-\(source)-\(name)",
                name: name,
                source: source,
                path: path,
                sizeBytes: size,
                detail: "\(ByteText.string(size)) · \(detailPrefix). Confirm you still use `\(name)` before removing.",
                lastActivity: PathActivity.lastActivity(at: path)
            ))
        }
        return out
    }
}
