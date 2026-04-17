import ArgumentParser
import Foundation

// MARK: - GenerateCommand (parent)

struct GenerateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "generate",
        abstract: "Generate Japanese resume data from repaired resume",
        subcommands: [GenerateRirekishoCommand.self, GenerateShokumukeirekishoCommand.self]
    )
}

// MARK: - GenerateRirekishoCommand

struct GenerateRirekishoCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rirekisho",
        abstract: "Generate 履歴書 data (reads repaired.json, writes rirekisho.json)"
    )

    @Option(help: "Workspace directory (default: ./.jpresume)")
    var workspace: String?

    @Option(help: "AI provider")
    var provider: ProviderChoice = .ollama

    @Option(help: "Model name override")
    var model: String?

    @Option(help: "Date format style")
    var era: EraStyle = .western

    @Flag(name: [.short, .long], help: "Show detailed output")
    var verbose = false

    @Flag(help: "Ignore cached output and regenerate")
    var noCache = false

    @Option(help: "Path to target-company context JSON file (enables tailored application mode)")
    var target: String?

    @Flag(help: "Emit rirekisho.prompt.json and exit (external-mode)")
    var external = false

    @Flag(help: "Ingest rirekisho.response.json and write rirekisho.json")
    var ingest = false

    func run() async throws {
        let workspaceURL = workspace.map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".jpresume")
        let store = ArtifactStore(root: workspaceURL)

        let inputsArtifact = try store.read(.inputs, as: InputsData.self)
        let inputsHash = inputsArtifact.data.markdownHash

        let targetContext = try loadTargetContext(target)

        // Strictly require repaired.json
        guard store.status(.repaired) != .missing else {
            print("Error: repaired.json not found. Run 'jpresume repair' first.")
            throw ExitCode.failure
        }
        let repairedArtifact = try store.read(.repaired, as: NormalizedResume.self)
        let repaired = repairedArtifact.data

        let contentHash = ArtifactHashes.rirekisho(inputsHash: inputsHash, era: era,
                                                    targetContext: targetContext)

        if !noCache, store.status(.rirekisho, expectedContentHash: contentHash) == .fresh {
            let age = store.producedAt(.rirekisho).map { formatAge($0) } ?? "?"
            let by = store.producedBy(.rirekisho) ?? "unknown"
            print("履歴書 data is fresh (\(by), \(age)) — skipping. Use --no-cache to force.")
            return
        }

        if external {
            let eraStyle = era == .japanese ? "Japanese era (令和/平成)" : "western year"
            let eraExample = era == .japanese ? "令和2年4月" : "2020年4月"
            let system = SystemPrompts.rirekisho(eraStyle: eraStyle, eraExample: eraExample,
                                                  targetContext: targetContext)
            let user = try buildUserMessage(repaired: repaired, config: inputsArtifact.data.config,
                                            targetContext: targetContext)
            var opts = ["era": era.rawValue]
            if let t = target { opts["target"] = t }
            try ExternalBridge.emitPrompt(stage: "rirekisho", kind: .rirekisho, workspace: workspaceURL,
                                          sourceArtifacts: ["repaired.json", "inputs.json"],
                                          stageOptions: opts, system: system, user: user, temperature: 0.3)
            return
        }

        if ingest {
            let raw = try ExternalBridge.readResponse(stage: "rirekisho", workspace: workspaceURL)
            do {
                let jsonData = try JSONExtractor.extract(from: raw)
                var data = try JSONDecoder().decode(RirekishoData.self, from: jsonData)
                data = Stages.polish(data, derived: repaired.derivedExperience)
                let by = ProducedBy.external(model: model ?? "external")
                try store.write(data, kind: .rirekisho, contentHash: contentHash, inputsHash: inputsHash,
                                producedBy: by, mode: "external")
                print("  ✓ Ingested rirekisho.json")
            } catch {
                let bundle = ErrorBundle(stage: "rirekisho", error: error.localizedDescription,
                                         responsePath: workspaceURL.appendingPathComponent("rirekisho.response.json").path)
                try? ExternalBridge.writeError(bundle, stage: "rirekisho", workspace: workspaceURL)
                throw error
            }
            return
        }

        // Internal LLM call
        print("Generating 履歴書\(targetContext != nil ? " (targeted)" : "")...")
        let providerInstance = try ProviderFactory.create(provider: provider.rawValue, model: model)
        print("  Using AI provider: \(providerInstance.name)")
        var rirekishoData = try await Stages.generateRirekisho(
            repaired: repaired, config: inputsArtifact.data.config, era: era,
            targetContext: targetContext, provider: providerInstance, verbose: verbose
        )
        rirekishoData = Stages.polish(rirekishoData, derived: repaired.derivedExperience)
        try store.write(rirekishoData, kind: .rirekisho, contentHash: contentHash, inputsHash: inputsHash,
                        producedBy: ProducedBy.jpresume(providerSlug: provider.rawValue, modelOverride: model))
        print("  ✓ \(workspaceURL.path)/rirekisho.json")
    }

    private func buildUserMessage(repaired: NormalizedResume, config: JapanConfig,
                                   targetContext: TargetCompanyContext?) throws -> String {
        buildTargetUserMessage(repaired: repaired, config: config, targetContext: targetContext)
    }
}

// MARK: - GenerateShokumukeirekishoCommand

struct GenerateShokumukeirekishoCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "shokumukeirekisho",
        abstract: "Generate 職務経歴書 data (reads repaired.json, writes shokumukeirekisho.json)"
    )

    @Option(help: "Workspace directory (default: ./.jpresume)")
    var workspace: String?

    @Option(help: "AI provider")
    var provider: ProviderChoice = .ollama

    @Option(help: "Model name override")
    var model: String?

    @Option(help: "Date format style")
    var era: EraStyle = .western

    @Flag(name: [.short, .long], help: "Show detailed output")
    var verbose = false

    @Flag(help: "Ignore cached output and regenerate")
    var noCache = false

    @Flag(help: "Include personal/side projects")
    var includeSideProjects = false

    @Flag(help: "Exclude older irrelevant roles")
    var excludeOlderRoles = false

    @Option(help: "Path to target-company context JSON file (enables tailored application mode)")
    var target: String?

    @Flag(help: "Emit shokumukeirekisho.prompt.json and exit (external-mode)")
    var external = false

    @Flag(help: "Ingest shokumukeirekisho.response.json and write shokumukeirekisho.json")
    var ingest = false

    func run() async throws {
        let workspaceURL = workspace.map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".jpresume")
        let store = ArtifactStore(root: workspaceURL)

        let inputsArtifact = try store.read(.inputs, as: InputsData.self)
        let inputsHash = inputsArtifact.data.markdownHash

        let targetContext = try loadTargetContext(target)

        guard store.status(.repaired) != .missing else {
            print("Error: repaired.json not found. Run 'jpresume repair' first.")
            throw ExitCode.failure
        }
        let repairedArtifact = try store.read(.repaired, as: NormalizedResume.self)
        let repaired = repairedArtifact.data
        let genOptions = GenerationOptions(
            includeSideProjects: includeSideProjects,
            includeOlderIrrelevantRoles: !excludeOlderRoles
        )
        let contentHash = ArtifactHashes.shokumukeirekisho(inputsHash: inputsHash, era: era,
                                                            options: genOptions, targetContext: targetContext)

        if !noCache, store.status(.shokumukeirekisho, expectedContentHash: contentHash) == .fresh {
            let age = store.producedAt(.shokumukeirekisho).map { formatAge($0) } ?? "?"
            let by = store.producedBy(.shokumukeirekisho) ?? "unknown"
            print("職務経歴書 data is fresh (\(by), \(age)) — skipping. Use --no-cache to force.")
            return
        }

        if external {
            let eraStyle = era == .japanese ? "Japanese era (令和/平成)" : "western year"
            let system = SystemPrompts.shokumukeirekisho(eraStyle: eraStyle, options: genOptions,
                                                          targetContext: targetContext)
            let user = try buildUserMessage(repaired: repaired, config: inputsArtifact.data.config,
                                            targetContext: targetContext)
            var opts = [
                "era": era.rawValue,
                "include_side_projects": String(includeSideProjects),
                "include_older_irrelevant_roles": String(!excludeOlderRoles)
            ]
            if let t = target { opts["target"] = t }
            try ExternalBridge.emitPrompt(stage: "shokumukeirekisho", kind: .shokumukeirekisho,
                                          workspace: workspaceURL,
                                          sourceArtifacts: ["repaired.json", "inputs.json"],
                                          stageOptions: opts, system: system, user: user, temperature: 0.3)
            return
        }

        if ingest {
            let raw = try ExternalBridge.readResponse(stage: "shokumukeirekisho", workspace: workspaceURL)
            do {
                let jsonData = try JSONExtractor.extract(from: raw)
                var data = try JSONDecoder().decode(ShokumukeirekishoData.self, from: jsonData)
                data = Stages.polish(data, derived: repaired.derivedExperience)
                let by = ProducedBy.external(model: model ?? "external")
                try store.write(data, kind: .shokumukeirekisho, contentHash: contentHash, inputsHash: inputsHash,
                                producedBy: by, mode: "external")
                print("  ✓ Ingested shokumukeirekisho.json")
            } catch {
                let bundle = ErrorBundle(stage: "shokumukeirekisho", error: error.localizedDescription,
                                         responsePath: workspaceURL.appendingPathComponent("shokumukeirekisho.response.json").path)
                try? ExternalBridge.writeError(bundle, stage: "shokumukeirekisho", workspace: workspaceURL)
                throw error
            }
            return
        }

        // Internal LLM call
        print("Generating 職務経歴書\(targetContext != nil ? " (targeted)" : "")...")
        let providerInstance = try ProviderFactory.create(provider: provider.rawValue, model: model)
        print("  Using AI provider: \(providerInstance.name)")
        var shokumuData = try await Stages.generateShokumukeirekisho(
            repaired: repaired, config: inputsArtifact.data.config, era: era,
            options: genOptions, targetContext: targetContext, provider: providerInstance, verbose: verbose
        )
        shokumuData = Stages.polish(shokumuData, derived: repaired.derivedExperience)
        try store.write(shokumuData, kind: .shokumukeirekisho, contentHash: contentHash, inputsHash: inputsHash,
                        producedBy: ProducedBy.jpresume(providerSlug: provider.rawValue, modelOverride: model))
        print("  ✓ \(workspaceURL.path)/shokumukeirekisho.json")
    }

    private func buildUserMessage(repaired: NormalizedResume, config: JapanConfig,
                                   targetContext: TargetCompanyContext?) throws -> String {
        buildTargetUserMessage(repaired: repaired, config: config, targetContext: targetContext)
    }
}

// MARK: - Shared helpers

func loadTargetContext(_ path: String?) throws -> TargetCompanyContext? {
    guard let path else { return nil }
    let url = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: url.path) else {
        print("Error: target context file not found: \(path)")
        throw ExitCode.failure
    }
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(TargetCompanyContext.self, from: data)
}

func buildTargetUserMessage(repaired: NormalizedResume, config: JapanConfig,
                             targetContext: TargetCompanyContext?) -> String {
    let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    let r = (try? enc.encode(repaired)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    let c = (try? enc.encode(config)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    let today = ISO8601DateFormatter().string(from: Date()).prefix(10)
    var msg = "{\n  \"normalized_resume\": \(r),\n  \"japan_config\": \(c),\n  \"today\": \"\(today)\""
    if let ctx = targetContext,
       let ctxData = try? enc.encode(ctx),
       let ctxStr = String(data: ctxData, encoding: .utf8) {
        msg += ",\n  \"target_company_context\": \(ctxStr)"
    }
    msg += "\n}"
    return msg
}
