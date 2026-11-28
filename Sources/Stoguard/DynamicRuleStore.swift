import Foundation

/// Dynamic Rule Generator and Backup Cache Store.
/// Synthesizes rules automatically for all installed applications on macOS,
/// making Stoguard self-updating as new apps are installed without editing rules.json.
enum DynamicRuleStore {
    private nonisolated(unsafe) static let fm = FileManager.default

    private static var storageURL: URL {
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Stoguard", isDirectory: true)
        try? fm.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport.appendingPathComponent("dynamic_rules.json")
    }

    /// Merges hand-crafted static rules with auto-discovered rules for all installed apps.
    static func loadCombinedRules(staticRules: [Rule]) -> [Rule] {
        var existingPaths = Set(staticRules.map { PathUtil.expand($0.path) })
        var combined = staticRules

        let dynamicRules = generateAppRules(existingPaths: &existingPaths)
        combined.append(contentsOf: dynamicRules)

        save(rules: dynamicRules)
        return combined
    }

    /// Auto-discovers related library/cache/container folders for all installed non-system applications.
    static func generateAppRules(existingPaths: inout Set<String>) -> [Rule] {
        let apps = AppScanner.listApps()
        var rules: [Rule] = []

        for app in apps {
            guard !app.isSystemApp else { continue }
            let bid = app.bundleID ?? ""
            if AppScanner.isProtected(bid) { continue }

            let groups = AppScanner.relatedFiles(appPath: app.appPath, bundleID: bid, appName: app.name)
            for group in groups {
                for entry in group.entries {
                    guard entry.kind != .application else { continue }
                    let path = entry.path
                    guard existingPaths.insert(path).inserted else { continue }

                    let cat: String = {
                        switch group.kind {
                        case .caches, .webKit, .savedState: return "Caches"
                        case .logs: return "Logs"
                        case .containers:
                            let lower = bid.lowercased()
                            let isEngine = lower.contains("orbstack") || lower.contains("docker") || lower.contains("colima") || lower.contains("minikube") || lower.contains("rancher")
                            return isEngine ? "Containers & K8s" : "Apps"
                        default: return "Apps"
                        }
                    }()

                    let safety: Safety = {
                        switch group.kind {
                        case .caches, .logs, .savedState, .webKit: return .safe
                        default: return .check
                        }
                    }()

                    let note = "Auto-discovered \(group.kind.rawValue) folder for \(app.name)."

                    rules.append(Rule(
                        id: "dynamic:\(path)",
                        name: "\(app.name) · \(entry.name)",
                        path: path,
                        category: cat,
                        safety: safety,
                        note: note
                    ))
                }
            }
        }
        return rules
    }

    private static func save(rules: [Rule]) {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        try? data.write(to: storageURL)
    }

    static func loadCachedRules() -> [Rule] {
        guard let data = try? Data(contentsOf: storageURL),
              let rules = try? JSONDecoder().decode([Rule].self, from: data)
        else { return [] }
        return rules
    }
}
