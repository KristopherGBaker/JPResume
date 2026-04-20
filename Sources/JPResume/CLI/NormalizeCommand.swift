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
            let user = try PromptPayload.normalize(western: parsedArtifact.data, inputs: inputsArtifact.data,
                                                   config: inputsArtifact.data.config)
            try ExternalBridge.emitPrompt(stage: "normalize", kind: .normalized, workspace: workspaceURL,
                                          sourceArtifacts: ["parsed.json", "inputs.json"],
                                          system: system, user: user, temperature: 0.2)
            return
        }

        if ingest {
            try ExternalBridge.ingestResponse(
                stage: "normalize", kind: .normalized,
                workspace: workspaceURL, store: store,
                contentHash: inputsHash, inputsHash: inputsHash, model: model,
                as: NormalizedResume.self
            )
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
