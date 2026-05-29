import Foundation

// MARK: - ArtifactKey

/// A document pipeline describes its artifacts by conforming an enum to `ArtifactKey`.
/// The store, status machine, and external bridge are all generic over this protocol, so
/// they carry no knowledge of any specific document type. Conform a `String`-backed,
/// `CaseIterable` enum (so `ArtifactStore.list()` can enumerate it).
public protocol ArtifactKey: Sendable {
    /// Stable identifier — also the on-disk `kind` field.
    var rawValue: String { get }
    /// File this artifact is written to inside the workspace.
    var filename: String { get }
    /// `"source"` (survives hand-edits) or `"derived"` (regenerated each run).
    var role: String { get }
    /// Optional legacy single-file cache name, relative to the workspace parent, read for
    /// one upgrade cycle. Default `nil`.
    var legacyCacheFilename: String? { get }
}

public extension ArtifactKey {
    var legacyCacheFilename: String? { nil }
}

// MARK: - ArtifactWarning

/// A non-fatal note attached to an artifact (e.g. a surviving constraint violation or a
/// validation warning). Persisted in the artifact envelope and surfaced by `inspect`.
public struct ArtifactWarning: Codable, Sendable {
    public let severity: Severity
    public let field: String?
    public let message: String

    public init(severity: Severity, field: String?, message: String) {
        self.severity = severity
        self.field = field
        self.message = message
    }
}

// MARK: - Artifact<T>

/// Typed envelope written to disk for every pipeline stage. Carries provenance
/// (`producedBy`, `producedAt`, `mode`), cache keys (`contentHash`, `inputsHash`),
/// the schema version, structured `warnings`, and the stage payload `data`.
public struct Artifact<T: Codable>: Codable {
    public let kind: String
    public let role: String          // "source" | "derived"
    public let schemaVersion: String
    public let contentHash: String
    public let inputsHash: String
    public let producedAt: String    // ISO-8601
    public let producedBy: String
    public let mode: String          // "internal" | "external"
    public let warnings: [ArtifactWarning]
    public let data: T

    public init(
        kind: String,
        role: String,
        schemaVersion: String,
        contentHash: String,
        inputsHash: String,
        producedAt: String,
        producedBy: String,
        mode: String,
        warnings: [ArtifactWarning],
        data: T
    ) {
        self.kind = kind
        self.role = role
        self.schemaVersion = schemaVersion
        self.contentHash = contentHash
        self.inputsHash = inputsHash
        self.producedAt = producedAt
        self.producedBy = producedBy
        self.mode = mode
        self.warnings = warnings
        self.data = data
    }

    enum CodingKeys: String, CodingKey {
        case kind, role, data, warnings, mode
        case schemaVersion = "schema_version"
        case contentHash = "content_hash"
        case inputsHash = "inputs_hash"
        case producedAt = "produced_at"
        case producedBy = "produced_by"
    }
}

// MARK: - ArtifactSummary

/// Compact status row for one artifact kind, returned by `ArtifactStore.list()`.
public struct ArtifactSummary<Key: ArtifactKey>: Sendable {
    public let kind: Key
    public let status: ArtifactStatus
    public let producedAt: String?
    public let producedBy: String?
    public let warningCount: Int
    public let errorCount: Int
    public let infoCount: Int

    public init(
        kind: Key,
        status: ArtifactStatus,
        producedAt: String?,
        producedBy: String?,
        warningCount: Int,
        errorCount: Int,
        infoCount: Int
    ) {
        self.kind = kind
        self.status = status
        self.producedAt = producedAt
        self.producedBy = producedBy
        self.warningCount = warningCount
        self.errorCount = errorCount
        self.infoCount = infoCount
    }
}
