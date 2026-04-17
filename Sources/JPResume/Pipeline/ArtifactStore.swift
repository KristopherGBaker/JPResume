import Foundation

// MARK: - ArtifactStatus

enum ArtifactStatus: Equatable, Sendable {
    case fresh
    case stale(reason: String)   // exists, parses, but hash doesn't match
    case missing                 // file doesn't exist
    case invalid(reason: String) // exists but unreadable / version mismatch
}

// MARK: - ArtifactMetadata (metadata-only decode — avoids generic T)

private struct ArtifactMetadata: Codable {
    let kind: String
    let schemaVersion: String
    let contentHash: String
    let inputsHash: String
    let producedAt: String
    let producedBy: String
    let mode: String
    let warnings: [ArtifactWarning]

    enum CodingKeys: String, CodingKey {
        case kind, warnings, mode
        case schemaVersion = "schema_version"
        case contentHash = "content_hash"
        case inputsHash = "inputs_hash"
        case producedAt = "produced_at"
        case producedBy = "produced_by"
    }
}

// MARK: - ArtifactStore

struct ArtifactStore: Sendable {
    static let schemaVersion = "3.0.0"
    let root: URL

    // MARK: Write

    func write<T: Codable>(
        _ value: T,
        kind: ArtifactKind,
        contentHash: String,
        inputsHash: String,
        producedBy: String,
        mode: String = "internal",
        warnings: [ArtifactWarning] = []
    ) throws {
        let artifact = Artifact(
            kind: kind.rawValue,
            role: kind.role,
            schemaVersion: Self.schemaVersion,
            contentHash: contentHash,
            inputsHash: inputsHash,
            producedAt: ISO8601DateFormatter().string(from: Date()),
            producedBy: producedBy,
            mode: mode,
            warnings: warnings,
            data: value
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(artifact)

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let dest = root.appendingPathComponent(kind.filename)
        let tmp = root.appendingPathComponent(".\(kind.rawValue).json.tmp")
        try data.write(to: tmp)
        if FileManager.default.fileExists(atPath: dest.path) {
            _ = try FileManager.default.replaceItem(at: dest, withItemAt: tmp, backupItemName: nil, options: [], resultingItemURL: nil)
        } else {
            try FileManager.default.moveItem(at: tmp, to: dest)
        }
    }

    // MARK: Read

    func read<T: Codable>(_ kind: ArtifactKind, as _: T.Type = T.self) throws -> Artifact<T> {
        let url = root.appendingPathComponent(kind.filename)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ArtifactStoreError.missing(kind)
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Artifact<T>.self, from: data)
    }

    // MARK: Status

    func status(_ kind: ArtifactKind, expectedContentHash: String? = nil) -> ArtifactStatus {
        let url = root.appendingPathComponent(kind.filename)
        if !FileManager.default.fileExists(atPath: url.path) {
            if let legacy = legacyURL(for: kind),
               FileManager.default.fileExists(atPath: legacy.path) {
                return .stale(reason: "legacy cache format — run stage to upgrade")
            }
            return .missing
        }
        guard let data = try? Data(contentsOf: url),
              let meta = try? JSONDecoder().decode(ArtifactMetadata.self, from: data) else {
            return .invalid(reason: "cannot parse artifact file")
        }
        guard meta.schemaVersion == Self.schemaVersion else {
            return .invalid(reason: "schema version mismatch (have \(meta.schemaVersion), need \(Self.schemaVersion))")
        }
        if let expected = expectedContentHash, meta.contentHash != expected {
            let short = { (h: String) in String(h.prefix(8)) }
            return .stale(reason: "hash changed (\(short(meta.contentHash))… → \(short(expected))…)")
        }
        return .fresh
    }

    // MARK: Produced-by for cache-hit log

    func producedBy(_ kind: ArtifactKind) -> String? {
        let url = root.appendingPathComponent(kind.filename)
        guard let data = try? Data(contentsOf: url),
              let meta = try? JSONDecoder().decode(ArtifactMetadata.self, from: data) else {
            return nil
        }
        return meta.producedBy
    }

    func producedAt(_ kind: ArtifactKind) -> Date? {
        let url = root.appendingPathComponent(kind.filename)
        guard let data = try? Data(contentsOf: url),
              let meta = try? JSONDecoder().decode(ArtifactMetadata.self, from: data) else {
            return nil
        }
        return ISO8601DateFormatter().date(from: meta.producedAt)
    }

    // MARK: List

    func list(expectedContentHash: String? = nil) -> [ArtifactSummary] {
        ArtifactKind.allCases.map { kind in
            let s = status(kind, expectedContentHash: expectedContentHash)
            var producedAt: String?
            var producedBy: String?
            var warnCount = 0, errCount = 0, infoCount = 0

            if case .fresh = s {
                let url = root.appendingPathComponent(kind.filename)
                if let data = try? Data(contentsOf: url),
                   let meta = try? JSONDecoder().decode(ArtifactMetadata.self, from: data) {
                    producedAt = meta.producedAt
                    producedBy = meta.producedBy
                    for w in meta.warnings {
                        switch w.severity {
                        case "info":    infoCount += 1
                        case "warning": warnCount += 1
                        case "error":   errCount += 1
                        default: break
                        }
                    }
                }
            }

            return ArtifactSummary(kind: kind, status: s, producedAt: producedAt,
                                   producedBy: producedBy, warningCount: warnCount,
                                   errorCount: errCount, infoCount: infoCount)
        }
    }

    // MARK: Legacy cache fallback

    func loadLegacy<T: Codable>(_ kind: ArtifactKind, as _: T.Type = T.self, expectedHash: String) -> T? {
        guard let url = legacyURL(for: kind) else { return nil }
        return AICache.load(from: url, expectedHash: expectedHash)
    }

    private func legacyURL(for kind: ArtifactKind) -> URL? {
        let parent = root.deletingLastPathComponent()
        switch kind {
        case .normalized:     return parent.appendingPathComponent(".normalized_cache.json")
        case .rirekisho:      return parent.appendingPathComponent(".rirekisho_cache.json")
        case .shokumukeirekisho: return parent.appendingPathComponent(".shokumukeirekisho_cache.json")
        default: return nil
        }
    }
}

// MARK: - ArtifactStoreError

enum ArtifactStoreError: Error, CustomStringConvertible {
    case missing(ArtifactKind)
    case invalid(ArtifactKind, String)

    var description: String {
        switch self {
        case .missing(let kind):
            return "Artifact '\(kind.filename)' not found in workspace. Run the appropriate stage first."
        case .invalid(let kind, let reason):
            return "Artifact '\(kind.filename)' is invalid: \(reason)"
        }
    }
}
