import CryptoKit
import Foundation

// MARK: - CacheEnvelope

struct CacheEnvelope<T: Codable>: Codable {
    let contentHash: String
    let schemaVersion: String
    let cachedAt: String
    let data: T

    enum CodingKeys: String, CodingKey {
        case data
        case contentHash = "content_hash"
        case schemaVersion = "schema_version"
        case cachedAt = "cached_at"
    }
}

// MARK: - AICache

enum AICache {
    /// Bump this when any cached model type changes shape.
    static let schemaVersion = "2.0.0"

    // MARK: Content hashing

    /// Compute a stable SHA-256 hex hash from the markdown content, serialized config, and schema version.
    static func contentHash(markdownContent: String, configData: Data?) -> String {
        var hasher = SHA256()
        hasher.update(data: Data(markdownContent.utf8))
        if let config = configData {
            hasher.update(data: config)
        }
        hasher.update(data: Data(schemaVersion.utf8))
        return hasher.finalize().compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: Load

    /// Load a cached value if the file exists and the content hash matches.
    static func load<T: Codable>(from url: URL, expectedHash: String) -> T? {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return nil }
        guard let envelope = try? JSONDecoder().decode(CacheEnvelope<T>.self, from: data) else {
            return nil
        }
        guard envelope.contentHash == expectedHash else { return nil }
        return envelope.data
    }

    // MARK: Save

    static func save<T: Codable>(_ value: T, to url: URL, contentHash: String) throws {
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
