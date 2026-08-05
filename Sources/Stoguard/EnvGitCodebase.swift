import Foundation

// MARK: - Environment Doctor

struct EnvFinding: Identifiable, Hashable, Sendable {
    enum Severity: String, Sendable { case ok, warn, info }
    let id: String
    let title: String
    let detail: String
    let severity: Severity
    let fixHint: String?
}

enum EnvDoctor {
    static func diagnose() -> [EnvFinding] {
        var findings: [EnvFinding] = []
        findings += brew()
        findings += node()
        findings += python()
        findings += java()
        findings += android()
        findings += xcodeCLTools()
        return findings
    }

    private static func brew() -> [EnvFinding] {
        guard which("brew") != nil else {
            return [EnvFinding(
                id: "brew-missing", title: "Homebrew not found",
                detail: "Homebrew is the common macOS package manager. Optional unless you use it.",
                severity: .info, fixHint: "https://brew.sh"
            )]
        }
        let outdated = shell("brew", ["outdated", "--quiet"])
        let lines = outdated.split(separator: "\n").filter { !$0.isEmpty }
        if lines.isEmpty {
            return [EnvFinding(
                id: "brew-ok", title: "Homebrew healthy",
                detail: "No outdated formulae reported.",
                severity: .ok, fixHint: nil
            )]
        }
        return [EnvFinding(
            id: "brew-outdated",
            title: "\(lines.count) outdated Homebrew formulae",
            detail: lines.prefix(12).joined(separator: ", ") + (lines.count > 12 ? "…" : ""),
            severity: .warn,
            fixHint: "brew upgrade"
        )]
    }

    private static func node() -> [EnvFinding] {
        var out: [EnvFinding] = []
        let nvm = PathUtil.expand("~/.nvm/versions/node")
        let versions = dirNames(nvm)
        if versions.count > 1 {
            out.append(EnvFinding(
                id: "node-multi",
                title: "\(versions.count) Node versions via nvm",
                detail: versions.joined(separator: ", "),
                severity: .warn,
                fixHint: "Keep one LTS; `nvm uninstall` the rest."
            ))
        }
        if which("node") != nil {
            let v = shell("node", ["-v"]).trimmingCharacters(in: .whitespacesAndNewlines)
            out.append(EnvFinding(
                id: "node-active", title: "Active Node \(v)",
                detail: "Resolved from PATH.",
                severity: .ok, fixHint: nil
            ))
        }
        // Duplicate global installs: /usr/local vs nvm vs brew
        var installs: [String] = []
        for p in ["/usr/local/bin/node", "/opt/homebrew/bin/node", PathUtil.expand("~/.nvm/nvm.sh")] {
            if FileManager.default.fileExists(atPath: p) { installs.append(p) }
        }
        if installs.count > 1 {
            out.append(EnvFinding(
                id: "node-paths",
                title: "Multiple Node install locations",
                detail: installs.joined(separator: " · "),
                severity: .warn,
                fixHint: "Pick one installer (nvm OR Homebrew) to avoid PATH conflicts."
            ))
        }
        return out
    }

    private static func python() -> [EnvFinding] {
        var out: [EnvFinding] = []
        let pyenv = dirNames(PathUtil.expand("~/.pyenv/versions"))
        if pyenv.count > 1 {
            out.append(EnvFinding(
                id: "py-multi",
                title: "\(pyenv.count) Python versions (pyenv)",
                detail: pyenv.joined(separator: ", "),
                severity: .warn,
                fixHint: "pyenv uninstall <version>"
            ))
        }
        let venvs = findShallow(
            roots: ["~/Documents", "~/Developer", "~/Projects", "~/Code", "~/Desktop"],
            names: [".venv", "venv"],
            maxDepth: 4
        )
        if venvs.count >= 3 {
            out.append(EnvFinding(
                id: "py-venvs",
                title: "\(venvs.count) Python virtual environments found",
                detail: "Stale venvs often linger after projects end.",
                severity: .info,
                fixHint: "Delete unused .venv folders or run a Developer scan."
            ))
        }
        return out
    }

    private static func java() -> [EnvFinding] {
        let root = "/Library/Java/JavaVirtualMachines"
        let jvms = dirNames(root)
        guard jvms.count > 1 else { return [] }
        return [EnvFinding(
            id: "java-multi",
            title: "\(jvms.count) Java JDKs installed",
            detail: jvms.joined(separator: ", "),
            severity: .warn,
            fixHint: "Conflicts happen when JAVA_HOME points at the wrong JDK. Keep the versions you need."
        )]
    }

    private static func android() -> [EnvFinding] {
        let sdk = PathUtil.expand("~/Library/Android/sdk")
        guard FileManager.default.fileExists(atPath: sdk) else { return [] }
        let platform = (sdk as NSString).appendingPathComponent("platforms")
        let platforms = dirNames(platform)
        if platforms.isEmpty {
            return [EnvFinding(
                id: "android-incomplete",
                title: "Android SDK incomplete",
                detail: "SDK folder exists but no platforms installed.",
                severity: .warn,
                fixHint: "Open Android Studio → SDK Manager."
            )]
        }
        return [EnvFinding(
            id: "android-ok",
            title: "Android SDK present",
            detail: "\(platforms.count) platform(s): \(platforms.prefix(5).joined(separator: ", "))",
            severity: .ok,
            fixHint: nil
        )]
    }

    private static func xcodeCLTools() -> [EnvFinding] {
        let xcode = shell("xcode-select", ["-p"]).trimmingCharacters(in: .whitespacesAndNewlines)
        if xcode.isEmpty {
            return [EnvFinding(
                id: "xcode-missing",
                title: "Xcode CLT path missing",
                detail: "Developer tools may not be configured.",
                severity: .warn,
                fixHint: "xcode-select --install"
            )]
        }
        return [EnvFinding(
            id: "xcode-ok",
            title: "Developer tools path set",
            detail: xcode,
            severity: .ok,
            fixHint: nil
        )]
    }

    // Helpers
    private static func which(_ cmd: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = [cmd]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do { try proc.run() } catch { return nil }
        proc.waitUntilExit()
        let r = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return r.isEmpty ? nil : r
    }

    private static func shell(_ launch: String, _ args: [String]) -> String {
        let proc = Process()
        if launch.hasPrefix("/") {
            proc.executableURL = URL(fileURLWithPath: launch)
            proc.arguments = args
        } else if let path = which(launch) {
            proc.executableURL = URL(fileURLWithPath: path)
            proc.arguments = args
        } else {
            return ""
        }
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do { try proc.run() } catch { return "" }
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            proc.waitUntilExit()
            group.leave()
        }
        _ = group.wait(timeout: .now() + 20)
        if proc.isRunning { proc.terminate() }
        return String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }

    private static func dirNames(_ path: String) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: path))?
            .filter { !$0.hasPrefix(".") }
            .sorted() ?? []
    }

    private static func findShallow(roots: [String], names: Set<String>, maxDepth: Int) -> [String] {
        var found: [String] = []
        func walk(_ dir: String, depth: Int) {
            guard depth <= maxDepth, found.count < 40 else { return }
            guard let kids = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return }
            for name in kids {
                let path = (dir as NSString).appendingPathComponent(name)
                if names.contains(name) {
                    found.append(path)
                    continue
                }
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { continue }
                if ["Library", "node_modules", ".git", "DerivedData"].contains(name) { continue }
                walk(path, depth: depth + 1)
            }
        }
        for r in roots {
            walk(PathUtil.expand(r), depth: 0)
        }
        return found
    }
}

// MARK: - Git repository optimizer

struct GitRepoReport: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let path: String
    let gitBytes: Int64
    let workingBytes: Int64
    let branchCount: Int
    let stashCount: Int
    let largePackHint: String?
    let recommendations: [String]
}

enum GitOptimizer {
    static func scan(roots: [String] = [
        "~/Documents", "~/Developer", "~/Projects", "~/Code", "~/Desktop", "~/src"
    ]) -> [GitRepoReport] {
        var reports: [GitRepoReport] = []
        for root in roots {
            walk(PathUtil.expand(root), depth: 0, into: &reports)
        }
        return reports.sorted { $0.gitBytes > $1.gitBytes }
    }

    private static func walk(_ dir: String, depth: Int, into reports: inout [GitRepoReport]) {
        guard depth < 5, reports.count < 40 else { return }
        let git = (dir as NSString).appendingPathComponent(".git")
        if FileManager.default.fileExists(atPath: git) {
            reports.append(analyze(repo: dir, gitPath: git))
            return
        }
        guard let kids = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return }
        for name in kids {
            if name.hasPrefix(".") || ["Library", "node_modules", "DerivedData"].contains(name) { continue }
            let path = (dir as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { continue }
            walk(path, depth: depth + 1, into: &reports)
        }
    }

    private static func analyze(repo: String, gitPath: String) -> GitRepoReport {
        let gitBytes = Shell.size(gitPath)
        let workingBytes = Shell.size(repo)
        let branches = countLines(git(repo, ["branch", "-a"]))
        let stashes = countLines(git(repo, ["stash", "list"]))
        var recs: [String] = []
        if gitBytes > 500_000_000 {
            recs.append("`.git` is over 500 MB — check for large binaries (`git rev-list --objects --all | …`) or Git LFS.")
        }
        if branches > 30 {
            recs.append("\(branches) branches — prune merged remotes: `git fetch -p` and delete stale locals.")
        }
        if stashes > 5 {
            recs.append("\(stashes) stashes — drop old ones with `git stash clear` (destructive) or `git stash drop`.")
        }
        if gitBytes > workingBytes / 2 && gitBytes > 100_000_000 {
            recs.append("Git metadata rivals working tree size — history may need `git gc` or a shallow clone.")
        }
        if recs.isEmpty {
            recs.append("Looks reasonable. Occasional `git gc` keeps packs tidy.")
        }
        return GitRepoReport(
            id: repo,
            name: (repo as NSString).lastPathComponent,
            path: repo,
            gitBytes: gitBytes,
            workingBytes: workingBytes,
            branchCount: branches,
            stashCount: stashes,
            largePackHint: gitBytes > 1_000_000_000 ? "Very large object database" : nil,
            recommendations: recs
        )
    }

    private static func git(_ repo: String, _ args: [String]) -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        proc.arguments = ["-C", repo] + args
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do { try proc.run() } catch { return "" }
        proc.waitUntilExit()
        return String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }

    private static func countLines(_ s: String) -> Int {
        s.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
    }
}

// MARK: - Codebase analyzer

struct CodebaseFinding: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let path: String
    let bytes: Int64
    let kind: String
    let advice: String
}

enum CodebaseAnalyzer {
    static func analyze(root: String) -> [CodebaseFinding] {
        let abs = PathUtil.expand(root)
        guard FileManager.default.fileExists(atPath: abs) else { return [] }
        var findings: [CodebaseFinding] = []
        let heavyNames: [(String, String, String)] = [
            ("node_modules", "Dependencies", "Reinstall with your package manager; don't commit."),
            (".git", "VCS", "See Git Optimizer for history bloat."),
            ("dist", "Build", "Generated output — safe to delete before rebuild."),
            ("build", "Build", "Generated output — safe to delete before rebuild."),
            ("target", "Build", "Rust/Java target — cargo/mvn clean."),
            (".next", "Build", "Next.js cache — delete and rebuild."),
            ("Pods", "Dependencies", "pod install recreates."),
            ("vendor", "Dependencies", "Language vendor dir — recreate via package tool."),
            ("__pycache__", "Cache", "Bytecode cache — safe."),
            (".venv", "Environment", "Recreate with python -m venv."),
        ]

        walk(abs, depth: 0, maxDepth: 5) { path, name in
            if let hit = heavyNames.first(where: { $0.0 == name }) {
                let bytes = Shell.size(path)
                guard bytes > 5_000_000 else { return }
                findings.append(CodebaseFinding(
                    id: path, title: "\(name) · \((path as NSString).deletingLastPathComponent as NSString).lastPathComponent",
                    path: path, bytes: bytes, kind: hit.1, advice: hit.2
                ))
            }
            // Large media/binaries at shallow depth
            if depthIsFile(path), let ext = name.split(separator: ".").last.map(String.init)?.lowercased() {
                let heavyExt = ["mp4", "mov", "psd", "zip", "dmg", "gguf", "pt", "onnx", "wasm", "pack"]
                if heavyExt.contains(ext) {
                    let bytes = Shell.size(path)
                    if bytes > 50_000_000 {
                        findings.append(CodebaseFinding(
                            id: path, title: name, path: path, bytes: bytes,
                            kind: "Large binary",
                            advice: "Consider Git LFS, external storage, or removing from the repo."
                        ))
                    }
                }
            }
        }
        return findings.sorted { $0.bytes > $1.bytes }
    }

    private static func depthIsFile(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        return !isDir.boolValue
    }

    private static func walk(_ dir: String, depth: Int, maxDepth: Int, visit: (String, String) -> Void) {
        guard depth <= maxDepth else { return }
        guard let kids = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return }
        for name in kids {
            let path = (dir as NSString).appendingPathComponent(name)
            visit(path, name)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { continue }
            if ["Library", ".Trash"].contains(name) { continue }
            // Don't descend into huge trees once noted
            if ["node_modules", ".git", "Pods", "target", "dist"].contains(name) { continue }
            walk(path, depth: depth + 1, maxDepth: maxDepth, visit: visit)
        }
    }
}
