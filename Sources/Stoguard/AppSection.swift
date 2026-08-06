import SwiftUI

/// Sidebar destinations — PureMac-style categories, Purge-style calm labels.
enum AppSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case health = "Health"
    case doctor = "Workstation Doctor"
    case ask = "Ask Stoguard"
    case learning = "Learning Center"
    case automation = "Automation"
    case pulse = "System Pulse"
    case envDoctor = "Env Doctor"
    case buildTrends = "Build Trends"
    case aiCleanup = "AI Cleanup"
    case aiModels = "AI Models"
    case duplicates = "Duplicates"
    case packageFinder = "Package Finder"
    case agentTools = "AI Skills & MCP"
    case gitRepos = "Git Repos"
    case codebase = "Codebase"
    case mediaOptimizer = "Media Optimizer"
    case rulesPlugins = "Rules & Plugins"
    case fleet = "Fleet Export"
    case installedApps = "Installed Apps"
    case developer = "Developer"
    case packageManagers = "Package Managers"
    case browserAutomation = "Browser Automation"
    case containers = "Containers & K8s"
    case aiTools = "AI Tools"
    case apps = "Apps"
    case system = "System"
    case heavyFolders = "Heavy folders"
    case trash = "Trash"
    case about = "About"

    var id: String { rawValue }

    /// Maps to the `category` field in rules.json (or discovery bucket).
    var ruleCategory: String? {
        switch self {
        case .overview, .health, .doctor, .ask, .learning, .automation, .pulse, .envDoctor, .buildTrends,
             .aiCleanup, .aiModels, .duplicates, .packageFinder, .agentTools, .gitRepos, .codebase, .mediaOptimizer,
             .rulesPlugins, .fleet, .installedApps, .about, .trash:
            return nil
        case .heavyFolders: return "Unknown heavy folders"
        default: return rawValue
        }
    }

    var icon: String {
        switch self {
        case .overview: return "chart.pie.fill"
        case .health: return "heart.circle.fill"
        case .doctor: return "stethoscope"
        case .ask: return "text.bubble.fill"
        case .learning: return "book.fill"
        case .automation: return "clock.arrow.2.circlepath"
        case .pulse: return "heart.text.square.fill"
        case .envDoctor: return "wrench.and.screwdriver.fill"
        case .buildTrends: return "chart.line.uptrend.xyaxis"
        case .aiCleanup: return "sparkles"
        case .aiModels: return "cpu.fill"
        case .duplicates: return "square.on.square"
        case .packageFinder: return "shippingbox.and.arrow.backward.fill"
        case .agentTools: return "puzzlepiece.fill"
        case .gitRepos: return "arrow.triangle.branch"
        case .codebase: return "folder.badge.gearshape"
        case .mediaOptimizer: return "photo.on.rectangle.angled"
        case .rulesPlugins: return "puzzlepiece.extension.fill"
        case .fleet: return "person.3.fill"
        case .installedApps: return "app.badge.fill"
        case .developer: return "chevron.left.forwardslash.chevron.right"
        case .packageManagers: return "archivebox.fill"
        case .browserAutomation: return "globe.americas.fill"
        case .containers: return "shippingbox.fill"
        case .aiTools: return "sparkles"
        case .apps: return "bubble.left.and.bubble.right.fill"
        case .system: return "externaldrive.fill"
        case .heavyFolders: return "folder.badge.questionmark"
        case .trash: return "trash.fill"
        case .about: return "info.circle"
        }
    }

    var blurb: String {
        switch self {
        case .overview: return "Disk usage and reclaimable space at a glance."
        case .health: return "Scores, GB/day forecasts, background watches, and history."
        case .doctor: return "Plain-English diagnosis — what grew, what's unused, and what's safe to fix."
        case .ask: return "Conversational AI grounded in your scan — ask why Docker is huge, what DerivedData is, etc."
        case .learning: return "Teachable glossary — what terms mean, when to delete, what happens after."
        case .automation: return "Scheduled scans and safe tidy rules — plus opt-in cohort benchmarks."
        case .pulse: return "CPU, memory, and disk pressure — why the machine feels slow."
        case .envDoctor: return "Brew, Node, Python, Java, Android, Flutter, Rust, asdf/mise health."
        case .buildTrends: return "DerivedData / Gradle cache size over time."
        case .aiCleanup: return "Models, skills, MCP, and AI caches — one place for immediate AI cleanup."
        case .aiModels: return "Local AI workspace — sizes, last used, RAM/GPU, quants, archive."
        case .duplicates: return "Fingerprint-confirmed duplicates — related installs show differences, not false dupes."
        case .packageFinder: return "Each installed package with a plain-English definition and disk space used."
        case .agentTools: return "MCP servers, AI skills, and idle editor extensions."
        case .gitRepos: return "Large .git folders, stashes, and branch sprawl."
        case .codebase: return "Repository Doctor — secrets, dead deps, binaries, build artifacts."
        case .mediaOptimizer: return "Find large images, videos, and documents — optimize with your approval."
        case .rulesPlugins: return "Plugin SDK packs — detection, risk, safe actions, docs links."
        case .fleet: return "Enterprise fleet — ingest, compliance, AI inventory, multi-OS."
        case .installedApps: return "See every file an app dropped on your Mac — caches, containers, preferences."
        case .developer: return "Xcode, simulators, IDE caches, and build artifacts."
        case .packageManagers: return "npm, Homebrew, pip, Cargo, Gradle, and other package caches."
        case .browserAutomation: return "Puppeteer, Playwright, and Selenium browser downloads."
        case .containers: return "Docker, Minikube, Colima — with the correct CLI commands."
        case .aiTools: return "LLM weights, Hugging Face, and AI IDE working data."
        case .apps: return "Zoom, Discord, Slack, and everyday app temp files."
        case .system: return "Shared app caches, logs, and browser data."
        case .heavyFolders: return "Large folders Stoguard doesn't recognize yet — review before removing."
        case .trash: return "Your Mac Trash — browse, restore, or permanently empty."
        case .about: return "Version, stats, and how Stoguard works."
        }
    }

    static var scannable: [AppSection] {
        [.developer, .packageManagers, .browserAutomation, .containers, .aiTools, .apps, .system, .heavyFolders]
    }

    static var insightTools: [AppSection] {
        [.health, .doctor, .ask, .learning, .automation, .pulse, .envDoctor, .buildTrends]
    }

    static var optimizeTools: [AppSection] {
        // AI Models + Skills/MCP roll up into AI Cleanup for immediate cleanup.
        // Package Finder is the install inventory (brew/npm) — keep it prominent.
        [.aiCleanup, .packageFinder, .mediaOptimizer, .duplicates, .gitRepos, .codebase]
    }

    static var platformTools: [AppSection] {
        [.rulesPlugins, .fleet]
    }

    static var advancedTools: [AppSection] {
        // Package Managers lives under Optimize → Packages (installs + caches).
        [.developer, .browserAutomation, .containers, .aiTools]
    }

    static var generalCleanup: [AppSection] {
        [.apps, .system, .heavyFolders]
    }

    var pureMacAdvancedToolLabel: String? {
        switch self {
        case .aiTools: return "AI Apps"
        case .developer: return "Xcode Junk"
        case .packageManagers: return "Brew / Node / pip caches"
        case .containers: return "Docker Cache"
        case .browserAutomation: return "Browser automation"
        default: return nil
        }
    }

    static func section(forCategory category: String) -> AppSection? {
        if category == "Unknown heavy folders" { return .heavyFolders }
        return scannable.first { $0.ruleCategory == category }
    }

    var sidebarLabel: String {
        switch self {
        case .health: return "Health"
        case .doctor: return "Doctor"
        case .ask: return "Ask"
        case .learning: return "Learn"
        case .automation: return "Automate"
        case .pulse: return "Pulse"
        case .envDoctor: return "Env"
        case .buildTrends: return "Builds"
        case .aiCleanup: return "AI Cleanup"
        case .aiModels: return "Models"
        case .duplicates: return "Dupes"
        case .packageFinder: return "Packages"
        case .agentTools: return "Skills/MCP"
        case .gitRepos: return "Git"
        case .codebase: return "Repo"
        case .mediaOptimizer: return "Media"
        case .rulesPlugins: return "Rules"
        case .fleet: return "Enterprise"
        case .packageManagers: return "Packages"
        case .browserAutomation: return "Browsers"
        case .containers: return "Containers"
        case .apps: return "Apps"
        case .heavyFolders: return "Heavy"
        default: return rawValue
        }
    }
}

enum SafetyFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case safe = "Safe to clean"
    case check = "Check first"

    var id: String { rawValue }

    func matches(_ safety: Safety) -> Bool {
        switch self {
        case .all: return true
        case .safe: return safety == .safe
        case .check: return safety == .check || safety == .command
        }
    }
}

enum SortOrder: String, CaseIterable, Identifiable {
    case largest = "Largest"
    case name = "Name"

    var id: String { rawValue }
}
