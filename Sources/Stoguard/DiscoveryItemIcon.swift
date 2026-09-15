import AppKit
import SwiftUI

/// Icons for Installed Packages and AI & Skills discovery rows.
enum DiscoveryItemIcon {
    enum Glyph: Equatable {
        case app(NSImage)
        case symbol(String, Color)
    }

    private nonisolated(unsafe) static let fm = FileManager.default

    private static let packageAppHints: [String: [String]] = [
        "playwright": ["Microsoft Edge.app", "Google Chrome.app"],
        "patchright": ["Google Chrome.app", "Chromium.app"],
        "puppeteer": ["Google Chrome.app", "Chromium.app"],
        "wrangler": ["Cloudflare WARP.app"],
        "docker": ["Docker.app"],
        "claude": ["Claude.app"],
        "anthropic": ["Claude.app"],
        "cursor": ["Cursor.app"],
        "codebase-memory": ["Cursor.app"],
        "ollama": ["Ollama.app"],
        "huggingface": ["Hugging Face.app"],
        "transformers": ["Python.app", "Python 3.app"],
        "torch": ["Python.app", "Python 3.app"],
        "scipy": ["Python.app", "Python 3.app"],
        "litellm": ["Python.app", "Python 3.app"],
    ]

    static func package(_ pkg: InstalledPackage) -> Glyph {
        if let hinted = appIcon(matching: pkg.name) { return .app(hinted) }
        if pkg.path.hasSuffix(".app"), fm.fileExists(atPath: pkg.path) {
            return .app(NSWorkspace.shared.icon(forFile: pkg.path))
        }

        switch pkg.source.lowercased() {
        case "homebrew":
            return appIcon(named: ["Homebrew.app"]).map { .app($0) }
                ?? .symbol("mug.fill", Color(red: 0.85, green: 0.35, blue: 0.12))
        case "homebrew cask":
            return fileIcon(at: pkg.path) ?? .symbol("app.fill", Theme.navy)
        case "npm global":
            return appIcon(named: ["Node.app"]).map { .app($0) }
                ?? .symbol("curlybraces", Color(red: 0.20, green: 0.65, blue: 0.32))
        case "pip":
            return appIcon(named: ["Python.app", "Python 3.app"]).map { .app($0) }
                ?? .symbol("chevron.left.forwardslash.chevron.right", Color(red: 0.22, green: 0.45, blue: 0.72))
        case "path":
            if let file = fileIcon(at: pkg.path) { return file }
            return .symbol("terminal.fill", Theme.navy)
        default:
            return .symbol("shippingbox.fill", Theme.navy)
        }
    }

    static func aiSkill(_ entry: AISkillEntry) -> Glyph {
        switch entry.kind {
        case .skill:
            // Skills — never a generic folder; use brain/sparkles skill metaphor.
            if entry.path.contains("/.cursor/") {
                return appIcon(named: ["Cursor.app"]).map { .app($0) }
                    ?? .symbol("brain.head.profile", Theme.navy)
            }
            if entry.path.contains("/.codex/") {
                return .symbol("sparkles", Color(red: 0.12, green: 0.55, blue: 0.45))
            }
            return .symbol("brain.head.profile", Theme.navy)
        case .mcp:
            return .symbol("point.3.connected.trianglepath.dotted", Color(red: 0.45, green: 0.28, blue: 0.72))
        case .extensionData:
            if entry.path.lowercased().contains("cursor") {
                return appIcon(named: ["Cursor.app"]).map { .app($0) }
                    ?? .symbol("puzzlepiece.extension.fill", Theme.navy)
            }
            return .symbol("puzzlepiece.extension.fill", Theme.secondaryText)
        }
    }

    /// Finder reveal — not the card identity icon.
    static let revealSymbol = "arrow.up.forward.app"

    private static func appIcon(matching name: String) -> NSImage? {
        let key = name.lowercased()
        for (hint, apps) in packageAppHints {
            if key.contains(hint) { return appIcon(named: apps) }
        }
        return nil
    }

    private static func appIcon(named apps: [String]) -> NSImage? {
        for app in apps {
            for base in ["/Applications", "\(NSHomeDirectory())/Applications"] {
                let path = (base as NSString).appendingPathComponent(app)
                if fm.fileExists(atPath: path) {
                    return NSWorkspace.shared.icon(forFile: path)
                }
            }
        }
        return nil
    }

    private static func fileIcon(at path: String) -> Glyph? {
        guard fm.fileExists(atPath: path) else { return nil }
        return .app(NSWorkspace.shared.icon(forFile: path))
    }
}

struct DiscoveryIconView: View {
    let glyph: DiscoveryItemIcon.Glyph
    var size: CGFloat = 28

    var body: some View {
        Group {
            switch glyph {
            case .app(let image):
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            case .symbol(let name, let tint):
                Image(systemName: name)
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: size, height: size)
        .background(
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(Theme.elevated.opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .strokeBorder(Theme.hairline.opacity(0.55), lineWidth: 0.5)
        )
    }
}
