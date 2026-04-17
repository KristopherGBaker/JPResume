import Testing
@testable import jpresume
import Foundation

@Suite("External Bridge")
struct ExternalBridgeTests {

    private func makeTempWorkspace() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("jpresume-ext-\(UUID().uuidString)", isDirectory: true)
    }

    // MARK: - emitPrompt

    @Test func emitPromptWritesBundleWithAllFields() throws {
        let ws = makeTempWorkspace()
        defer { try? FileManager.default.removeItem(at: ws) }

        try ExternalBridge.emitPrompt(
            stage: "normalize",
            kind: .normalized,
            workspace: ws,
            sourceArtifacts: ["parsed.json", "inputs.json"],
            stageOptions: ["era": "western"],
            system: "system text",
            user: "user text",
            temperature: 0.2
        )

        let url = ws.appendingPathComponent("normalize.prompt.json")
        #expect(FileManager.default.fileExists(atPath: url.path))

        let data = try Data(contentsOf: url)
        let bundle = try JSONDecoder().decode(PromptBundle.self, from: data)

        #expect(bundle.stage == "normalize")
        #expect(bundle.artifactKind == "normalized")
        #expect(bundle.workspace == ws.path)
        #expect(bundle.sourceArtifacts == ["parsed.json", "inputs.json"])
        #expect(bundle.stageOptions["era"] == "western")
        #expect(bundle.system == "system text")
        #expect(bundle.user == "user text")
        #expect(bundle.temperature == 0.2)
        #expect(bundle.expectedOutputFormat == "json-only")
        #expect(bundle.responseSchema.isEmpty)  // MVP ships empty
        #expect(bundle.responsePath.hasSuffix("normalize.response.json"))
    }

    @Test func emitPromptWritesGenerateStageBundle() throws {
        let ws = makeTempWorkspace()
        defer { try? FileManager.default.removeItem(at: ws) }

        try ExternalBridge.emitPrompt(
            stage: "shokumukeirekisho",
            kind: .shokumukeirekisho,
            workspace: ws,
            sourceArtifacts: ["repaired.json", "inputs.json"],
            stageOptions: [
                "era": "japanese",
                "include_side_projects": "true",
                "include_older_irrelevant_roles": "false"
            ],
            system: "sys",
            user: "usr",
            temperature: 0.3
        )

        let url = ws.appendingPathComponent("shokumukeirekisho.prompt.json")
        let data = try Data(contentsOf: url)
        let bundle = try JSONDecoder().decode(PromptBundle.self, from: data)

        #expect(bundle.artifactKind == "shokumukeirekisho")
        #expect(bundle.stageOptions["era"] == "japanese")
        #expect(bundle.stageOptions["include_side_projects"] == "true")
        #expect(bundle.stageOptions["include_older_irrelevant_roles"] == "false")
        #expect(bundle.temperature == 0.3)
    }

    // MARK: - readResponse

    @Test func readResponseReturnsFileContents() throws {
        let ws = makeTempWorkspace()
        try FileManager.default.createDirectory(at: ws, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ws) }

        let url = ws.appendingPathComponent("normalize.response.json")
        let canned = #"{"name":"Test"}"#
        try canned.write(to: url, atomically: true, encoding: .utf8)

        let got = try ExternalBridge.readResponse(stage: "normalize", workspace: ws)
        #expect(got == canned)
    }

    @Test func readResponseThrowsWhenMissing() {
        let ws = makeTempWorkspace()
        defer { try? FileManager.default.removeItem(at: ws) }

        #expect(throws: (any Error).self) {
            _ = try ExternalBridge.readResponse(stage: "normalize", workspace: ws)
        }
    }

    // MARK: - writeError

    @Test func writeErrorPersistsStructuredBundle() throws {
        let ws = makeTempWorkspace()
        try FileManager.default.createDirectory(at: ws, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ws) }

        let bundle = ErrorBundle(
            stage: "normalize",
            error: "decoder failed at /experience[0]/start_date",
            responsePath: ws.appendingPathComponent("normalize.response.json").path
        )
        try ExternalBridge.writeError(bundle, stage: "normalize", workspace: ws)

        let url = ws.appendingPathComponent("normalize.error.json")
        #expect(FileManager.default.fileExists(atPath: url.path))

        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(ErrorBundle.self, from: data)
        #expect(decoded.stage == "normalize")
        #expect(decoded.error.contains("decoder failed"))
        #expect(!decoded.timestamp.isEmpty)
    }
}
