import Foundation

/// Finds AI agent skills, MCP configs, and editor extensions that may be stale.
struct AgentToolFinding: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let kind: String // mcp, skill, extension
    let path: String
    let sizeBytes: Int64
    let detail: String
    var lastActivity: Date? = nil
    var staleDays: Int? = nil

    var sizeText: String { ByteText.string(sizeBytes) }
    var isStale: Bool { (staleDays ?? 0) >= 60 }
}

enum AgentToolsScanner {
    static func scan() -> [AgentToolFinding] {
        var out: [AgentToolFinding] = []
        out += mcpConfigs()
        out += skillFolders()
        out += editorExtensions()
        out.sort {
            let as_ = $0.isStale ? 1 : 0
            let bs = $1.isStale ? 1 : 0
            if as_ != bs { return as_ > bs }
            return $0.sizeBytes > $1.sizeBytes
        }
        return out
    }

    // MARK: - MCP

    private static func mcpConfigs() -> [AgentToolFinding] {
        let home = NSHomeDirectory()
        let candidates = [
            "\(home)/.vscode/mcp.json",
            "\(home)/Library/Application Support/Code/User/globalStorage/saoudrizwan.claude-dev/settings/cline_mcp_settings.json",
            "\(home)/Library/Application Support/Claude/claude_desktop_config.json",
            "\(home)/.config/claude/mcp.json",
            "\(home)/.mcp.json",
        ]
        var out: [AgentToolFinding] = []
        let fm = FileManager.default
        for path in candidates where fm.fileExists(atPath: path) {
            let size = Shell.size(path)
            let act = PathActivity.lastActivity(at: path)
            let days = act.map { max(0, Int(Date().timeIntervalSince($0) / 86_400)) }
            let servers = mcpServerNames(at: path)
            out.append(AgentToolFinding(
                id: "mcp-\(path.hashValue)",
                name: servers.isEmpty ? (path as NSString).lastPathComponent : servers.joined(separator: ", "),
                kind: "MCP",
                path: path,
                sizeBytes: max(size, 1),
                detail: servers.isEmpty
                    ? "MCP config file. Review servers you no longer use."
                    : "MCP servers: \(servers.joined(separator: ", ")). Disable unused ones to reduce agent clutter.",
                lastActivity: act,
                staleDays: days
            ))
        }
        return out
    }

    private static func mcpServerNames(at path: String) -> [String] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }
        if let servers = obj["mcpServers"] as? [String: Any] {
            return servers.keys.sorted()
        }
        if let servers = obj["servers"] as? [String: Any] {
            return servers.keys.sorted()
        }
        return []
    }

    // MARK: - Skills

    private static func skillFolders() -> [AgentToolFinding] {
        let home = NSHomeDirectory()
        let roots = [
            "\(home)/.codex/skills",
            "\(home)/.claude/skills",
            "\(home)/.agents/skills",
        ]
        var out: [AgentToolFinding] = []
        let fm = FileManager.default
        for root in roots {
            guard let entries = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for name in entries where !name.hasPrefix(".") {
                let path = (root as NSString).appendingPathComponent(name)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: path, isDirectory: &isDir) else { continue }
                let size = isDir.boolValue ? Shell.size(path) : ((try? fm.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value ?? 0)
                let act = PathActivity.lastActivity(at: path)
                let days = act.map { max(0, Int(Date().timeIntervalSince($0) / 86_400)) }
                let stale = (days ?? 0) >= 60
                out.append(AgentToolFinding(
                    id: "skill-\(path.hashValue)",
                    name: name,
                    kind: "Skill",
                    path: path,
                    sizeBytes: size,
                    detail: stale
                        ? "Skill/agent pack looks idle (\(days ?? 0)d). Confirm before deleting — outdated skills can confuse agents."
                        : "AI skill / agent pack. Keep if you still invoke it.",
                    lastActivity: act,
                    staleDays: days
                ))
            }
        }
        // Also flag SKILL.md files under common project dirs? Keep scoped to user skill roots.
        return out
    }

    // MARK: - Extensions

    private static func editorExtensions() -> [AgentToolFinding] {
        let home = NSHomeDirectory()
        let roots = [
            ("VS Code", "\(home)/.vscode/extensions"),
            ("VS Code Insiders", "\(home)/.vscode-insiders/extensions"),
        ]
        var out: [AgentToolFinding] = []
        let fm = FileManager.default
        for (editor, root) in roots {
            guard let names = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for name in names where !name.hasPrefix(".") {
                let path = (root as NSString).appendingPathComponent(name)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { continue }
                let size = Shell.size(path)
                guard size > 2_000_000 else { continue }
                let act = PathActivity.lastActivity(at: path)
                let days = act.map { max(0, Int(Date().timeIntervalSince($0) / 86_400)) }
                let display = friendlyExtensionName(folder: name, path: path)
                out.append(AgentToolFinding(
                    id: "ext-\(editor)-\(name)",
                    name: display,
                    kind: "\(editor) extension",
                    path: path,
                    sizeBytes: size,
                    detail: (days ?? 0) >= 90
                        ? "Extension idle ~\(days ?? 0) days. Consider uninstalling from \(editor) if unused."
                        : "Installed \(editor) extension (\(ByteText.string(size))).",
                    lastActivity: act,
                    staleDays: days
                ))
            }
        }
        // Keep top offenders only to avoid huge lists
        return Array(out.sorted { $0.sizeBytes > $1.sizeBytes }.prefix(40))
    }

    private static func friendlyExtensionName(folder: String, path: String) -> String {
        let pkg = (path as NSString).appendingPathComponent("package.json")
        if let data = try? Data(contentsOf: URL(fileURLWithPath: pkg)),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let display = obj["displayName"] as? String, !display.isEmpty { return display }
            if let name = obj["name"] as? String, !name.isEmpty { return name }
        }
        return folder
    }
}
