import CryptoKit
import Foundation

// MARK: - CacheEnvelope

/// Legacy single-file cache envelope. Superseded by `Artifact<T>` but retained so the
/// store can read pre-workspace cache files for one upgrade cycle.
public struct CacheEnvelope<T: Codable>: Codable {
    public let contentHash: String
    public let schemaVersion: String
    public let cachedAt: String
    public let data: T

    enum CodingKeys: String, CodingKey {
        case data
        case contentHash = "content_hash"
        case schemaVersion = "schema_version"
        case cachedAt = "cached_at"
    }
}

// MARK: - AICache

/// Content hashing plus the legacy single-file cache reader/writer. The hashing inputs
/// are deliberately generic (a primary string, optional secondary data, optional extra
/// string) so any document pipeline can fold its own inputs into a stable cache key.
public enum AICache {
    /// Bump this when any cached model type changes shape.
    public static let schemaVersion = "2.0.0"

    // MARK: Content hashing

    /// Compute a stable SHA-256 hex hash from the markdown/source content, serialized
    /// config, optional free-form notes, and schema version. Existing workspaces without
    /// notes hash identically (the notes block contributes nothing when nil/empty).
    public static func contentHash(markdownContent: String, configData: Data?, notes: String? = nil) -> String {
        var hasher = SHA256()
        hasher.update(data: Data(markdownContent.utf8))
        if let config = configData {
            hasher.update(data: config)
        }
        if let notes, !notes.isEmpty {
            hasher.update(data: Data(notes.utf8))
        }
        hasher.update(data: Data(schemaVersion.utf8))
        return hasher.finalize().compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: Load

    /// Load a cached value if the file exists and the content hash matches.
    public static func load<T: Codable>(from url: URL, expectedHash: String) -> T? {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return nil }
        guard let envelope = try? JSONDecoder().decode(CacheEnvelope<T>.self, from: data) else {
            return nil
        }
        guard envelope.contentHash == expectedHash else { return nil }
        return envelope.data
    }

    // MARK: Save

    public static func save<T: Codable>(_ value: T, to url: URL, contentHash: String) throws {
        let envelope = CacheEnvelope(
            contentHash: contentHash,
            schemaVersion: schemaVersion,
            cachedAt: ISO8601DateFormatter().string(from: Date()),
            data: value
        )
        let data = try JSONCoders.prettySorted.encode(envelope)
        try data.write(to: url)
        print("  Cached to \(url.lastPathComponent)")
    }
}
