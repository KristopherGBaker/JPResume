import Testing
@testable import jpresume
import Foundation

@Suite("AI Cache")
struct CacheTests {

    // MARK: Content hashing

    @Test func hashChangesWhenMarkdownChanges() {
        let h1 = AICache.contentHash(markdownContent: "resume v1", configData: nil)
        let h2 = AICache.contentHash(markdownContent: "resume v2", configData: nil)
        #expect(h1 != h2)
    }

    @Test func hashChangesWhenConfigChanges() {
        let configA = Data("config_a".utf8)
        let configB = Data("config_b".utf8)
        let h1 = AICache.contentHash(markdownContent: "same", configData: configA)
        let h2 = AICache.contentHash(markdownContent: "same", configData: configB)
        #expect(h1 != h2)
    }

    @Test func hashIsStableForSameInputs() {
        let config = Data("config".utf8)
        let h1 = AICache.contentHash(markdownContent: "resume", configData: config)
        let h2 = AICache.contentHash(markdownContent: "resume", configData: config)
        #expect(h1 == h2)
    }

    @Test func hashIsNonEmpty() {
        let hash = AICache.contentHash(markdownContent: "test", configData: nil)
        #expect(!hash.isEmpty)
        #expect(hash.count == 64) // SHA-256 = 32 bytes = 64 hex chars
    }

    // MARK: Save and load

    @Test func saveAndLoadRoundtrip() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_cache_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let value = NormalizedResume(name: "Test User")
        let hash = AICache.contentHash(markdownContent: "md", configData: nil)

        try AICache.save(value, to: tempURL, contentHash: hash)
        let loaded: NormalizedResume? = AICache.load(from: tempURL, expectedHash: hash)

        #expect(loaded != nil)
        #expect(loaded?.name == "Test User")
    }

    @Test func loadReturnsNilOnHashMismatch() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_cache_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let value = NormalizedResume(name: "Test User")
        let writeHash = AICache.contentHash(markdownContent: "v1", configData: nil)
        let readHash = AICache.contentHash(markdownContent: "v2", configData: nil)

        try AICache.save(value, to: tempURL, contentHash: writeHash)
        let loaded: NormalizedResume? = AICache.load(from: tempURL, expectedHash: readHash)

        #expect(loaded == nil)
    }

    @Test func loadReturnsNilForMissingFile() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonexistent_\(UUID().uuidString).json")
        let loaded: NormalizedResume? = AICache.load(from: url, expectedHash: "anyhash")
        #expect(loaded == nil)
    }
}
