import Foundation

/// Recursive scan for dev project artifacts — node_modules, build outputs, venvs.
enum ProjectScanner {
    static let searchRoots = [
        "~/Documents", "~/Developer", "~/Projects", "~/Code",
        "~/Desktop", "~/Dropbox", "~/src",
    ]

    /// (folder name, note suffix)
    static let artifacts: [(String, String)] = [
        ("node_modules", "JavaScript dependencies. Reinstall with npm/yarn/pnpm install."),
        (".next", "Next.js build cache. Rebuilt on next dev/build."),
        (".nuxt", "Nuxt build cache. Rebuilt on next dev/build."),
        ("dist", "Build output folder. Rebuilt on next compile."),
        ("build", "Build output folder. Rebuilt on next compile."),
        ("target", "Rust compile output. Rebuilt on next cargo build."),
        (".venv", "Python virtual environment. Recreate with python -m venv."),
        ("venv", "Python virtual environment. Recreate with python -m venv."),
        (".pytest_cache", "pytest cache. Regenerated on next test run."),
        (".mypy_cache", "mypy type-check cache. Regenerated on next run."),
        (".turbo", "Turborepo cache. Rebuilt on next turbo run."),
        (".parcel-cache", "Parcel bundler cache. Rebuilt on next build."),
        (".gradle", "Project-level Gradle cache. Rebuilt on next build."),
        ("Pods", "CocoaPods dependencies. Reinstall with pod install."),
        (".dart_tool", "Dart/Flutter tool cache. Rebuilt automatically."),
        (".svelte-kit", "SvelteKit build cache. Rebuilt on next dev."),
        (".angular", "Angular CLI cache. Rebuilt on next ng build."),
        ("coverage", "Test coverage output. Regenerated on next test run."),
        ("__pycache__", "Python bytecode cache. Regenerated automatically."),
    ]

    static let staleDays = 30

    static func scan(onItem: @escaping (ScanItem) -> Void) {
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-Double(staleDays) * 86400)

        for root in searchRoots {
            let absRoot = PathUtil.expand(root)
            guard fm.fileExists(atPath: absRoot) else { continue }
            walk(absRoot, depth: 0, cutoff: cutoff, fm: fm, onItem: onItem)
        }
    }

    private static func walk(
        _ dir: String, depth: Int, cutoff: Date,
        fm: FileManager, onItem: @escaping (ScanItem) -> Void
    ) {
        guard depth < 6 else { return }
        guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { return }

        for name in entries {
            if name.hasPrefix(".") && !name.hasPrefix(".next") && name != ".venv" { continue }
            let path = (dir as NSString).appendingPathComponent(name)

            if let art = artifacts.first(where: { $0.0 == name }) {
                emit(path: path, artifact: art, cutoff: cutoff, fm: fm, onItem: onItem)
                continue
            }

            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { continue }
            if shouldSkip(name) { continue }
            walk(path, depth: depth + 1, cutoff: cutoff, fm: fm, onItem: onItem)
        }
    }

    private static func emit(
        path: String, artifact: (String, String), cutoff: Date,
        fm: FileManager, onItem: @escaping (ScanItem) -> Void
    ) {
        let bytes = Shell.size(path)
        guard bytes > 10_485_760 else { return } // 10 MB minimum

        let mod = (try? fm.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? Date.distantPast
        let stale = mod < cutoff
        let parent = (path as NSString).deletingLastPathComponent
        let project = (parent as NSString).lastPathComponent

        let note = stale
            ? "\(artifact.1) Not modified in \(staleDays)+ days."
            : artifact.1

        onItem(ScanItem(
            id: "project:\(path)",
            name: "\(artifact.0) · \(project)",
            path: path,
            category: "Developer",
            safety: stale ? .safe : .check,
            note: note,
            command: nil,
            sizeBytes: bytes,
            known: true
        ))
    }

    private static func shouldSkip(_ name: String) -> Bool {
        let skip = ["Library", "Applications", ".git", ".svn", "node_modules", "Pods",
                    "DerivedData", "build", "target", "dist", ".next"]
        return skip.contains(name)
    }
}
