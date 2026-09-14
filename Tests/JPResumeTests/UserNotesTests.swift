import DocPipeline
import Testing
@testable import jpresume
import ArgumentParser
import Foundation
import Shikisha

/// Covers --notes wiring: resolver, hash invalidation, payload inclusion, prompt-bundle
/// round-trip through external mode.
@Suite("User notes (--notes)")
struct UserNotesTests {

    // MARK: - resolveNotes

    @Test func resolveNotesReturnsNilForNilOrEmpty() throws {
        #expect(try resolveNotes(nil) == nil)
        #expect(try resolveNotes("") == nil)
        #expect(try resolveNotes("   ") == nil)
    }

    @Test func resolveNotesReadsFileContentsWhenPathExists() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("jpresume-notes-\(UUID().uuidString).md")
        try "extra context line\nsecond line".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try resolveNotes(url.path)
        #expect(result == "extra context line\nsecond line")
    }

    @Test func resolveNotesTreatsNonPathAsInline() throws {
        let result = try resolveNotes("Emphasize my AI work.")
        #expect(result == "Emphasize my AI work.")
    }

    // MARK: - Hash invalidation

    @Test func inputsHashChangesWhenNotesAdded() {
        let baseline = ArtifactHashes.inputs(markdownContent: "resume", configData: nil)
        let withNotes = ArtifactHashes.inputs(markdownContent: "resume", configData: nil,
                                               notes: "extra context")
        #expect(baseline != withNotes)
    }

    @Test func inputsHashIsStableForNilOrEmptyNotes() {
        let baseline = ArtifactHashes.inputs(markdownContent: "resume", configData: nil)
        let nilNotes = ArtifactHashes.inputs(markdownContent: "resume", configData: nil, notes: nil)
        let emptyNotes = ArtifactHashes.inputs(markdownContent: "resume", configData: nil, notes: "")
        #expect(baseline == nilNotes)
        #expect(baseline == emptyNotes)
    }

    @Test func inputsHashChangesWhenNotesEdited() {
        let a = ArtifactHashes.inputs(markdownContent: "resume", configData: nil, notes: "version 1")
        let b = ArtifactHashes.inputs(markdownContent: "resume", configData: nil, notes: "version 2")
        #expect(a != b)
    }

    // MARK: - Payload inclusion

    @Test func normalizePayloadIncludesAdditionalContextWhenNotesPresent() throws {
        let inputs = InputsData(sourcePath: "/x.md", markdownHash: "h", config: JapanConfig(),
                                userNotes: "I also worked at FooCorp 2010-2012.")
        let payload = try PromptPayload.normalize(western: WesternResume(),
                                                   inputs: inputs, config: JapanConfig())
        #expect(payload.contains("\"additional_context\""))
        #expect(payload.contains("FooCorp"))
    }

    @Test func normalizePayloadOmitsAdditionalContextWhenNotesAbsent() throws {
        let inputs = InputsData(sourcePath: "/x.md", markdownHash: "h", config: JapanConfig())
        let payload = try PromptPayload.normalize(western: WesternResume(),
                                                   inputs: inputs, config: JapanConfig())
        #expect(!payload.contains("\"additional_context\""))
    }

    @Test func adaptPayloadIncludesAdditionalContextWhenProvided() throws {
        let payload = try PromptPayload.adapt(
            normalized: NormalizedResume(name: "X"),
            config: JapanConfig(),
            additionalContext: "Emphasize iOS work."
        )
        #expect(payload.contains("\"additional_context\""))
        #expect(payload.contains("Emphasize iOS work."))
    }

    @Test func adaptPayloadOmitsAdditionalContextWhenAbsent() throws {
        let payload = try PromptPayload.adapt(
            normalized: NormalizedResume(name: "X"),
            config: JapanConfig()
        )
        #expect(!payload.contains("\"additional_context\""))
    }

    // MARK: - InputsData round-trip

    @Test func inputsDataDecodesUserNotesField() throws {
        let original = InputsData(sourcePath: "/x.md", markdownHash: "h", config: JapanConfig(),
                                  userNotes: "extra context")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(InputsData.self, from: data)
        #expect(decoded.userNotes == "extra context")
    }

    @Test func inputsDataDecodesLegacyShapeWithoutUserNotes() throws {
        let json = """
        {
          "source_path": "/tmp/r.md",
          "markdown_hash": "abc",
          "config": {}
        }
        """
        let decoded = try JSONDecoder().decode(InputsData.self, from: Data(json.utf8))
        #expect(decoded.userNotes == nil)
    }

    // MARK: - End-to-end through ResumeAI

    @Test func generateRirekishoPassesNotesToPrompt() async throws {
        let clean = makeRirekishoClean()
        let model = FakeChatModel(responses: [aiMessage(clean)])

        _ = try await ResumeAI(model: model, verbose: false)
            .generateRirekisho(normalized: NormalizedResume(name: "X"),
                               config: JapanConfig(), era: .western,
                               additionalContext: "I prefer 株式会社 over Inc. for Japanese entities.")

        let calls = await model.snapshotInvocations()
        let userMessage = calls.first?.last?.content ?? ""
        #expect(userMessage.contains("additional_context"))
        #expect(userMessage.contains("株式会社"))
    }

    // MARK: - Stepwise plumbing (parse --notes → inputs.json → generate)

    /// `parse --notes` must persist the notes and fold them into the inputs hash, so a
    /// stepwise run gets the same additional_context that `convert --notes` does.
    @Test func parseStoresNotesInInputsAndFoldsThemIntoTheHash() async throws {
        let project = FileManager.default.temporaryDirectory
            .appendingPathComponent("jpresume-notes-parse-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: project) }

        let resume = project.appendingPathComponent("resume.md")
        try "# Jane Doe\n\n## Experience\n\n### Engineer at Corp\nJan 2020 - Dec 2023\n\n- Built stuff"
            .write(to: resume, atomically: true, encoding: .utf8)
        let config = project.appendingPathComponent("jpresume_config.yaml")
        try "name_kanji: 山田 太郎\n".write(to: config, atomically: true, encoding: .utf8)

        let bare = project.appendingPathComponent(".jpresume-bare", isDirectory: true)
        let bareParse = try ParseCommand.parse([resume.path, "--workspace", bare.path,
                                                "--config", config.path])
        try await bareParse.run()
        let bareInputs = try ArtifactStore(root: bare).read(.inputs, as: InputsData.self)

        let noted = project.appendingPathComponent(".jpresume-noted", isDirectory: true)
        let notedParse = try ParseCommand.parse([resume.path, "--workspace", noted.path,
                                                 "--config", config.path,
                                                 "--notes", "Include my Sparra side project."])
        try await notedParse.run()
        let notedInputs = try ArtifactStore(root: noted).read(.inputs, as: InputsData.self)

        #expect(bareInputs.data.userNotes == nil)
        #expect(notedInputs.data.userNotes == "Include my Sparra side project.")
        #expect(notedInputs.data.markdownHash != bareInputs.data.markdownHash)
    }

    /// The generate stages read notes back out of inputs.json — without this the stepwise
    /// prompt bundle silently drops context that the internal `convert` path honours.
    @Test func generateExternalPromptCarriesNotesFromInputs() async throws {
        let project = FileManager.default.temporaryDirectory
            .appendingPathComponent("jpresume-notes-gen-\(UUID().uuidString)", isDirectory: true)
        let workspace = project.appendingPathComponent(".jpresume", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: project) }

        let store = ArtifactStore(root: workspace)
        let hash = "notes-hash"
        let inputs = InputsData(sourcePath: "/tmp/resume.md", markdownHash: hash, config: JapanConfig(),
                                userNotes: "Target a general backend role, not iOS.")
        try store.write(inputs, kind: .inputs, contentHash: hash, inputsHash: hash,
                        producedBy: "jpresume/test")
        try store.write(NormalizedResume(name: "Jane Doe"), kind: .repaired,
                        contentHash: hash, inputsHash: hash, producedBy: "jpresume/test")

        func bundle(for stage: String) throws -> PromptBundle {
            let data = try Data(contentsOf: workspace.appendingPathComponent("\(stage).prompt.json"))
            return try JSONDecoder().decode(PromptBundle.self, from: data)
        }

        let rirekisho = try GenerateRirekishoCommand.parse(["--workspace", workspace.path, "--external"])
        try await rirekisho.run()
        let shokumu = try GenerateShokumukeirekishoCommand.parse(["--workspace", workspace.path, "--external"])
        try await shokumu.run()

        for stage in ["rirekisho", "shokumukeirekisho"] {
            let promptBundle = try bundle(for: stage)
            #expect(promptBundle.user.contains("additional_context"))
            #expect(promptBundle.user.contains("general backend role"))
        }
    }

    // MARK: - Fixtures

    private func makeRirekishoClean() -> RirekishoData {
        RirekishoData(
            creationDate: "令和7年5月", nameKanji: "山田 太郎", nameFurigana: "ヤマダ タロウ",
            dateOfBirth: "平成元年1月1日",
            gender: nil, postalCode: nil, address: nil, addressFurigana: nil,
            contactPostalCode: nil, contactAddress: nil, contactAddressFurigana: nil,
            phone: nil, email: nil, photoPath: nil,
            educationHistory: [],
            workHistory: [
                DateDescription("令和元年4月", "株式会社サンプル 入社"),
                DateDescription("", "現在に至る")
            ],
            licenses: [],
            motivation: "貴社の事業に関心があり、応募いたしました。",
            hobbies: nil, commuteTime: nil, spouse: nil, dependents: nil, dependentsExclSpouse: nil
        )
    }

    private func aiMessage<T: Encodable>(_ value: T) -> AIMessage {
        let data = try! JSONEncoder().encode(value)  // swiftlint:disable:this force_try
        return AIMessage(content: String(data: data, encoding: .utf8)!)
    }
}
