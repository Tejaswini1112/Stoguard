import Foundation

/// Phase-1 mentor briefing: Problem → Cause → Explanation → Risk → Recommendation → Fix → Learn More.
struct MentorBriefing: Identifiable, Hashable, Sendable {
    let id: UUID
    let problem: String
    let cause: String
    let explanation: String
    let risk: String
    let recommendation: String
    let fix: MentorFix?
    let learnMore: MentorLearnMore?

    init(
        id: UUID = UUID(),
        problem: String,
        cause: String,
        explanation: String,
        risk: String,
        recommendation: String,
        fix: MentorFix? = nil,
        learnMore: MentorLearnMore? = nil
    ) {
        self.id = id
        self.problem = problem
        self.cause = cause
        self.explanation = explanation
        self.risk = risk
        self.recommendation = recommendation
        self.fix = fix
        self.learnMore = learnMore
    }

    var plainText: String {
        var lines = [
            "Problem: \(problem)",
            "",
            "Cause: \(cause)",
            "",
            "Explanation: \(explanation)",
            "",
            "Risk: \(risk)",
            "",
            "Recommendation: \(recommendation)",
        ]
        if let fix { lines += ["", "One-click fix: \(fix.label)"] }
        if let learnMore { lines += ["Learn more: \(learnMore.label)"] }
        return lines.joined(separator: "\n")
    }
}

struct MentorFix: Hashable, Sendable {
    enum Kind: String, Sendable {
        case openSection
        case trashSafeItem
        case trashSafeCategory
        case copyCommand
        case scan
        case openLearning
        case openHealth
    }

    let label: String
    let kind: Kind
    let section: AppSection?
    let itemID: String?
    let command: String?
    let articleID: String?

    init(
        label: String,
        kind: Kind,
        section: AppSection? = nil,
        itemID: String? = nil,
        command: String? = nil,
        articleID: String? = nil
    ) {
        self.label = label
        self.kind = kind
        self.section = section
        self.itemID = itemID
        self.command = command
        self.articleID = articleID
    }
}

struct MentorLearnMore: Hashable, Sendable {
    let label: String
    let articleID: String?
    let prompt: String?

    init(label: String, articleID: String? = nil, prompt: String? = nil) {
        self.label = label
        self.articleID = articleID
        self.prompt = prompt
    }
}

/// Knowledge-graph style card for a workstation object (Phase 2).
struct KnowledgeCard: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let storageBytes: Int64?
    let createdBy: String
    let purpose: String
    let canDelete: String
    let afterEffect: String
    let risk: String
    let typicalSize: String
    let yourSizeText: String?
    let learnArticleID: String?

    var plainBlock: String {
        """
        \(title)
        Storage: \(yourSizeText ?? "—")
        Created by: \(createdBy)
        Purpose: \(purpose)
        Can I delete?: \(canDelete)
        After effect: \(afterEffect)
        Risk: \(risk)
        Typical size: \(typicalSize)
        """
    }
}

enum KnowledgeGraph {
    static func card(forTerm term: String, context: WorkstationChat.Context) -> KnowledgeCard? {
        let t = term.lowercased()
        if t.contains("derived") || t.contains("xcode") {
            let item = context.items.first {
                $0.name.localizedCaseInsensitiveContains("DerivedData")
                    || $0.id.localizedCaseInsensitiveContains("derived")
            }
            return KnowledgeCard(
                id: "deriveddata",
                title: "DerivedData",
                storageBytes: item?.sizeBytes,
                createdBy: "Xcode",
                purpose: "Compiled intermediates, indexes, and module caches",
                canDelete: "YES — source code is never only here",
                afterEffect: "Next build is slower once (cold compile), then speeds up again",
                risk: "Low",
                typicalSize: "5–20 GB",
                yourSizeText: item.map { ByteText.string($0.sizeBytes) },
                learnArticleID: "deriveddata"
            )
        }
        if t.contains("docker") {
            let bytes = context.items.filter {
                $0.category.localizedCaseInsensitiveContains("Container")
                    || $0.name.localizedCaseInsensitiveContains("Docker")
            }.reduce(Int64(0)) { $0 + $1.sizeBytes }
            return KnowledgeCard(
                id: "docker",
                title: "Docker disk / images",
                storageBytes: bytes > 0 ? bytes : nil,
                createdBy: "Docker Desktop / engine",
                purpose: "Images, layers, build cache, and volumes for containers",
                canDelete: "Unused images/cache: YES via prune. Named volumes: review first",
                afterEffect: "Next pull/build re-downloads layers; projects/Dockerfiles stay",
                risk: "Low for prune · Medium for volumes",
                typicalSize: "10–40 GB",
                yourSizeText: bytes > 0 ? ByteText.string(bytes) : nil,
                learnArticleID: "docker"
            )
        }
        if t.contains("ollama") || t.contains("model") {
            let bytes = context.models.reduce(Int64(0)) { $0 + $1.sizeBytes }
            return KnowledgeCard(
                id: "ollama",
                title: "Local AI models",
                storageBytes: bytes > 0 ? bytes : nil,
                createdBy: "Ollama / HF / LM Studio / etc.",
                purpose: "Offline LLM and diffusion weights",
                canDelete: "YES for idle models — re-pull to restore",
                afterEffect: "That model won’t run until downloaded again",
                risk: "Low",
                typicalSize: "4–12 GB per model",
                yourSizeText: bytes > 0 ? ByteText.string(bytes) : nil,
                learnArticleID: "ollama"
            )
        }
        if t.contains("npm") {
            let item = context.items.first { $0.name.localizedCaseInsensitiveContains("npm") }
            return KnowledgeCard(
                id: "npm-cache",
                title: "npm cache",
                storageBytes: item?.sizeBytes,
                createdBy: "npm",
                purpose: "Downloaded package tarballs for faster installs",
                canDelete: "YES",
                afterEffect: "Next installs refill the cache (slower until then)",
                risk: "Low",
                typicalSize: "1–5 GB",
                yourSizeText: item.map { ByteText.string($0.sizeBytes) },
                learnArticleID: "npm-cache"
            )
        }
        return nil
    }
}
