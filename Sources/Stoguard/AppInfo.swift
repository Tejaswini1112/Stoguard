import Foundation

enum ComparisonStrength: String {
    case strong = "Excellent"
    case partial = "Partial"
    case none = "—"

    var color: String {
        switch self {
        case .strong: return "green"
        case .partial: return "orange"
        case .none: return "gray"
        }
    }
}

struct ToolComparisonRow: Identifiable {
    let id: String
    let icon: String
    let title: String
    let detail: String
    let vacs: ComparisonStrength
    let purge: ComparisonStrength
    let macOS: ComparisonStrength
    let cleanMyMac: ComparisonStrength
}

enum AppInfo {
    static let name = "Stoguard"
    static let tagline = "Find what’s eating your developer machine — AI models, packages, and caches — with plain-English definitions and one-tap safe cleanup."
    static let author = "Stoguard"
    static let copyrightYear = "2026"
    static let licenseName = "Proprietary · All Rights Reserved"
    /// Public repo URL when published. Nil until Stoguard has its own org/repo.
    static let repoURL: URL? = nil

    static let licenseNotice = """
    Copyright © \(copyrightYear) \(author). All rights reserved.

    Stoguard is proprietary software. You may not copy, modify, distribute, sell, or create derivative works from this app or its source without prior written permission.
    """

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    static var versionLabel: String { "\(version) (\(build))" }

    static var bugReportURL: URL? {
        guard let repoURL else { return nil }
        var c = URLComponents(url: repoURL.appendingPathComponent("issues/new"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "labels", value: "bug")]
        return c.url
    }

    static var featureRequestURL: URL? {
        guard let repoURL else { return nil }
        var c = URLComponents(url: repoURL.appendingPathComponent("issues/new"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "labels", value: "enhancement")]
        return c.url
    }

    static var releasesURL: URL? {
        repoURL?.appendingPathComponent("releases")
    }

    /// Bundled rules file inside the app — not a third-party GitHub link.
    static var allowlistURL: URL? {
        Bundle.main.url(forResource: "rules", withExtension: "json")
    }

    static let toolComparisons: [ToolComparisonRow] = [
        ToolComparisonRow(
            id: "puppeteer",
            icon: "globe.americas.fill",
            title: "Puppeteer & Playwright",
            detail: "Chromium under ~/.cache/puppeteer and ~/Library/Caches/ms-playwright.",
            vacs: .strong, purge: .partial, macOS: .none, cleanMyMac: .none
        ),
        ToolComparisonRow(
            id: "docker",
            icon: "shippingbox.fill",
            title: "Docker VM disk (real size)",
            detail: "Reads actual APFS allocation — not the virtual disk size.",
            vacs: .strong, purge: .partial, macOS: .partial, cleanMyMac: .partial
        ),
        ToolComparisonRow(
            id: "minikube",
            icon: "cube.transparent.fill",
            title: "Minikube & Colima",
            detail: "Known paths with safe CLI commands — not risky folder deletes.",
            vacs: .strong, purge: .none, macOS: .none, cleanMyMac: .none
        ),
        ToolComparisonRow(
            id: "packages",
            icon: "archivebox.fill",
            title: "npm · pip · Homebrew · Cargo",
            detail: "90+ known cache paths with plain-English notes.",
            vacs: .strong, purge: .partial, macOS: .none, cleanMyMac: .partial
        ),
        ToolComparisonRow(
            id: "xcode",
            icon: "chevron.left.forwardslash.chevron.right",
            title: "Xcode DerivedData & simulators",
            detail: "Per-project breakdown and simctl guidance.",
            vacs: .strong, purge: .partial, macOS: .partial, cleanMyMac: .partial
        ),
        ToolComparisonRow(
            id: "ai",
            icon: "sparkles",
            title: "AI Cleanup (models · skills · MCP)",
            detail: "One place for local LLM stores, agent skills, MCP servers, and AI caches.",
            vacs: .strong, purge: .none, macOS: .none, cleanMyMac: .none
        ),
        ToolComparisonRow(
            id: "pkgfinder",
            icon: "shippingbox.and.arrow.backward.fill",
            title: "Package Finder with definitions",
            detail: "Homebrew, npm, pipx, and CLI installs — each with what it is and disk size.",
            vacs: .strong, purge: .none, macOS: .none, cleanMyMac: .none
        ),
        ToolComparisonRow(
            id: "heavy",
            icon: "folder.badge.questionmark",
            title: "Unknown folders over 1 GB",
            detail: "Sweep of ~/.cache and ~/Library for unlisted heavy folders.",
            vacs: .strong, purge: .none, macOS: .none, cleanMyMac: .partial
        ),
        ToolComparisonRow(
            id: "consumer",
            icon: "bubble.left.and.bubble.right.fill",
            title: "Zoom · Discord · consumer apps",
            detail: "Dedicated Apps category — Zoom, Discord, Slack, Perplexity, Spotify, and more.",
            vacs: .strong, purge: .strong, macOS: .partial, cleanMyMac: .strong
        ),
        ToolComparisonRow(
            id: "explain",
            icon: "text.book.closed.fill",
            title: "Plain-English explanations",
            detail: "Every row says what the folder is and what happens if removed.",
            vacs: .strong, purge: .strong, macOS: .partial, cleanMyMac: .partial
        ),
        ToolComparisonRow(
            id: "trash",
            icon: "trash",
            title: "Trash-only deletion",
            detail: "Recoverable until you empty Trash — nothing silently erased.",
            vacs: .strong, purge: .strong, macOS: .strong, cleanMyMac: .partial
        ),
        ToolComparisonRow(
            id: "rules",
            icon: "lock.shield.fill",
            title: "Open auditable rules.json",
            detail: "Every scanned path is human-readable in one auditable file.",
            vacs: .strong, purge: .partial, macOS: .none, cleanMyMac: .none
        ),
    ]

    static let cleanCategories: [(icon: String, title: String, detail: String)] = [
        ("chevron.left.forwardslash.chevron.right", "Developer caches",
         "Xcode DerivedData, simulator runtimes, IDE caches, and build artifacts."),
        ("archivebox.fill", "Package manager stores",
         "npm, Homebrew, pip, Cargo, Gradle, and other caches that rebuild on the next install."),
        ("globe.americas.fill", "Browser automation",
         "Puppeteer, Playwright, and Selenium browser downloads."),
        ("shippingbox.fill", "Containers & Kubernetes",
         "Docker, Minikube, and Colima — with the correct CLI command, not risky folder deletes."),
        ("sparkles", "AI Cleanup",
         "Models, skills, MCP, and AI app caches — one place for immediate safe reclaim."),
        ("shippingbox.and.arrow.backward.fill", "Package Finder",
         "Installed brew/npm/pipx/CLI packages with a definition and how much space each uses."),
        ("bubble.left.and.bubble.right.fill", "Everyday apps",
         "Zoom, Discord, Slack, Perplexity, Spotify — temp files with plain-English notes."),
        ("externaldrive.fill", "System caches & logs",
         "Shared app caches and logs under ~/Library — explained before you remove anything."),
        ("folder.badge.questionmark", "Unknown heavy folders",
         "Large folders over 1 GB not in the allowlist yet — review before removing."),
    ]

    static func sizeAnalogy(for bytes: Int64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        switch gb {
        case 50...: return "About the size of a full Docker Desktop VM"
        case 20..<50: return "About the size of a fresh Xcode install"
        case 10..<20: return "About the size of 2 hours of 4K video"
        case 5..<10: return "About the size of a AAA game demo"
        case 1..<5: return "About the size of a long 1080p movie"
        case 0.1..<1: return "About the size of a photo library backup"
        default: return "Every megabyte counts"
        }
    }
}
