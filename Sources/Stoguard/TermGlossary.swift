import Foundation

/// Plain-English glossary for every cleanup term — shown before Trash / in Doctor.
enum TermGlossary {
    static func explain(item: ScanItem) -> String {
        explain(id: item.id, name: item.name, category: item.category, note: item.note)
    }

    static func explain(id: String, name: String, category: String, note: String) -> String {
        let key = id.lowercased()
        let n = name.lowercased()
        let specific = lookup(id: key, name: n) ?? categoryHint(category)
        return """
        \(note)

        \(specific)

        Safety tip: Stoguard only moves items to Trash (or copies a CLI). Nothing is permanently erased until you empty Trash.
        """
    }

    static func shortLabel(for item: ScanItem) -> String {
        lookup(id: item.id.lowercased(), name: item.name.lowercased())?
            .split(separator: "\n").first.map(String.init)
            ?? item.note
    }

    private static func lookup(id: String, name: String) -> String? {
        if id.contains("deriveddata") || name.contains("deriveddata") {
            return "Term: DerivedData — Xcode’s scratch pad for compiling, indexing, and previews. Deleting it does not delete your source code; the next build is just slower once while Xcode regenerates indexes."
        }
        if id.contains("docker") || name.contains("docker") {
            return "Term: Docker VM disk — a virtual hard drive holding images, containers, and volumes. Never drag this folder to Trash; use Docker’s prune command so metadata stays consistent."
        }
        if id.contains("ollama") {
            return "Term: Ollama models — full neural-network weight files for local chat/completion. Removing a model frees many GB; you can re-download later with `ollama pull`."
        }
        if id.contains("huggingface") || name.contains("hugging") {
            return "Term: Hugging Face cache — downloaded model weights and datasets used by ML libraries. Safe to remove unused models; active projects will re-fetch what they need."
        }
        if id.contains("lmstudio") || name.contains("lm studio") {
            return "Term: LM Studio models — GGUF/local weights managed by LM Studio. Removing frees disk; reopen LM Studio to download again."
        }
        if id.contains("npm") || name.contains("npm cache") {
            return "Term: npm cache — tarballs of packages you’ve installed. Clearing is safe; the next `npm install` re-downloads."
        }
        if id.contains("node_modules") || name.contains("node_modules") {
            return "Term: node_modules — installed JavaScript dependencies for one project. Not shared globally; recreate with npm/yarn/pnpm install inside that project."
        }
        if id.contains("nvm") {
            return "Term: nvm — Node Version Manager. Each folder is a full Node.js runtime. Extra versions are common duplicates."
        }
        if id.contains("pyenv") {
            return "Term: pyenv — installs multiple Python interpreters side by side. Old versions often duplicate standard libraries."
        }
        if id.contains("simulator") || name.contains("simulator") {
            return "Term: Simulator — virtual iPhone/iPad used for testing. Device data can grow large; unavailable runtimes are safe to prune via simctl."
        }
        if id.contains("gradle") {
            return "Term: Gradle cache — Android/JVM dependency and build cache. Rebuilds automatically on the next build."
        }
        if id.contains("cargo") {
            return "Term: Cargo registry — downloaded Rust crates. Safe to clear; next `cargo build` re-fetches."
        }
        if id.contains("homebrew") || name.contains("homebrew") {
            return "Term: Homebrew cache — downloaded bottle archives. Equivalent to `brew cleanup`."
        }
        if id.contains("playwright") || id.contains("puppeteer") {
            return "Term: Browser automation downloads — full Chromium/Firefox builds used by test tools. Re-installed on next test run."
        }
        if id.contains("git") || name.contains(".git") {
            return "Term: Git object database — every commit, blob, and packfile for a repo. Large `.git` folders usually mean big binaries or long history — not your working tree files."
        }
        if categoryHintNeeded(id) {
            return nil
        }
        return nil
    }

    private static func categoryHintNeeded(_ id: String) -> Bool { true }

    private static func categoryHint(_ category: String) -> String {
        switch category {
        case "Developer":
            return "Category: Developer tools — build products and IDE caches. Usually regenerable; keep Archives if you still ship those builds."
        case "Package Managers":
            return "Category: Package caches — shared downloads for language ecosystems. Clearing forces re-download, not loss of your projects."
        case "Containers & K8s":
            return "Category: Containers — virtual machines and cluster state. Prefer official CLI prune/delete commands."
        case "AI Tools":
            return "Category: AI tools — model weights and IDE AI indexes. Large and often unused for months."
        case "Browser Automation":
            return "Category: Test browsers — full browser binaries for automation frameworks."
        case "Apps":
            return "Category: Consumer app caches — temp media and updater files. Apps recreate them."
        case "System":
            return "Category: Shared system/user caches and logs under your Library."
        case "Unknown heavy folders":
            return "Category: Unknown — Stoguard doesn’t recognize this path. Open in Finder and identify it before deleting."
        default:
            return "This is a measured folder on your Mac. Read the note above, then decide Trash vs keep."
        }
    }
}
