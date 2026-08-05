import AppKit
import SwiftUI

/// Maps scan rows to real app icons (Purge-style) — rule id → .app bundle, then path heuristics.
enum ScanItemIcon {
    enum Source: Equatable {
        case app(String)
        case file(String)
        case symbol(String)
    }

    private nonisolated(unsafe) static let fm = FileManager.default

    /// Rule id → app bundle names to try under /Applications.
    private static let appsByRule: [String: [String]] = [
        "xcode-deriveddata": ["Xcode.app"],
        "xcode-archives": ["Xcode.app"],
        "xcode-iphonesupport": ["Xcode.app"],
        "xcode-watchsupport": ["Xcode.app"],
        "xcode-devicelogs": ["Xcode.app"],
        "coresim-caches": ["Xcode.app"],
        "coresim-devices": ["Xcode.app"],
        "swift-pm-cache": ["Xcode.app"],
        "carthage-cache": ["Xcode.app"],
        "cocoapods-cache": ["Xcode.app"],
        "jetbrains-caches": ["IntelliJ IDEA.app", "WebStorm.app", "PyCharm.app", "JetBrains Toolbox.app"],
        "jetbrains-logs": ["IntelliJ IDEA.app", "JetBrains Toolbox.app"],
        "android-emulator": ["Android Studio.app"],
        "flutter-pub": ["Android Studio.app"],
        "unity-cache": ["Unity Hub.app", "Unity.app"],
        "godot-cache": ["Godot.app"],
        "vscode-data": ["Visual Studio Code.app"],
        "vscode-support": ["Visual Studio Code.app"],
        "vscode-insiders": ["Visual Studio Code - Insiders.app"],
        "vscode-caches": ["Visual Studio Code.app"],
        "windsurf-data": ["Windsurf.app"],
        "npm-cache": ["Node.app"],
        "yarn-cache": ["Node.app"],
        "pnpm-store": ["Node.app"],
        "bun-cache": ["Bun.app"],
        "deno-cache": ["Deno.app"],
        "homebrew-cache": ["Homebrew.app"],
        "pip-cache": ["Python.app", "Python 3.app"],
        "uv-cache": ["Python.app", "Python 3.app"],
        "conda-pkgs": ["Miniconda3.app", "Anaconda.app"],
        "poetry-cache": ["Python.app"],
        "cargo-cache": ["RustDesk.app"],
        "gradle-caches": ["Android Studio.app"],
        "maven-repo": ["IntelliJ IDEA.app"],
        "nvm-cache": ["Node.app"],
        "pyenv-versions": ["Python.app"],
        "puppeteer": ["Google Chrome.app", "Chromium.app"],
        "playwright": ["Google Chrome.app", "Microsoft Edge.app"],
        "selenium": ["Google Chrome.app", "Firefox.app"],
        "electron-cache": ["Electron.app"],
        "docker-desktop": ["Docker.app"],
        "minikube": ["Docker.app", "Lens.app"],
        "colima": ["Docker.app"],
        "rancher-desktop": ["Rancher Desktop.app"],
        "huggingface": ["Hugging Face.app"],
        "ollama-models": ["Ollama.app"],
        "claude-desktop": ["Claude.app"],
        "chatgpt-desktop": ["ChatGPT.app"],
        "gemini-antigravity": ["Antigravity.app"],
        "gemini-antigravity-backup": ["Antigravity.app"],
        "lmstudio": ["LM Studio.app"],
        "chrome-cache": ["Google Chrome.app"],
        "firefox-cache": ["Firefox.app"],
        "brave-cache": ["Brave Browser.app"],
        "google-chrome-support": ["Google Chrome.app"],
        "mail-attachments": ["Mail.app"],
        "ios-backups": ["Finder.app"],
        "trash": ["Trash.app", "Finder.app"],
        "user-caches": ["Finder.app"],
        "user-logs": ["Console.app"],
        "zoom-cache": ["zoom.us.app", "Zoom.us.app", "Zoom.app"],
        "zoom-logs": ["zoom.us.app", "Zoom.us.app", "Zoom.app"],
        "discord-cache": ["Discord.app"],
        "discord-gpu": ["Discord.app"],
        "discord-code-cache": ["Discord.app"],
        "slack-cache": ["Slack.app"],
        "teams-cache": ["Microsoft Teams.app"],
        "teams2-cache": ["Microsoft Teams.app"],
        "spotify-cache": ["Spotify.app"],
        "perplexity-cache": ["Perplexity.app"],
        "perplexity-cache-alt": ["Perplexity.app"],
        "notion-cache": ["Notion.app"],
        "figma-cache": ["Figma.app"],
        "telegram-cache": ["Telegram.app"],
        "whatsapp-cache": ["WhatsApp.app"],
        "steam-cache": ["Steam.app"],
        "epic-cache": ["Epic Games Launcher.app"],
        "arc-cache": ["Arc.app"],
        "1password-cache": ["1Password.app"],
        "dropbox-cache": ["Dropbox.app"],
        "google-drive-cache": ["Google Drive.app"],
        "location-analytics": ["Maps.app"],
        "apple-mediaanalysis": ["Photos.app"],
    ]

    private static let categorySymbols: [String: String] = [
        "Developer": "chevron.left.forwardslash.chevron.right",
        "Package Managers": "archivebox.fill",
        "Browser Automation": "globe.americas.fill",
        "Containers & K8s": "shippingbox.fill",
        "AI Tools": "sparkles",
        "Apps": "bubble.left.and.bubble.right.fill",
        "System": "externaldrive.fill",
        "Unknown heavy folders": "folder.badge.questionmark",
    ]

    static func resolve(_ item: ScanItem) -> Source {
        let ruleID = ruleID(from: item.id)

        if let ruleID, let apps = appsByRule[ruleID], let app = findApp(named: apps) {
            return .app(app)
        }

        if let app = appFromPath(item.path) {
            return .app(app)
        }

        if item.id.hasPrefix("project:") {
            if let node = findApp(named: ["Node.app"]) { return .app(node) }
            return .symbol("chevron.left.forwardslash.chevron.right")
        }

        if fm.fileExists(atPath: item.path) {
            let img = NSWorkspace.shared.icon(forFile: item.path)
            if img.size.width > 0 { return .file(item.path) }
        }

        if let sym = categorySymbols[item.category] {
            return .symbol(sym)
        }
        return .symbol("doc.fill")
    }

    static func image(for item: ScanItem) -> NSImage {
        switch resolve(item) {
        case .app(let path), .file(let path):
            return NSWorkspace.shared.icon(forFile: path)
        case .symbol:
            return NSImage(systemSymbolName: "doc.fill", accessibilityDescription: nil)
                ?? NSWorkspace.shared.icon(forFile: item.path)
        }
    }

    // MARK: - Internals

    private static func ruleID(from itemID: String) -> String? {
        if itemID.hasPrefix("unknown:") || itemID.hasPrefix("project:") { return nil }
        return itemID
    }

    private static func findApp(named names: [String]) -> String? {
        for base in ["/Applications", NSHomeDirectory() + "/Applications"] {
            for name in names {
                let path = (base as NSString).appendingPathComponent(name)
                if fm.fileExists(atPath: path) { return path }
            }
        }
        return nil
    }

    /// Bundle id embedded in Library paths → installed .app
    private static func appFromPath(_ path: String) -> String? {
        let patterns: [(String, [String])] = [
            ("com.docker.docker", ["Docker.app"]),
            ("com.microsoft.VSCode", ["Visual Studio Code.app"]),
            ("com.google.Chrome", ["Google Chrome.app"]),
            ("com.openai.chat", ["ChatGPT.app"]),
            ("com.anthropic", ["Claude.app"]),
            ("com.apple.mail", ["Mail.app"]),
            ("com.hnc.Discord", ["Discord.app"]),
            ("us.zoom", ["zoom.us.app", "Zoom.us.app"]),
            ("com.spotify", ["Spotify.app"]),
            ("com.perplexity", ["Perplexity.app"]),
        ]
        for (needle, apps) in patterns {
            if path.contains(needle), let app = findApp(named: apps) { return app }
        }
        return nil
    }
}

struct ScanItemIconView: View {
    let item: ScanItem
    var size: CGFloat = 24

    var body: some View {
        switch ScanItemIcon.resolve(item) {
        case .app(let path), .file(let path):
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: size * 0.58, weight: .medium))
                .foregroundStyle(Theme.navy)
                .frame(width: size, height: size)
                .background(Theme.navy.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }
}
