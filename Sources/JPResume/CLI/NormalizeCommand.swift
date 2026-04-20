import ArgumentParser
import Foundation

struct NormalizeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "normalize",
        abstract: "Normalize parsed resume using AI (reads parsed.json, writes normalized.json)"
    )

    @Option(help: "Workspace directory (default: ./.jpresume)")
    var workspace: String?

    @Option(help: "AI provider")
    var provider: ProviderChoice = .ollama

    @Option(help: "Model name override")
    var model: String?

    @Flag(name: [.short, .long], help: "Show detailed output")
    var verbose = false

    @Flag(help: "Ignore cached AI output and regenerate")
    var noCache = false

    @Flag(help: "Emit normalize.prompt.json and exit (external-mode)")
    var external = false

    @Flag(help: "Ingest normalize.response.json and write normalized.json")
    var ingest = false

    func run() async throws {
        let workspaceURL = workspace.map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".jpresume")
        let store = ArtifactStore(root: workspaceURL)

        let inputsArtifact = try store.read(.inputs, as: InputsData.self)
        let parsedArtifact = try store.read(.parsed, as: WesternResume.self)
        let inputsHash = inputsArtifact.data.markdownHash

        if !noCache, store.status(.normalized, expectedContentHash: inputsHash) == .fresh {
            let age = store.producedAt(.normalized).map { formatAge($0) } ?? "?"
            let by = store.producedBy(.normalized) ?? "unknown"
            print("Normalized resume is fresh (\(by), \(age)) — skipping. Use --no-cache to force.")
            return
        }

        if external {
            let system = SystemPrompts.normalization()
            let enc = JSONCoders.prettySorted
            let westernJSON = (try? enc.encode(parsedArtifact.data)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            let configJSON = (try? enc.encode(inputsArtifact.data.config)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            let sourceKind = inputsArtifact.data.sourceKind?.rawValue ?? "text"
            let cleanedText = (try? enc.encode(inputsArtifact.data.cleanedText ?? inputsArtifact.data.sourceText)).flatMap {
                String(data: $0, encoding: .utf8)
            } ?? "null"
            let notes = (try? enc.encode(inputsArtifact.data.preprocessingNotes)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            let user = """
            {
              "western_resume": \(westernJSON),
              "japan_config": \(configJSON),
              "source_input": {
                "kind": "\(sourceKind)",
                "cleaned_text": \(cleanedText),
                "preprocessing_notes": \(notes)
              }
            }
            """
            try ExternalBridge.emitPrompt(stage: "normalize", kind: .normalized, workspace: workspaceURL,
                                          sourceArtifacts: ["parsed.json", "inputs.json"],
                                          system: system, user: user, temperature: 0.2)
            return
        }

        if ingest {
            let raw = try ExternalBridge.readResponse(stage: "normalize", workspace: workspaceURL)
            do {
                let jsonData = try JSONExtractor.extract(from: raw)
                let normalized = try JSONDecoder().decode(NormalizedResume.self, from: jsonData)
                let by = ProducedBy.external(model: model ?? "external")
                try store.write(normalized, kind: .normalized, contentHash: inputsHash, inputsHash: inputsHash,
                                producedBy: by, mode: "external")
                print("  ✓ Ingested normalized.json")
            } catch {
                let bundle = ErrorBundle(stage: "normalize", error: error.localizedDescription,
                                         responsePath: workspaceURL.appendingPathComponent("normalize.response.json").path)
                try? ExternalBridge.writeError(bundle, stage: "normalize", workspace: workspaceURL)
                throw error
            }
            return
        }

        // Internal LLM call
        print("Normalizing resume...")
        let providerInstance = try ProviderFactory.create(provider: provider.rawValue, model: model)
        print("  Using AI provider: \(providerInstance.name)")
        let normalized = try await Stages.normalize(
            western: parsedArtifact.data, inputs: inputsArtifact.data, config: inputsArtifact.data.config,
            provider: providerInstance, verbose: verbose
        )
        try store.write(normalized, kind: .normalized, contentHash: inputsHash, inputsHash: inputsHash,
                        producedBy: ProducedBy.jpresume(providerSlug: provider.rawValue, modelOverride: model))
        print("  ✓ \(workspaceURL.path)/normalized.json")
    }
}
