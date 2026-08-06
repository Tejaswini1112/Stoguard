import Foundation

/// Assertion-based self-check runnable without XCTest (Command Line Tools can't
/// build the SwiftPM test target). Run with:  ./build/Stoguard.app/Contents/MacOS/Stoguard --selftest
/// Exits 0 if all checks pass, 1 otherwise.
enum SelfTest {
    static func run() -> Never {
        var failures: [String] = []
        func check(_ cond: Bool, _ msg: String) { if !cond { failures.append(msg) } }

        // Byte formatting
        check(ByteText.string(0) == "0 B", "ByteText 0")
        check(ByteText.string(1024) == "1.0 KB", "ByteText 1KB")
        check(ByteText.string(1536) == "1.5 KB", "ByteText 1.5KB")
        check(ByteText.string(1_073_741_824) == "1.0 GB", "ByteText 1GB")

        // Overlap detection (dedup between known rules and discovery)
        check(Scanner.overlaps("/a/b", with: ["/a"]), "overlap child")
        check(Scanner.overlaps("/a", with: ["/a/b"]), "overlap parent")
        check(!Scanner.overlaps("/ab", with: ["/a"]), "overlap false-prefix")
        check(!Scanner.overlaps("/x", with: ["/a"]), "overlap unrelated")

        // Safety decoding
        let json = #"[{"id":"x","name":"X","path":"~/x","category":"C","safety":"command","note":"n","command":"do"}]"#
        if let rules = try? JSONDecoder().decode([Rule].self, from: Data(json.utf8)) {
            check(rules.first?.safety == .command, "decode .command")
            check(rules.first?.command == "do", "decode command string")
        } else {
            failures.append("decode failed")
        }

        // Rules database consistency
        let rules = Scanner.loadRules()
        check(!rules.isEmpty, "rules load")
        for r in rules where r.safety == .command {
            check(r.command != nil, "command rule missing command: \(r.id)")
        }
        check(Set(rules.map(\.id)).count == rules.count, "duplicate rule ids")

        // Path safety — home file OK, system path rejected
        let homeFile = (NSHomeDirectory() as NSString).appendingPathComponent(".vacs-selftest-probe")
        FileManager.default.createFile(atPath: homeFile, contents: Data("x".utf8))
        defer { try? FileManager.default.removeItem(atPath: homeFile) }
        check(PathSafety.validateForTrash(homeFile).isSuccess, "path safety home ok")
        check(PathSafety.validateForTrash("/System/Library").isFailure, "path safety system blocked")

        // Adaptive profile skip threshold
        var profile = AdaptiveProfile()
        for _ in 0..<AdaptiveProfile.autoSkipAfterMisses {
            profile.recordMiss(ruleID: "never-installed-tool")
        }
        check(!profile.shouldScan(ruleID: "never-installed-tool"), "adaptive skip after misses")
        profile.recordHit(ruleID: "never-installed-tool")
        check(profile.shouldScan(ruleID: "never-installed-tool"), "adaptive reset on hit")

        // Doctor / chat grounding
        let sample = ScanItem(
            id: "npm-cache", name: "npm cache", path: "/tmp/npm",
            category: "Package Managers", safety: .safe,
            note: "npm download cache.", command: nil,
            sizeBytes: 500_000_000, known: true,
            lastActivity: Date().addingTimeInterval(-90 * 86_400)
        )
        let report = DoctorEngine.build(
            items: [sample],
            history: [],
            freeBytes: 50_000_000_000,
            totalBytes: 500_000_000_000,
            skippedRules: 0,
            cacheHits: 0
        )
        check(!report.summaryLines.isEmpty, "doctor summary")
        check(report.reclaimableSafe == 500_000_000, "doctor safe bytes")
        check(!report.recommendations.isEmpty, "doctor recommendations")

        let chat = WorkstationChat.whyIsSSDFull(context: .init(
            items: [sample], report: report, pulse: nil,
            duplicates: [], models: [], env: []
        ))
        check(chat.contains("npm") || chat.contains("hotspot") || chat.contains("GB") || chat.contains("Problem"), "ssd full narrative")

        let glossary = TermGlossary.explain(item: sample)
        check(glossary.lowercased().contains("npm") || glossary.lowercased().contains("trash"), "glossary before delete")

        // Plugin loader scaffold
        PluginLoader.ensureScaffold()
        check(FileManager.default.fileExists(atPath: PluginLoader.pluginsDirectory.path), "plugins dir")

        // Duplicate finder returns array (may be empty on clean machines)
        _ = DuplicateFinder.scan()
        _ = LocalModelManager.inventory()

        if failures.isEmpty {
            print("Stoguard self-test: OK (\(rules.count) rules loaded)")
            exit(0)
        } else {
            print("Stoguard self-test: FAILED")
            failures.forEach { print("  - \($0)") }
            exit(1)
        }
    }
}

private extension Result {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
    var isFailure: Bool { !isSuccess }
}
