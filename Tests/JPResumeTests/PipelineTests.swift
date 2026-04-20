import Testing
@testable import jpresume
import Foundation

@Suite("Pipeline: hashes, ProducedBy, Stages")
struct PipelineTests {

    // MARK: - ArtifactHashes

    @Test func inputsHashMatchesAICache() {
        let md = "resume content"
        let cfg = Data("config".utf8)
        #expect(ArtifactHashes.inputs(markdownContent: md, configData: cfg)
                == AICache.contentHash(markdownContent: md, configData: cfg))
    }

    @Test func rirekishoHashVariesWithEra() {
        let h1 = ArtifactHashes.rirekisho(inputsHash: "x", era: .western)
        let h2 = ArtifactHashes.rirekisho(inputsHash: "x", era: .japanese)
        #expect(h1 != h2)
    }

    @Test func rirekishoHashStableForSameInputs() {
        let h1 = ArtifactHashes.rirekisho(inputsHash: "x", era: .western)
        let h2 = ArtifactHashes.rirekisho(inputsHash: "x", era: .western)
        #expect(h1 == h2)
    }

    /// Regression test for the pre-refactor bug where `--include-side-projects`
    /// didn't invalidate the shokumukeirekisho cache.
    @Test func shokumukeirekishoHashVariesWithIncludeSideProjects() {
        let h1 = ArtifactHashes.shokumukeirekisho(
            inputsHash: "x", era: .western,
            options: GenerationOptions(includeSideProjects: false, includeOlderIrrelevantRoles: true)
        )
        let h2 = ArtifactHashes.shokumukeirekisho(
            inputsHash: "x", era: .western,
            options: GenerationOptions(includeSideProjects: true, includeOlderIrrelevantRoles: true)
        )
        #expect(h1 != h2)
    }

    @Test func shokumukeirekishoHashVariesWithOlderRolesFlag() {
        let h1 = ArtifactHashes.shokumukeirekisho(
            inputsHash: "x", era: .western,
            options: GenerationOptions(includeOlderIrrelevantRoles: true)
        )
        let h2 = ArtifactHashes.shokumukeirekisho(
            inputsHash: "x", era: .western,
            options: GenerationOptions(includeOlderIrrelevantRoles: false)
        )
        #expect(h1 != h2)
    }

    @Test func shokumukeirekishoHashVariesWithEra() {
        let opts = GenerationOptions()
        let h1 = ArtifactHashes.shokumukeirekisho(inputsHash: "x", era: .western, options: opts)
        let h2 = ArtifactHashes.shokumukeirekisho(inputsHash: "x", era: .japanese, options: opts)
        #expect(h1 != h2)
    }

    @Test func shokumukeirekishoHashVariesWithInputs() {
        let opts = GenerationOptions()
        let h1 = ArtifactHashes.shokumukeirekisho(inputsHash: "a", era: .western, options: opts)
        let h2 = ArtifactHashes.shokumukeirekisho(inputsHash: "b", era: .western, options: opts)
        #expect(h1 != h2)
    }

    // MARK: - ProducedBy

    @Test func producedByDeterministic() {
        #expect(ProducedBy.jpresume() == "jpresume/\(ProducedBy.version)")
    }

    @Test func producedByWithExplicitModel() {
        #expect(ProducedBy.jpresume(providerSlug: "anthropic", modelOverride: "claude-sonnet-4-6")
                == "jpresume/\(ProducedBy.version) anthropic:claude-sonnet-4-6")
    }

    @Test func producedByFallsBackToDefaultModel() {
        // "anthropic" default is "claude-sonnet-4-6" per ProviderFactory.defaultModels
        #expect(ProducedBy.jpresume(providerSlug: "anthropic", modelOverride: nil)
                == "jpresume/\(ProducedBy.version) anthropic:claude-sonnet-4-6")
    }

    @Test func producedByHandlesEmptyDefaultModel() {
        // claude-cli has "" as default → omit the colon segment
        #expect(ProducedBy.jpresume(providerSlug: "claude-cli", modelOverride: nil)
                == "jpresume/\(ProducedBy.version) claude-cli")
    }

    @Test func producedByExternalFormat() {
        #expect(ProducedBy.external(model: "gpt-5.4") == "claude-code/external gpt-5.4")
    }

    // MARK: - Stages (deterministic wrappers only)

    @Test func parseReturnsWesternResume() {
        let md = """
        # Jane Doe

        ## Experience

        ### Engineer at Corp
        Jan 2020 - Dec 2023

        - Built things
        """
        let result = Stages.parse(text: md, sourceKind: .markdown)
        // Parser success is indicated by at least one of these being populated.
        let didAnything = result.name != nil
            || !result.experience.isEmpty
            || !result.rawSections.isEmpty
        #expect(didAnything)
    }

    @Test func repairIsIdempotent() {
        let resume = NormalizedResume(
            name: "Test",
            experience: [
                NormalizedWorkEntry(
                    company: "Corp",
                    startDate: StructuredDate(year: 2020, month: 1),
                    endDate: StructuredDate(year: 2023, month: 12)
                )
            ]
        )
        let once = Stages.repair(resume)
        let twice = Stages.repair(once)
        #expect(once.experience.count == twice.experience.count)
        #expect(once.derivedExperience?.totalSoftwareYears == twice.derivedExperience?.totalSoftwareYears)
    }

    @Test func validateFlagsMissingName() {
        let resume = NormalizedResume(name: nil)
        let result = Stages.validate(resume)
        #expect(result.issues.contains { $0.field == "name" })
    }

    @Test func inputsDataDecodesLegacyShape() throws {
        let json = """
        {
          "source_path": "/tmp/resume.pdf",
          "markdown_hash": "abc",
          "config": {}
        }
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(InputsData.self, from: data)
        #expect(decoded.sourcePath == "/tmp/resume.pdf")
        #expect(decoded.sourceKind == nil)
        #expect(decoded.cleanedText == nil)
        #expect(decoded.preprocessingNotes.isEmpty)
    }
}
