import Foundation

/// Finds installed developer packages / CLI tools the user may have forgotten about.
struct PackageFinding: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let source: String // brew, npm, pipx, pip, cargo, bin, app
    let path: String
    let sizeBytes: Int64
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
        var out: [PackageFinding] = []
        out += brewPackages()
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

    // MARK: - Homebrew

    private static func brewPackages() -> [PackageFinding] {
        let cellarCandidates = [
            "/opt/homebrew/Cellar",
            "/usr/local/Cellar",
            (NSHomeDirectory() as NSString).appendingPathComponent("homebrew/Cellar"),
        ]
        var findings: [PackageFinding] = []
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
                    let size = Shell.size(path)
                    guard size > 1_000_000 else { continue } // skip tiny meta
                    findings.append(PackageFinding(
                        id: "brew-\(formula)-\(ver)",
                        name: formula,
                        source: "Homebrew",
                        path: path,
                        sizeBytes: size,
                        detail: "Cellar \(ver). Uninstall with `brew uninstall \(formula)` if unused.",
                        lastActivity: PathActivity.lastActivity(at: path)
                    ))
                }
            }
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
                guard size > 500_000 else { continue }
                findings.append(PackageFinding(
                    id: "npm-\(name)-\(path.hashValue)",
                    name: name,
                    source: "npm global",
                    path: path,
                    sizeBytes: size,
                    detail: "Global npm package. Remove with `npm uninstall -g \(name)` if you no longer use it.",
                    lastActivity: PathActivity.lastActivity(at: path)
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
            guard size > 1_000_000 else { return nil }
            return PackageFinding(
                id: "pipx-\(name)",
                name: name,
                source: "pipx",
                path: path,
                sizeBytes: size,
                detail: "pipx virtualenv. Remove with `pipx uninstall \(name)` if unused (e.g. forgotten CLI tools).",
                lastActivity: PathActivity.lastActivity(at: path)
            )
        }
    }

    // MARK: - cargo bins

    private static func cargoBins() -> [PackageFinding] {
        let root = (NSHomeDirectory() as NSString).appendingPathComponent(".cargo/bin")
        return binaries(in: root, source: "Cargo bin", detailPrefix: "Rust cargo-installed binary")
    }

    private static func looseBins() -> [PackageFinding] {
        let roots = [
            (NSHomeDirectory() as NSString).appendingPathComponent(".local/bin"),
            "/opt/homebrew/bin",
        ]
        var out: [PackageFinding] = []
        for root in roots {
            out += binaries(in: root, source: "User bin", detailPrefix: "Executable on your PATH")
        }
        // Cap noise from homebrew bin (thousands of symlinks) — only report large real files
        return out.filter { $0.sizeBytes >= 2_000_000 || $0.source == "User bin" }
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
            guard size > 500_000 else { continue }
            out.append(PackageFinding(
                id: "bin-\(source)-\(name)",
                name: name,
                source: source,
                path: path,
                sizeBytes: size,
                detail: "\(detailPrefix). Confirm you still use `\(name)` before removing.",
                lastActivity: PathActivity.lastActivity(at: path)
            ))
        }
        return out
    }
}
