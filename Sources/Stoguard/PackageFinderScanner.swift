import Foundation

/// Finds installed CLI tools and package-manager packages the user may have forgotten.
enum PackageFinderScanner {
    private nonisolated(unsafe) static let fm = FileManager.default

    static func scan() -> [InstalledPackage] {
        var results: [InstalledPackage] = []
        results += brewFormulae()
        results += brewCasks()
        results += npmGlobal()
        results += pipPackages()
        results += pathBinaries()

        var seen = Set<String>()
        return results
            .filter { seen.insert($0.path).inserted }
            .sorted { $0.sizeBytes > $1.sizeBytes }
    }

    // MARK: - Homebrew

    private static func brewFormulae() -> [InstalledPackage] {
        guard let brew = brewExecutable() else { return [] }
        guard let list = shell(brew, ["list", "--formula"]) else { return [] }
        return list.split(separator: "\n").compactMap { line in
            let name = line.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            let prefix = shell(brew, ["--prefix", name]).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            } ?? ""
            guard !prefix.isEmpty, fm.fileExists(atPath: prefix) else { return nil }
            return InstalledPackage(
                id: "brew:\(name)",
                name: name,
                source: "Homebrew",
                path: prefix,
                sizeBytes: Shell.size(prefix),
                detail: "Homebrew formula",
                uninstallCommand: "brew uninstall \(name)",
                modifiedAt: modificationDate(at: prefix)
            )
        }
    }

    private static func brewCasks() -> [InstalledPackage] {
        guard let brew = brewExecutable() else { return [] }
        guard let list = shell(brew, ["list", "--cask"]) else { return [] }
        return list.split(separator: "\n").compactMap { line in
            let name = line.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            let caskroom = PathUtil.expand("~/Library/Caches/Homebrew/Cask")
            let appPath = findCaskApp(name: name, caskroom: caskroom)
                ?? shell(brew, ["--caskroom", name]).map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                } ?? ""
            guard !appPath.isEmpty, fm.fileExists(atPath: appPath) else { return nil }
            return InstalledPackage(
                id: "cask:\(name)",
                name: name,
                source: "Homebrew Cask",
                path: appPath,
                sizeBytes: Shell.size(appPath),
                detail: "Homebrew cask",
                uninstallCommand: "brew uninstall --cask \(name)",
                modifiedAt: modificationDate(at: appPath)
            )
        }
    }

    private static func findCaskApp(name: String, caskroom: String) -> String? {
        let base = (caskroom as NSString).appendingPathComponent(name)
        guard fm.fileExists(atPath: base),
              let versions = try? fm.contentsOfDirectory(atPath: base) else { return nil }
        for version in versions {
            let dir = (base as NSString).appendingPathComponent(version)
            guard let items = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            if let app = items.first(where: { $0.hasSuffix(".app") }) {
                return (dir as NSString).appendingPathComponent(app)
            }
        }
        return nil
    }

    // MARK: - npm / pip

    private static func npmGlobal() -> [InstalledPackage] {
        guard let npm = which("npm") else { return [] }
        guard let json = shell(npm, ["list", "-g", "--depth=0", "--json"]),
              let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let deps = root["dependencies"] as? [String: Any]
        else { return [] }

        let globalRoot = shell(npm, ["root", "-g"])?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return deps.keys.sorted().compactMap { name in
            let path = (globalRoot as NSString).appendingPathComponent(name)
            guard fm.fileExists(atPath: path) else { return nil }
            return InstalledPackage(
                id: "npm:\(name)",
                name: name,
                source: "npm global",
                path: path,
                sizeBytes: Shell.size(path),
                detail: "Global npm package",
                uninstallCommand: "npm uninstall -g \(name)",
                modifiedAt: modificationDate(at: path)
            )
        }
    }

    private static func pipPackages() -> [InstalledPackage] {
        guard let pipPath = which("pip3") ?? which("pip") else { return [] }
        let pipCmd = (pipPath as NSString).lastPathComponent
        guard let json = shell(pipPath, ["list", "--format=json"]),
              let data = json.data(using: .utf8),
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }

        let sitePackages = guessPipSitePackages()
        return list.compactMap { entry -> InstalledPackage? in
            guard let name = entry["name"] as? String else { return nil }
            let lower = name.lowercased()
            if lower == "pip" || lower == "setuptools" || lower == "wheel" { return nil }
            let path = sitePackages.compactMap { findPackageDir(name: name, in: $0) }.first
                ?? PathUtil.expand("~/.local/bin/\(name)")
            guard fm.fileExists(atPath: path) else { return nil }
            return InstalledPackage(
                id: "pip:\(name)",
                name: name,
                source: "pip",
                path: path,
                sizeBytes: Shell.size(path),
                detail: "Python package",
                uninstallCommand: "\(pipCmd) uninstall \(name)",
                modifiedAt: modificationDate(at: path)
            )
        }
    }

    // MARK: - PATH binaries

    private static func pathBinaries() -> [InstalledPackage] {
        let binDirs = [
            "/usr/local/bin",
            PathUtil.expand("~/.local/bin"),
            PathUtil.expand("~/go/bin"),
            PathUtil.expand("~/.cargo/bin"),
            PathUtil.expand("~/.bun/bin"),
        ]
        var results: [InstalledPackage] = []
        var seen = Set<String>()

        for dir in binDirs {
            guard fm.fileExists(atPath: dir),
                  let names = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for name in names {
                let path = (dir as NSString).appendingPathComponent(name)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else { continue }
                guard seen.insert(path).inserted else { continue }
                let bytes = Shell.size(path)
                guard bytes > 0 else { continue }
                results.append(InstalledPackage(
                    id: "path:\(path)",
                    name: name,
                    source: "PATH",
                    path: path,
                    sizeBytes: bytes,
                    detail: "Binary in \((dir as NSString).lastPathComponent)",
                    uninstallCommand: nil,
                    modifiedAt: modificationDate(at: path)
                ))
            }
        }
        return results
    }

    // MARK: - Helpers

    private static func modificationDate(at path: String) -> Date? {
        try? fm.attributesOfItem(atPath: path)[.modificationDate] as? Date
    }

    private static func brewExecutable() -> String? {
        for path in ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"] {
            if fm.isExecutableFile(atPath: path) { return path }
        }
        return which("brew")
    }

    private static func which(_ name: String) -> String? {
        shell("/usr/bin/which", [name])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    private static func shell(_ executable: String, _ args: [String]) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = args
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do { try proc.run() } catch { return nil }
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        return String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }

    private static func guessPipSitePackages() -> [String] {
        guard let pipPath = which("pip3") ?? which("pip"),
              let out = shell(pipPath, ["show", "pip"]),
              let line = out.split(separator: "\n").first(where: { $0.hasPrefix("Location:") })
        else { return [] }
        let loc = line.replacingOccurrences(of: "Location:", with: "")
            .trimmingCharacters(in: .whitespaces)
        return loc.isEmpty ? [] : [loc]
    }

    private static func findPackageDir(name: String, in sitePackages: String) -> String? {
        let normalized = name.lowercased().replacingOccurrences(of: "-", with: "_")
        let candidates = [
            (sitePackages as NSString).appendingPathComponent(name),
            (sitePackages as NSString).appendingPathComponent(normalized),
            (sitePackages as NSString).appendingPathComponent("\(normalized)-*.dist-info"),
        ]
        for path in candidates where !path.contains("*") {
            if fm.fileExists(atPath: path) { return path }
        }
        guard let items = try? fm.contentsOfDirectory(atPath: sitePackages) else { return nil }
        if let match = items.first(where: {
            $0.lowercased().hasPrefix(normalized) && ($0.hasSuffix(".dist-info") || $0 == normalized)
        }) {
            return (sitePackages as NSString).appendingPathComponent(match)
        }
        return nil
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
