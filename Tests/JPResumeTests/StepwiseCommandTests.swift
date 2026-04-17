import Testing
@testable import jpresume
import Foundation

@Suite("Stepwise Commands (integration)")
struct StepwiseCommandTests {

    // MARK: - Fixtures

    /// A workspace laid out like `parse` would leave it: inputs.json + parsed.json present.
    /// Returns the project dir (remove it to clean up) and the workspace dir.
    private func makeParsedWorkspace() throws -> (project: URL, workspace: URL, inputsHash: String) {
        let project = FileManager.default.temporaryDirectory
            .appendingPathComponent("jpresume-step-\(UUID().uuidString)", isDirectory: true)
        let workspace = project.appendingPathComponent(".jpresume", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)

        let cfg = JapanConfig()
        let md = "# Jane Doe\n\n## Experience\n\n### Engineer at Corp\nJan 2020 - Dec 2023\n\n- Built stuff"
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let cfgData = try enc.encode(cfg)
        let inputsHash = ArtifactHashes.inputs(markdownContent: md, configData: cfgData)

        let store = ArtifactStore(root: workspace)
        let inputs = InputsData(sourcePath: project.appendingPathComponent("resume.md").path,
                                markdownHash: inputsHash, config: cfg)
        try store.write(inputs, kind: .inputs, contentHash: inputsHash, inputsHash: inputsHash,
                        producedBy: "jpresume/test")

        let western = Stages.parse(markdown: md)
        try store.write(western, kind: .parsed, contentHash: inputsHash, inputsHash: inputsHash,
                        producedBy: "jpresume/test")
        return (project, workspace, inputsHash)
    }

    /// Adds repaired.json (empty-experience, but decodable) to the workspace.
    private func addRepairedArtifact(to workspace: URL, inputsHash: String) throws -> NormalizedResume {
        let repaired = NormalizedResume(
            name: "Jane Doe",
            experience: [
                NormalizedWorkEntry(
                    company: "Corp",
                    title: "Engineer",
                    startDate: StructuredDate(year: 2020, month: 1),
                    endDate: StructuredDate(year: 2023, month: 12)
                )
            ]
        )
        let store = ArtifactStore(root: workspace)
        try store.write(repaired, kind: .repaired, contentHash: inputsHash, inputsHash: inputsHash,
                        producedBy: "jpresume/test")
        return repaired
    }

    /// Minimal JSON for a NormalizedResume that round-trips through JSONExtractor + JSONDecoder.
    private func cannedNormalizedJSON() throws -> String {
        let resume = NormalizedResume(
            name: "Canned",
            experience: [
                NormalizedWorkEntry(
                    company: "Acme",
                    startDate: StructuredDate(year: 2020),
                    endDate: StructuredDate(year: 2023)
                )
            ]
        )
        let data = try JSONEncoder().encode(resume)
        return String(data: data, encoding: .utf8)!
    }

    // MARK: - normalize --external

    @Test func normalizeExternalEmitsPromptBundle() async throws {
        let (project, workspace, _) = try makeParsedWorkspace()
        defer { try? FileManager.default.removeItem(at: project) }

        let cmd = try NormalizeCommand.parse(["--workspace", workspace.path, "--external"])
        try await cmd.run()

        let promptURL = workspace.appendingPathComponent("normalize.prompt.json")
        #expect(FileManager.default.fileExists(atPath: promptURL.path))

        let data = try Data(contentsOf: promptURL)
        let bundle = try JSONDecoder().decode(PromptBundle.self, from: data)
        #expect(bundle.stage == "normalize")
        #expect(bundle.artifactKind == "normalized")
        #expect(bundle.sourceArtifacts.contains("parsed.json"))
        #expect(bundle.sourceArtifacts.contains("inputs.json"))
        #expect(bundle.temperature == 0.2)

        // Must NOT have written normalized.json (external-mode exits without calling the LLM)
        let normalizedURL = workspace.appendingPathComponent("normalized.json")
        #expect(!FileManager.default.fileExists(atPath: normalizedURL.path))
    }

    // MARK: - normalize --ingest

    @Test func normalizeIngestWritesNormalizedArtifact() async throws {
        let (project, workspace, inputsHash) = try makeParsedWorkspace()
        defer { try? FileManager.default.removeItem(at: project) }

        let responseURL = workspace.appendingPathComponent("normalize.response.json")
        try cannedNormalizedJSON().write(to: responseURL, atomically: true, encoding: .utf8)

        let cmd = try NormalizeCommand.parse(["--workspace", workspace.path, "--ingest"])
        try await cmd.run()

        let store = ArtifactStore(root: workspace)
        #expect(store.status(.normalized, expectedContentHash: inputsHash) == .fresh)

        let artifact = try store.read(.normalized, as: NormalizedResume.self)
        #expect(artifact.data.name == "Canned")
        #expect(artifact.mode == "external")
        #expect(artifact.producedBy.hasPrefix("claude-code/external"))
    }

    @Test func normalizeIngestWritesErrorBundleOnMalformedResponse() async throws {
        let (project, workspace, _) = try makeParsedWorkspace()
        defer { try? FileManager.default.removeItem(at: project) }

        let responseURL = workspace.appendingPathComponent("normalize.response.json")
        try "this is not json".write(to: responseURL, atomically: true, encoding: .utf8)

        let cmd = try NormalizeCommand.parse(["--workspace", workspace.path, "--ingest"])
        await #expect(throws: (any Error).self) {
            try await cmd.run()
        }

        let errorURL = workspace.appendingPathComponent("normalize.error.json")
        #expect(FileManager.default.fileExists(atPath: errorURL.path))
    }

    // MARK: - repair + validate stepwise chain

    @Test func repairProducesDerivedArtifact() async throws {
        let (project, workspace, inputsHash) = try makeParsedWorkspace()
        defer { try? FileManager.default.removeItem(at: project) }

        // Provide normalized.json via cached response so repair has input.
        let responseURL = workspace.appendingPathComponent("normalize.response.json")
        try cannedNormalizedJSON().write(to: responseURL, atomically: true, encoding: .utf8)
        let normalize = try NormalizeCommand.parse(["--workspace", workspace.path, "--ingest"])
        try await normalize.run()

        let repair = try RepairCommand.parse(["--workspace", workspace.path])
        try await repair.run()

        let store = ArtifactStore(root: workspace)
        #expect(store.status(.repaired, expectedContentHash: inputsHash) == .fresh)
        let artifact = try store.read(.repaired, as: NormalizedResume.self)
        #expect(artifact.role == "derived")
    }

    @Test func validateWritesValidationArtifact() async throws {
        let (project, workspace, inputsHash) = try makeParsedWorkspace()
        defer { try? FileManager.default.removeItem(at: project) }

        let responseURL = workspace.appendingPathComponent("normalize.response.json")
        try cannedNormalizedJSON().write(to: responseURL, atomically: true, encoding: .utf8)
        try await NormalizeCommand.parse(["--workspace", workspace.path, "--ingest"]).run()

        let validate = try ValidateCommand.parse(["--workspace", workspace.path, "--on", "normalized"])
        try await validate.run()

        let store = ArtifactStore(root: workspace)
        #expect(store.status(.validation, expectedContentHash: inputsHash) == .fresh)
        let artifact = try store.read(.validation, as: ValidationResult.self)
        #expect(artifact.role == "derived")
    }

    // MARK: - generate requires repaired.json

    @Test func generateRirekishoFailsWithoutRepaired() async throws {
        let (project, workspace, _) = try makeParsedWorkspace()
        defer { try? FileManager.default.removeItem(at: project) }

        // No repaired.json exists — external-mode should still refuse.
        let cmd = try GenerateRirekishoCommand.parse(["--workspace", workspace.path, "--external"])
        await #expect(throws: (any Error).self) {
            try await cmd.run()
        }

        // And nothing should have been written.
        let promptURL = workspace.appendingPathComponent("rirekisho.prompt.json")
        #expect(!FileManager.default.fileExists(atPath: promptURL.path))
    }

    @Test func generateShokumukeirekishoFailsWithoutRepaired() async throws {
        let (project, workspace, _) = try makeParsedWorkspace()
        defer { try? FileManager.default.removeItem(at: project) }

        let cmd = try GenerateShokumukeirekishoCommand.parse([
            "--workspace", workspace.path, "--external"
        ])
        await #expect(throws: (any Error).self) {
            try await cmd.run()
        }
    }

    @Test func generateRirekishoExternalEmitsPromptWhenRepairedPresent() async throws {
        let (project, workspace, inputsHash) = try makeParsedWorkspace()
        defer { try? FileManager.default.removeItem(at: project) }
        _ = try addRepairedArtifact(to: workspace, inputsHash: inputsHash)

        let cmd = try GenerateRirekishoCommand.parse(["--workspace", workspace.path, "--external"])
        try await cmd.run()

        let promptURL = workspace.appendingPathComponent("rirekisho.prompt.json")
        #expect(FileManager.default.fileExists(atPath: promptURL.path))

        let data = try Data(contentsOf: promptURL)
        let bundle = try JSONDecoder().decode(PromptBundle.self, from: data)
        #expect(bundle.stage == "rirekisho")
        #expect(bundle.artifactKind == "rirekisho")
        #expect(bundle.sourceArtifacts.contains("repaired.json"))
        #expect(bundle.stageOptions["era"] == "western")
    }

    // MARK: - generate with --target

    @Test func generateRirekishoExternalIncludesTargetInStageOptions() async throws {
        let (project, workspace, inputsHash) = try makeParsedWorkspace()
        defer { try? FileManager.default.removeItem(at: project) }
        _ = try addRepairedArtifact(to: workspace, inputsHash: inputsHash)

        // Write a minimal target context file
        let ctx = TargetCompanyContext(companyName: "Acme Corp", roleTitle: "iOS Engineer",
                                       emphasisTags: ["mobile", "consumer"])
        let targetURL = project.appendingPathComponent("target.json")
        try JSONEncoder().encode(ctx).write(to: targetURL)

        let cmd = try GenerateRirekishoCommand.parse([
            "--workspace", workspace.path,
            "--target", targetURL.path,
            "--external"
        ])
        try await cmd.run()

        let data = try Data(contentsOf: workspace.appendingPathComponent("rirekisho.prompt.json"))
        let bundle = try JSONDecoder().decode(PromptBundle.self, from: data)
        #expect(bundle.stageOptions["target"] == targetURL.path)
        // System prompt should include the company name
        #expect(bundle.system.contains("Acme Corp"))
    }

    @Test func generateRirekishoHashDiffersWithTarget() async throws {
        let (project, _, inputsHash) = try makeParsedWorkspace()
        defer { try? FileManager.default.removeItem(at: project) }

        let ctx = TargetCompanyContext(companyName: "TargetCo")
        let baseHash = ArtifactHashes.rirekisho(inputsHash: inputsHash, era: .western)
        let targetedHash = ArtifactHashes.rirekisho(inputsHash: inputsHash, era: .western,
                                                     targetContext: ctx)
        #expect(baseHash != targetedHash)
    }

    // MARK: - inspect

    @Test func inspectDoesNotThrowOnEmptyWorkspace() async throws {
        let project = FileManager.default.temporaryDirectory
            .appendingPathComponent("jpresume-inspect-\(UUID().uuidString)", isDirectory: true)
        let workspace = project.appendingPathComponent(".jpresume", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: project) }

        let cmd = try InspectCommand.parse(["--workspace", workspace.path])
        try await cmd.run()
    }
}
