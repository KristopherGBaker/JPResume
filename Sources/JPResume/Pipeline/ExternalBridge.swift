import Foundation

// MARK: - PromptBundle

/// JSON bundle written to <workspace>/<stage>.prompt.json in --external mode.
struct PromptBundle: Codable {
    let stage: String
    let artifactKind: String
    let workspace: String
    let sourceArtifacts: [String]
    let stageOptions: [String: String]
    let system: String
    let user: String
    let temperature: Double
    let expectedOutputFormat: String
    /// Empty for MVP — prose-only schema lives in `system`. Reserved for future JSON Schema emission.
    let responseSchema: [String: String]
    let responsePath: String

    enum CodingKeys: String, CodingKey {
        case stage, workspace, system, user, temperature
        case artifactKind = "artifact_kind"
        case sourceArtifacts = "source_artifacts"
        case stageOptions = "stage_options"
        case expectedOutputFormat = "expected_output_format"
        case responseSchema = "response_schema"
        case responsePath = "response_path"
    }
}

// MARK: - ExternalBridge

enum ExternalBridge {

    /// Write a prompt bundle for an external agent to fulfil.
    /// Exits after writing; caller should return/exit with success.
    static func emitPrompt(
        stage: String,
        kind: ArtifactKind,
        workspace: URL,
        sourceArtifacts: [String],
        stageOptions: [String: String] = [:],
        system: String,
        user: String,
        temperature: Double
    ) throws {
        let responsePath = workspace.appendingPathComponent("\(stage).response.json").path
        let bundle = PromptBundle(
            stage: stage,
            artifactKind: kind.rawValue,
            workspace: workspace.path,
            sourceArtifacts: sourceArtifacts,
            stageOptions: stageOptions,
            system: system,
            user: user,
            temperature: temperature,
            expectedOutputFormat: "json-only",
            responseSchema: [:],
            responsePath: responsePath
        )

        let data = try JSONCoders.prettySorted.encode(bundle)

        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let promptURL = workspace.appendingPathComponent("\(stage).prompt.json")
        try data.write(to: promptURL)
        print("  Prompt written to \(promptURL.path)")
        print("  Write the AI response to \(responsePath)")
        print("  Then run: jpresume \(stage) --workspace \(workspace.path) --ingest")
    }

    /// Read the agent's response from <workspace>/<stage>.response.json.
    /// Returns the raw string content (the AI's reply).
    /// On failure writes <workspace>/<stage>.error.json and throws.
    static func readResponse(stage: String, workspace: URL) throws -> String {
        let responseURL = workspace.appendingPathComponent("\(stage).response.json")
        guard FileManager.default.fileExists(atPath: responseURL.path) else {
            throw ExternalBridgeError.responseMissing(responseURL.path)
        }

        do {
            let raw = try String(contentsOf: responseURL, encoding: .utf8)
            return raw
        } catch {
            let errInfo = ErrorBundle(stage: stage, error: error.localizedDescription,
                                      responsePath: responseURL.path)
            try? writeError(errInfo, stage: stage, workspace: workspace)
            throw error
        }
    }

    /// Write a structured error file when --ingest fails.
    static func writeError(_ error: ErrorBundle, stage: String, workspace: URL) throws {
        let data = try JSONCoders.prettySorted.encode(error)
        let url = workspace.appendingPathComponent("\(stage).error.json")
        try data.write(to: url)
        print("  Error written to \(url.path)")
    }
}

// MARK: - ErrorBundle

struct ErrorBundle: Codable {
    let stage: String
    let error: String
    let responsePath: String
    let timestamp: String

    init(stage: String, error: String, responsePath: String) {
        self.stage = stage
        self.error = error
        self.responsePath = responsePath
        self.timestamp = ISO8601DateFormatter().string(from: Date())
    }

    enum CodingKeys: String, CodingKey {
        case stage, error, timestamp
        case responsePath = "response_path"
    }
}

// MARK: - ExternalBridgeError

enum ExternalBridgeError: Error, CustomStringConvertible {
    case responseMissing(String)
    case parseError(String)

    var description: String {
        switch self {
        case .responseMissing(let path):
            return "Response file not found: \(path). Write the AI output there and re-run with --ingest."
        case .parseError(let msg):
            return "Failed to parse AI response: \(msg)"
        }
    }
}
