import CryptoKit
import DocPipeline
import Foundation

/// The resume pipeline's artifact store, specialized to `ArtifactKind`. Keeping the name
/// `ArtifactStore` lets every call site read unchanged; the generic mechanism lives in
/// DocPipeline.
typealias ArtifactStore = DocPipeline.ArtifactStore<ArtifactKind>

// MARK: - ArtifactKind

enum ArtifactKind: String, CaseIterable, Sendable, ArtifactKey {
    case inputs
    case parsed
    case normalized
    case repaired
    case validation
    case rirekisho
    case shokumukeirekisho

    var filename: String { "\(rawValue).json" }

    // "derived" means regeneratable — edits don't stick
    var role: String {
        switch self {
        case .repaired, .validation: return "derived"
        default: return "source"
        }
    }

    // Legacy single-file cache names (one upgrade window). Read by DocPipeline's store.
    var legacyCacheFilename: String? {
        switch self {
        case .normalized:        return ".normalized_cache.json"
        case .rirekisho:         return ".rirekisho_cache.json"
        case .shokumukeirekisho: return ".shokumukeirekisho_cache.json"
        default:                 return nil
        }
    }
}

// MARK: - InputsData

enum ResumeSourceKind: String, Codable, Sendable {
    case markdown
    case docx
    case pdf
    case text

    static func from(url: URL) -> ResumeSourceKind {
        switch url.pathExtension.lowercased() {
        case "md", "markdown":
            return .markdown
        case "docx":
            return .docx
        case "pdf":
            return .pdf
        default:
            return .text
        }
    }
}

struct InputsData: Codable, Sendable {
    let sourcePath: String
    let markdownHash: String
    let config: JapanConfig
    let sourceKind: ResumeSourceKind?
    let sourceText: String?
    let cleanedText: String?
    let preprocessingNotes: [String]
    /// Free-form additional context supplied by the candidate via `--notes`.
    /// Read by every LLM stage as `additional_context` in the user payload.
    let userNotes: String?

    enum CodingKeys: String, CodingKey {
        case config
        case sourcePath = "source_path"
        case markdownHash = "markdown_hash"
        case sourceKind = "source_kind"
        case sourceText = "source_text"
        case cleanedText = "cleaned_text"
        case preprocessingNotes = "preprocessing_notes"
        case userNotes = "user_notes"
    }

    init(
        sourcePath: String,
        markdownHash: String,
        config: JapanConfig,
        sourceKind: ResumeSourceKind? = nil,
        sourceText: String? = nil,
        cleanedText: String? = nil,
        preprocessingNotes: [String] = [],
        userNotes: String? = nil
    ) {
        self.sourcePath = sourcePath
        self.markdownHash = markdownHash
        self.config = config
        self.sourceKind = sourceKind
        self.sourceText = sourceText
        self.cleanedText = cleanedText
        self.preprocessingNotes = preprocessingNotes
        self.userNotes = userNotes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourcePath = try container.decode(String.self, forKey: .sourcePath)
        markdownHash = try container.decode(String.self, forKey: .markdownHash)
        config = try container.decode(JapanConfig.self, forKey: .config)
        sourceKind = try container.decodeIfPresent(ResumeSourceKind.self, forKey: .sourceKind)
        sourceText = try container.decodeIfPresent(String.self, forKey: .sourceText)
        cleanedText = try container.decodeIfPresent(String.self, forKey: .cleanedText)
        preprocessingNotes = try container.decodeIfPresent([String].self, forKey: .preprocessingNotes) ?? []
        userNotes = try container.decodeIfPresent(String.self, forKey: .userNotes)
    }
}

// MARK: - ArtifactHashes

enum ArtifactHashes {
    /// Hash of source markdown + config (+ optional user notes) — same computation as
    /// `AICache.contentHash`. Notes fold in so changing `--notes` invalidates every
    /// downstream artifact, including cached normalize/generate output.
    static func inputs(markdownContent: String, configData: Data?, notes: String? = nil) -> String {
        AICache.contentHash(markdownContent: markdownContent, configData: configData, notes: notes)
    }

    /// Rirekisho hash includes era style and optional target context.
    static func rirekisho(inputsHash: String, era: EraStyle,
                          targetContext: TargetCompanyContext? = nil) -> String {
        let enc = JSONCoders.sorted
        let ctxStr = targetContext.flatMap { try? enc.encode($0) }
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""
        return sha256("\(inputsHash)\(era.rawValue)\(ctxStr)")
    }

    /// Shokumukeirekisho hash includes generation options and optional target context.
    static func shokumukeirekisho(inputsHash: String, era: EraStyle, options: GenerationOptions,
                                  targetContext: TargetCompanyContext? = nil) -> String {
        let enc = JSONCoders.sorted
        let optStr = (try? enc.encode(options)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let ctxStr = targetContext.flatMap { try? enc.encode($0) }
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""
        return sha256("\(inputsHash)\(era.rawValue)\(optStr)\(ctxStr)")
    }

    private static func sha256(_ string: String) -> String {
        var hasher = SHA256()
        hasher.update(data: Data(string.utf8))
        return hasher.finalize().compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - ProducedBy

/// Produces the `produced_by` string using the grammar `<actor>/<version> [<slug>:<model>]`.
/// Provider slug is the provider raw value (e.g. "anthropic", "ollama").
enum ProducedBy {
    static let actor = "jpresume"
    static let version = "0.5.0"

    static func jpresume() -> String { "\(actor)/\(version)" }

    static func jpresume(providerSlug: String, modelOverride: String?) -> String {
        let resolved = ProviderFactory.resolveModel(provider: providerSlug, model: modelOverride)
        if resolved.isEmpty {
            return "\(actor)/\(version) \(providerSlug)"
        }
        return "\(actor)/\(version) \(providerSlug):\(resolved)"
    }

    static func external(model: String) -> String { "claude-code/external \(model)" }
}
