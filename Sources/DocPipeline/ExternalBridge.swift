import Foundation

// MARK: - PromptBundle

/// JSON bundle written to <workspace>/<stage>.prompt.json in --external mode.
public struct PromptBundle: Codable {
    public let stage: String
    public let artifactKind: String
    public let workspace: String
    public let sourceArtifacts: [String]
    public let stageOptions: [String: String]
    public let system: String
    public let user: String
    public let temperature: Double
    public let expectedOutputFormat: String
    /// Empty for MVP — prose-only schema lives in `system`. Reserved for future JSON Schema emission.
    public let responseSchema: [String: String]
    public let responsePath: String

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

/// Emits prompt bundles for an external agent and ingests their responses. Generic over a
/// pipeline's `ArtifactKey`; provenance for ingested artifacts is supplied by the caller
/// via `producedBy` so this layer stays free of any app-specific naming.
public enum ExternalBridge {

    /// Write a prompt bundle for an external agent to fulfil.
    /// Exits after writing; caller should return/exit with success.
    public static func emitPrompt<Key: ArtifactKey>(
        stage: String,
        kind: Key,
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
    public static func readResponse(stage: String, workspace: URL) throws -> String {
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
    public static func writeError(_ error: ErrorBundle, stage: String, workspace: URL) throws {
        let data = try JSONCoders.prettySorted.encode(error)
        let url = workspace.appendingPathComponent("\(stage).error.json")
        try data.write(to: url)
        print("  Error written to \(url.path)")
    }

    /// Read an external agent's response, decode it, optionally transform it, and write the
    /// resulting artifact. Wraps the read → extract → decode → (transform) → write pipeline
    /// shared by every `--ingest` flow, including the `ErrorBundle` cleanup that fires when
    /// any step throws. `producedBy` is supplied by the caller (e.g. "claude-code/external <model>").
    public static func ingestResponse<T: Codable, Key: ArtifactKey>(
        stage: String,
        kind: Key,
        workspace: URL,
        store: ArtifactStore<Key>,
        contentHash: String,
        inputsHash: String,
        producedBy: String,
        as _: T.Type = T.self,
        transform: (T) -> T = { $0 }
    ) throws {
        let raw = try readResponse(stage: stage, workspace: workspace)
        do {
            let jsonData = try extractJSON(from: raw)
            let decoded = try JSONDecoder().decode(T.self, from: jsonData)
            let final = transform(decoded)
            try store.write(final, kind: kind, contentHash: contentHash, inputsHash: inputsHash,
                            producedBy: producedBy, mode: "external")
            print("  ✓ Ingested \(kind.filename)")
        } catch {
            let bundle = ErrorBundle(
                stage: stage, error: error.localizedDescription,
                responsePath: workspace.appendingPathComponent("\(stage).response.json").path
            )
            try? writeError(bundle, stage: stage, workspace: workspace)
            throw error
        }
    }
}

// MARK: - ErrorBundle

public struct ErrorBundle: Codable {
    public let stage: String
    public let error: String
    public let responsePath: String
    public let timestamp: String

    public init(stage: String, error: String, responsePath: String) {
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

public enum ExternalBridgeError: Error, CustomStringConvertible {
    case responseMissing(String)
    case parseError(String)

    public var description: String {
        switch self {
        case .responseMissing(let path):
            return "Response file not found: \(path). Write the AI output there and re-run with --ingest."
        case .parseError(let msg):
            return "Failed to parse AI response: \(msg)"
        }
    }
}

// MARK: - JSON extraction

/// Extract the first valid JSON object from an external agent's response. Tolerates a
/// markdown code fence around the object and a brace-matched object embedded in prose.
/// External agents (humans, other LLMs) routinely emit either shape.
private func extractJSON(from text: String) throws -> Data {
    let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

    // Code-fence form: ```json\n{...}\n```
    if cleaned.contains("```") {
        let parts = cleaned.components(separatedBy: "```")
        for part in parts.dropFirst() {
            var content = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if content.hasPrefix("json") || content.hasPrefix("JSON") {
                content = String(content.drop(while: { $0 != "\n" }).dropFirst())
            }
            content = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if content.hasPrefix("{"),
               let data = content.data(using: .utf8),
               (try? JSONSerialization.jsonObject(with: data)) != nil {
                return data
            }
        }
    }

    // Direct JSON
    if let data = cleaned.data(using: .utf8),
       (try? JSONSerialization.jsonObject(with: data)) != nil {
        return data
    }

    // Brace-match fallback
    guard let startIdx = cleaned.firstIndex(of: "{") else {
        throw ExternalBridgeError.parseError(String(cleaned.prefix(200)))
    }
    var depth = 0
    for (i, ch) in cleaned[startIdx...].enumerated() {
        if ch == "{" { depth += 1 } else if ch == "}" {
            depth -= 1
            if depth == 0 {
                let endOffset = cleaned.index(startIdx, offsetBy: i + 1)
                let jsonStr = String(cleaned[startIdx..<endOffset])
                if let data = jsonStr.data(using: .utf8) { return data }
            }
        }
    }
    throw ExternalBridgeError.parseError(String(cleaned.prefix(200)))
}
