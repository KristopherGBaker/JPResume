import Foundation

// MARK: - ArtifactStatus

public enum ArtifactStatus: Equatable, Sendable {
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

/// Typed read/write over a workspace directory, generic over a document pipeline's
/// `ArtifactKey`. Writes are atomic; status is a four-state machine
/// (`fresh` / `stale` / `missing` / `invalid`). Carries no knowledge of any specific
/// document type — the `Key` supplies filenames, roles, and legacy cache names.
public struct ArtifactStore<Key: ArtifactKey>: Sendable {
    public static var schemaVersion: String { "3.0.0" }
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    // MARK: Write

    public func write<T: Codable>(
        _ value: T,
        kind: Key,
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
        let data = try JSONCoders.prettySorted.encode(artifact)

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

    public func read<T: Codable>(_ kind: Key, as _: T.Type = T.self) throws -> Artifact<T> {
        let url = root.appendingPathComponent(kind.filename)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ArtifactStoreError.missing(kind.filename)
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Artifact<T>.self, from: data)
    }

    // MARK: Metadata

    /// Decode the metadata-only header from an artifact file, if present and parseable.
    /// Errors (missing file, bad JSON) collapse to `nil` — callers handle that as
    /// "treat as missing/invalid" via `status(_:)`.
    private func loadMetadata(_ kind: Key) -> ArtifactMetadata? {
        let url = root.appendingPathComponent(kind.filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ArtifactMetadata.self, from: data)
    }

    // MARK: Status

    public func status(_ kind: Key, expectedContentHash: String? = nil) -> ArtifactStatus {
        let url = root.appendingPathComponent(kind.filename)
        if !FileManager.default.fileExists(atPath: url.path) {
            if let legacy = legacyURL(for: kind),
               FileManager.default.fileExists(atPath: legacy.path) {
                return .stale(reason: "legacy cache format — run stage to upgrade")
            }
            return .missing
        }
        guard let meta = loadMetadata(kind) else {
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

    public func producedBy(_ kind: Key) -> String? {
        loadMetadata(kind)?.producedBy
    }

    public func producedAt(_ kind: Key) -> Date? {
        loadMetadata(kind).flatMap { ISO8601DateFormatter().date(from: $0.producedAt) }
    }

    // MARK: Legacy cache fallback

    public func loadLegacy<T: Codable>(_ kind: Key, as _: T.Type = T.self, expectedHash: String) -> T? {
        guard let url = legacyURL(for: kind) else { return nil }
        return AICache.load(from: url, expectedHash: expectedHash)
    }

    private func legacyURL(for kind: Key) -> URL? {
        guard let name = kind.legacyCacheFilename else { return nil }
        return root.deletingLastPathComponent().appendingPathComponent(name)
    }
}

// MARK: - List (requires enumerable keys)

public extension ArtifactStore where Key: CaseIterable {
    func list(expectedContentHash: String? = nil) -> [ArtifactSummary<Key>] {
        Key.allCases.map { kind in
            let s = status(kind, expectedContentHash: expectedContentHash)
            var producedAt: String?
            var producedBy: String?
            var warnCount = 0, errCount = 0, infoCount = 0

            if case .fresh = s, let meta = loadMetadata(kind) {
                producedAt = meta.producedAt
                producedBy = meta.producedBy
                for w in meta.warnings {
                    switch w.severity {
                    case .info:    infoCount += 1
                    case .warning: warnCount += 1
                    case .error:   errCount += 1
                    }
                }
            }

            return ArtifactSummary(kind: kind, status: s, producedAt: producedAt,
                                   producedBy: producedBy, warningCount: warnCount,
                                   errorCount: errCount, infoCount: infoCount)
        }
    }
}

// MARK: - ArtifactStoreError

public enum ArtifactStoreError: Error, CustomStringConvertible {
    case missing(String)        // filename
    case invalid(String, String) // filename, reason

    public var description: String {
        switch self {
        case .missing(let name):
            return "Artifact '\(name)' not found in workspace. Run the appropriate stage first."
        case .invalid(let name, let reason):
            return "Artifact '\(name)' is invalid: \(reason)"
        }
    }
}
