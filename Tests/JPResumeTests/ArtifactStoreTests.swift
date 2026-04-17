import Testing
@testable import jpresume
import Foundation

@Suite("Artifact Store")
struct ArtifactStoreTests {

    // MARK: - Helpers

    /// Returns a brand-new (project, workspace) pair. The caller must remove `project` to clean up.
    private func makeTempProject() -> (project: URL, workspace: URL) {
        let project = FileManager.default.temporaryDirectory
            .appendingPathComponent("jpresume-test-\(UUID().uuidString)", isDirectory: true)
        let workspace = project.appendingPathComponent(".jpresume", isDirectory: true)
        return (project, workspace)
    }

    // MARK: - Status state machine

    @Test func statusMissingWhenArtifactAbsent() {
        let (project, workspace) = makeTempProject()
        defer { try? FileManager.default.removeItem(at: project) }
        let store = ArtifactStore(root: workspace)
        #expect(store.status(.parsed) == .missing)
    }

    @Test func statusFreshAfterWrite() throws {
        let (project, workspace) = makeTempProject()
        defer { try? FileManager.default.removeItem(at: project) }
        let store = ArtifactStore(root: workspace)
        let western = WesternResume(name: "Test")
        try store.write(western, kind: .parsed, contentHash: "h", inputsHash: "h", producedBy: "test")
        #expect(store.status(.parsed) == .fresh)
        #expect(store.status(.parsed, expectedContentHash: "h") == .fresh)
    }

    @Test func statusStaleWhenExpectedHashDiffers() throws {
        let (project, workspace) = makeTempProject()
        defer { try? FileManager.default.removeItem(at: project) }
        let store = ArtifactStore(root: workspace)
        let western = WesternResume(name: "Test")
        try store.write(western, kind: .parsed, contentHash: "old", inputsHash: "old", producedBy: "test")
        guard case .stale = store.status(.parsed, expectedContentHash: "new") else {
            Issue.record("expected .stale, got \(store.status(.parsed, expectedContentHash: "new"))")
            return
        }
    }

    @Test func statusInvalidOnUnparseableFile() throws {
        let (project, workspace) = makeTempProject()
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: project) }
        let url = workspace.appendingPathComponent("parsed.json")
        try "not valid json".write(to: url, atomically: true, encoding: .utf8)
        let store = ArtifactStore(root: workspace)
        guard case .invalid = store.status(.parsed) else {
            Issue.record("expected .invalid, got \(store.status(.parsed))")
            return
        }
    }

    @Test func statusInvalidOnSchemaVersionMismatch() throws {
        let (project, workspace) = makeTempProject()
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: project) }

        // Hand-craft an artifact with a bogus schema_version.
        let payload = """
        {
          "kind": "parsed",
          "role": "source",
          "schema_version": "0.0.0",
          "content_hash": "x",
          "inputs_hash": "x",
          "produced_at": "2024-01-01T00:00:00Z",
          "produced_by": "test",
          "mode": "internal",
          "warnings": [],
          "data": {}
        }
        """
        let url = workspace.appendingPathComponent("parsed.json")
        try payload.write(to: url, atomically: true, encoding: .utf8)

        let store = ArtifactStore(root: workspace)
        guard case .invalid(let reason) = store.status(.parsed) else {
            Issue.record("expected .invalid, got \(store.status(.parsed))")
            return
        }
        #expect(reason.contains("schema"))
    }

    @Test func statusStaleWhenOnlyLegacyCacheExists() throws {
        let (project, workspace) = makeTempProject()
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: project) }

        // Legacy path lives one level up from the workspace.
        let legacyURL = project.appendingPathComponent(".normalized_cache.json")
        let resume = NormalizedResume(name: "Legacy")
        try AICache.save(resume, to: legacyURL, contentHash: "legacy")

        let store = ArtifactStore(root: workspace)
        guard case .stale(let reason) = store.status(.normalized) else {
            Issue.record("expected .stale, got \(store.status(.normalized))")
            return
        }
        #expect(reason.lowercased().contains("legacy"))
    }

    // MARK: - Read / Write

    @Test func readThrowsWhenMissing() {
        let (project, workspace) = makeTempProject()
        defer { try? FileManager.default.removeItem(at: project) }
        let store = ArtifactStore(root: workspace)
        #expect(throws: (any Error).self) {
            _ = try store.read(.parsed, as: WesternResume.self)
        }
    }

    @Test func roundTripPreservesEnvelope() throws {
        let (project, workspace) = makeTempProject()
        defer { try? FileManager.default.removeItem(at: project) }
        let store = ArtifactStore(root: workspace)
        let western = WesternResume(name: "Round Trip", skills: ["Swift"])
        try store.write(western, kind: .parsed, contentHash: "ch", inputsHash: "ih",
                        producedBy: "jpresume/0.2.0")
        let artifact = try store.read(.parsed, as: WesternResume.self)

        #expect(artifact.data.name == "Round Trip")
        #expect(artifact.data.skills == ["Swift"])
        #expect(artifact.kind == "parsed")
        #expect(artifact.role == "source")
        #expect(artifact.contentHash == "ch")
        #expect(artifact.inputsHash == "ih")
        #expect(artifact.producedBy == "jpresume/0.2.0")
        #expect(artifact.mode == "internal")
    }

    @Test func repairedAndValidationHaveDerivedRole() throws {
        let (project, workspace) = makeTempProject()
        defer { try? FileManager.default.removeItem(at: project) }
        let store = ArtifactStore(root: workspace)

        try store.write(NormalizedResume(), kind: .repaired, contentHash: "h", inputsHash: "h", producedBy: "x")
        try store.write(ValidationResult(issues: []), kind: .validation, contentHash: "h", inputsHash: "h",
                        producedBy: "x")

        let rep = try store.read(.repaired, as: NormalizedResume.self)
        let val = try store.read(.validation, as: ValidationResult.self)
        #expect(rep.role == "derived")
        #expect(val.role == "derived")
    }

    @Test func writeOverwritesExisting() throws {
        let (project, workspace) = makeTempProject()
        defer { try? FileManager.default.removeItem(at: project) }
        let store = ArtifactStore(root: workspace)
        try store.write(WesternResume(name: "A"), kind: .parsed, contentHash: "h", inputsHash: "h",
                        producedBy: "t")
        try store.write(WesternResume(name: "B"), kind: .parsed, contentHash: "h", inputsHash: "h",
                        producedBy: "t")
        let artifact = try store.read(.parsed, as: WesternResume.self)
        #expect(artifact.data.name == "B")
    }

    // MARK: - Legacy cache fallback

    @Test func loadLegacyReturnsValueOnHashMatch() throws {
        let (project, workspace) = makeTempProject()
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: project) }

        let legacyURL = project.appendingPathComponent(".normalized_cache.json")
        let resume = NormalizedResume(name: "Legacy User")
        try AICache.save(resume, to: legacyURL, contentHash: "hash1")

        let store = ArtifactStore(root: workspace)
        let loaded: NormalizedResume? = store.loadLegacy(.normalized, expectedHash: "hash1")
        #expect(loaded?.name == "Legacy User")
    }

    @Test func loadLegacyReturnsNilOnHashMismatch() throws {
        let (project, workspace) = makeTempProject()
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: project) }

        let legacyURL = project.appendingPathComponent(".rirekisho_cache.json")
        try AICache.save(NormalizedResume(), to: legacyURL, contentHash: "hash1")

        let store = ArtifactStore(root: workspace)
        let loaded: NormalizedResume? = store.loadLegacy(.rirekisho, expectedHash: "different")
        #expect(loaded == nil)
    }

    @Test func loadLegacyReturnsNilForArtifactKindsWithoutLegacyPath() {
        let (project, workspace) = makeTempProject()
        defer { try? FileManager.default.removeItem(at: project) }
        let store = ArtifactStore(root: workspace)
        // No legacy fallback exists for parsed / inputs / repaired / validation.
        let parsed: WesternResume? = store.loadLegacy(.parsed, expectedHash: "h")
        let inputs: InputsData? = store.loadLegacy(.inputs, expectedHash: "h")
        #expect(parsed == nil)
        #expect(inputs == nil)
    }

    // MARK: - List

    @Test func listReportsAllKinds() throws {
        let (project, workspace) = makeTempProject()
        defer { try? FileManager.default.removeItem(at: project) }
        let store = ArtifactStore(root: workspace)
        try store.write(WesternResume(name: "Alice"), kind: .parsed, contentHash: "h", inputsHash: "h",
                        producedBy: "jpresume/0.2.0")
        let summaries = store.list()
        #expect(summaries.count == ArtifactKind.allCases.count)
        #expect(summaries.contains { $0.kind == .parsed && $0.status == .fresh })
        #expect(summaries.contains { $0.kind == .normalized && $0.status == .missing })
    }
}
