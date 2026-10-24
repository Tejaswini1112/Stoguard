import Foundation

/// Scans Cursor/Codex skill folders and MCP configs for stale or broken entries.
enum AISkillsScanner {
    private nonisolated(unsafe) static let fm = FileManager.default
    private static let staleDays = 180

    static let skillRoots: [(String, String)] = [
        ("~/.cursor/skills", "Cursor skills"),
        ("~/.cursor/skills-cursor", "Cursor built-in skills"),
        ("~/.codex/skills", "Codex skills"),
        ("~/.agents/skills", "Agent skills"),
        ("~/.claude/skills", "Claude skills"),
    ]

    static let mcpConfigPaths: [String] = [
        "~/.cursor/mcp.json",
        "~/.codex/mcp.json",
    ]

    static func scan() -> [AISkillEntry] {
        var results: [AISkillEntry] = []
        results += scanSkillDirectories()
        results += scanMCPConfigs()
        results += scanExtensionDirs()
        return results.sorted { lhs, rhs in
            if lhs.needsAttention != rhs.needsAttention { return lhs.needsAttention }
            return lhs.sizeBytes > rhs.sizeBytes
        }
    }

    // MARK: - Skills

    private static func scanSkillDirectories() -> [AISkillEntry] {
        let cutoff = Date().addingTimeInterval(-Double(staleDays) * 86400)
        var results: [AISkillEntry] = []

        for (rootPattern, _) in skillRoots {
            let root = PathUtil.expand(rootPattern)
            guard fm.fileExists(atPath: root),
                  let names = try? fm.contentsOfDirectory(atPath: root) else { continue }

            var addedForRoot = 0
            for name in names where !name.hasPrefix(".") {
                let path = (root as NSString).appendingPathComponent(name)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { continue }

                let skillFile = (path as NSString).appendingPathComponent("SKILL.md")
                let hasSkill = fm.fileExists(atPath: skillFile)
                let mod = (try? fm.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? Date.distantPast
                let bytes = Shell.size(path)

                let issue: String? = {
                    if !hasSkill { return "Missing SKILL.md — may be outdated or incomplete" }
                    if mod < cutoff { return "Not modified in \(staleDays)+ days — review if still needed" }
                    return nil
                }()

                results.append(AISkillEntry(
                    id: "skill:\(path)",
                    name: name,
                    path: path,
                    kind: .skill,
                    issue: issue,
                    sizeBytes: bytes,
                    modifiedAt: mod
                ))
                addedForRoot += 1
            }

            if addedForRoot == 0 {
                let bytes = Shell.size(root)
                if bytes > 0 {
                    results.append(AISkillEntry(
                        id: "skill-root:\(root)",
                        name: (root as NSString).lastPathComponent,
                        path: root,
                        kind: .skill,
                        issue: nil,
                        sizeBytes: bytes,
                        modifiedAt: modificationDate(at: root)
                    ))
                }
            }
        }

        return results
    }

    // MARK: - MCP

    private static func scanMCPConfigs() -> [AISkillEntry] {
        var results: [AISkillEntry] = []

        for pattern in mcpConfigPaths {
            let path = PathUtil.expand(pattern)
            guard fm.fileExists(atPath: path) else { continue }

            let bytes = Shell.size(path)
            var issue: String? = nil

            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let servers = (json["mcpServers"] as? [String: Any])
                    ?? (json["servers"] as? [String: Any])
                    ?? [:]
                var broken: [String] = []
                for (name, value) in servers {
                    guard let dict = value as? [String: Any] else { continue }
                    if let cmd = dict["command"] as? String, !cmd.isEmpty {
                        let expanded = (cmd as NSString).expandingTildeInPath
                        if expanded.hasPrefix("/"), !fm.fileExists(atPath: expanded) {
                            broken.append(name)
                        }
                    }
                    if let args = dict["args"] as? [String] {
                        for arg in args where arg.hasPrefix("/") {
                            if !fm.fileExists(atPath: arg) { broken.append(name); break }
                        }
                    }
                }
                if !broken.isEmpty {
                    issue = "Broken path for: \(broken.prefix(3).joined(separator: ", "))"
                }
                let mod = (try? fm.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? Date.distantPast
                if issue == nil, mod < Date().addingTimeInterval(-Double(staleDays) * 86400) {
                    issue = "Config not updated in \(staleDays)+ days"
                }
            } else {
                issue = "Could not parse MCP config JSON"
            }

            results.append(AISkillEntry(
                id: "mcp:\(path)",
                name: (path as NSString).lastPathComponent,
                path: path,
                kind: .mcp,
                issue: issue,
                sizeBytes: bytes,
                modifiedAt: (try? fm.attributesOfItem(atPath: path)[.modificationDate] as? Date)
            ))
        }

        return results
    }

    // MARK: - Extension data

    private static func scanExtensionDirs() -> [AISkillEntry] {
        let dirs = [
            ("~/Library/Application Support/Cursor", "Cursor app data"),
            ("~/.cursor/extensions", "Cursor extensions"),
        ]
        var results: [AISkillEntry] = []

        for (pattern, label) in dirs {
            let path = PathUtil.expand(pattern)
            guard fm.fileExists(atPath: path) else { continue }
            let bytes = Shell.size(path)
            guard bytes > 50_000_000 else { continue } // 50 MB — skip tiny dirs
            results.append(AISkillEntry(
                id: "ext:\(path)",
                name: label,
                path: path,
                kind: .extensionData,
                issue: bytes > 2_000_000_000
                    ? "Large (\(ByteText.string(bytes))) — may include stale caches or indexes"
                    : nil,
                sizeBytes: bytes,
                modifiedAt: modificationDate(at: path)
            ))
        }
        return results
    }

    private static func modificationDate(at path: String) -> Date? {
        try? fm.attributesOfItem(atPath: path)[.modificationDate] as? Date
    }
}
