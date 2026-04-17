import ArgumentParser
import Foundation

struct ConvertCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "convert",
        abstract: "Convert a western resume to Japanese format (one-shot)"
    )

    @Argument(help: "Path to western-style markdown resume")
    var input: String

    @Option(name: [.short, .long], help: "Output directory (default: same as input)")
    var outputDir: String?

    @Option(name: [.short, .long], help: "Path to YAML config file")
    var config: String?

    @Option(help: "Workspace directory for intermediate artifacts (default: <outputDir>/.jpresume)")
    var workspace: String?

    @Flag(help: "Re-prompt for all Japan-specific fields")
    var reconfigure = false

    @Option(help: "Output format")
    var format: OutputFormat = .both

    @Flag(help: "Generate only the rirekisho (履歴書)")
    var rirekishoOnly = false

    @Flag(help: "Generate only the shokumukeirekisho (職務経歴書)")
    var shokumukeirekishoOnly = false

    @Option(help: "AI provider")
    var provider: ProviderChoice = .ollama

    @Option(help: "Model name override")
    var model: String?

    @Option(help: "Date format style")
    var era: EraStyle = .western

    @Flag(help: "Ignore cached AI output and regenerate")
    var noCache = false

    @Flag(help: "Parse and analyze only, don't generate output")
    var dryRun = false

    @Flag(name: [.short, .long], help: "Show detailed output")
    var verbose = false

    @Flag(help: "Treat validation warnings as errors")
    var strict = false

    @Flag(help: "Include personal/side projects in 職務経歴書")
    var includeSideProjects = false

    @Flag(help: "Exclude older irrelevant roles from 職務経歴書")
    var excludeOlderRoles = false

    func run() async throws {
        let inputURL = URL(fileURLWithPath: input)
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            print("Error: Input file not found: \(input)")
            throw ExitCode.failure
        }

        let inputDir = inputURL.deletingLastPathComponent()
        let outputURL = outputDir.map { URL(fileURLWithPath: $0) } ?? inputDir
        let configURL = config.map { URL(fileURLWithPath: $0) }
            ?? inputDir.appendingPathComponent("jpresume_config.yaml")
        let workspaceURL = workspace.map { URL(fileURLWithPath: $0) }
            ?? outputURL.appendingPathComponent(".jpresume")
        let store = ArtifactStore(root: workspaceURL)

        // Step 1: Parse
        print("\nStep 1: Parsing western resume...")
        let text = try String(contentsOf: inputURL, encoding: .utf8)
        let western = Stages.parse(markdown: text)
        print("  Found: \(western.experience.count) work entries, "
              + "\(western.education.count) education entries, "
              + "\(western.skills.count) skills")

        // Step 2: Config
        print("\nStep 2: Gathering Japan-specific information...")
        let japanConfig = try ConfigManager.loadOrPrompt(
            path: configURL, western: western, forceReconfigure: reconfigure
        )
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let configData = try? enc.encode(japanConfig)
        let inputsHash = ArtifactHashes.inputs(markdownContent: text, configData: configData)
        let by = ProducedBy.jpresume()

        let inputsData = InputsData(sourcePath: inputURL.path, markdownHash: inputsHash, config: japanConfig)
        try store.write(inputsData, kind: .inputs, contentHash: inputsHash, inputsHash: inputsHash, producedBy: by)
        try store.write(western, kind: .parsed, contentHash: inputsHash, inputsHash: inputsHash, producedBy: by)

        // Step 3: Normalize (with cache)
        print("\nStep 3: Normalizing resume...")
        let normalized = try await resolveNormalized(store: store, western: western, config: japanConfig,
                                                      inputsHash: inputsHash, producedBy: by)

        // Step 4: Validate
        print("\nStep 4: Validating...")
        let validation = Stages.validate(normalized)
        if validation.hasIssues {
            ResumeValidator.printResult(validation)
            if strict && !validation.isValid {
                print("\nValidation errors found. Use --no-strict to continue anyway.")
                throw ExitCode.failure
            }
        } else {
            if let years = validation.totalYearsExperience {
                print("  ✓ Valid — \(String(format: "%.1f", years)) years experience")
            } else {
                print("  ✓ Valid")
            }
        }
        let validationWarnings = validation.issues.map { $0.asArtifactWarning }
        try store.write(validation, kind: .validation, contentHash: inputsHash, inputsHash: inputsHash,
                        producedBy: by, warnings: validationWarnings)

        // Step 4b: Repair
        print("\nStep 4b: Checking consistency and repairing...")
        let repaired = Stages.repair(normalized)
        try store.write(repaired, kind: .repaired, contentHash: inputsHash, inputsHash: inputsHash, producedBy: by)
        printRepairs(repaired)

        if dryRun {
            let prettyEncoder = JSONEncoder()
            prettyEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            print("\nParsed resume (WesternResume):")
            print(String(data: try prettyEncoder.encode(western), encoding: .utf8)!)
            print("\nNormalized resume (NormalizedResume):")
            print(String(data: try prettyEncoder.encode(normalized), encoding: .utf8)!)
            print("\nDry run complete. No output generated.")
            return
        }

        // Step 5: Generate rirekisho + shokumukeirekisho
        let genOptions = GenerationOptions(
            includeSideProjects: includeSideProjects,
            includeOlderIrrelevantRoles: !excludeOlderRoles
        )
        let rHash = ArtifactHashes.rirekisho(inputsHash: inputsHash, era: era)
        let sHash = ArtifactHashes.shokumukeirekisho(inputsHash: inputsHash, era: era, options: genOptions)

        print("\nStep 5: Translating and adapting with AI...")
        let (rirekishoData, shokumukeirekishoData) = try await resolveJPData(
            store: store, repaired: repaired, config: japanConfig, genOptions: genOptions,
            inputsHash: inputsHash, rirekishoHash: rHash, shokumuHash: sHash, producedBy: by
        )

        // Step 5b: Polish
        let derived = repaired.derivedExperience
        let polishedRirekisho = rirekishoData.map { Stages.polish($0, derived: derived) }
        let polishedShokumu = shokumukeirekishoData.map { Stages.polish($0, derived: derived) }

        if let r = polishedRirekisho {
            try store.write(r, kind: .rirekisho, contentHash: rHash, inputsHash: inputsHash, producedBy: by)
        }
        if let s = polishedShokumu {
            try store.write(s, kind: .shokumukeirekisho, contentHash: sHash, inputsHash: inputsHash, producedBy: by)
        }

        // Step 6: Render
        print("\nStep 6: Generating output files...")
        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
        try renderOutput(rirekisho: polishedRirekisho, shokumukeirekisho: polishedShokumu, to: outputURL)

        print("\nDone! Workspace: \(workspaceURL.path)")
    }
}

// MARK: - Private helpers

extension ConvertCommand {
    private func resolveNormalized(
        store: ArtifactStore,
        western: WesternResume,
        config: JapanConfig,
        inputsHash: String,
        producedBy: String
    ) async throws -> NormalizedResume {
        if !noCache {
            if store.status(.normalized, expectedContentHash: inputsHash) == .fresh,
               let artifact = try? store.read(.normalized, as: NormalizedResume.self) {
                let age = store.producedAt(.normalized).map { formatAge($0) } ?? "?"
                let by = store.producedBy(.normalized) ?? "unknown"
                print("  Using cached normalized resume (\(by), \(age))")
                return artifact.data
            }
            if let legacy: NormalizedResume = store.loadLegacy(.normalized, expectedHash: inputsHash) {
                print("  Using legacy cached normalized resume (upgrading to workspace format)")
                // Legacy caches don't record their producer, so don't instantiate one here.
                try store.write(legacy, kind: .normalized, contentHash: inputsHash, inputsHash: inputsHash,
                                producedBy: ProducedBy.jpresume())
                return legacy
            }
        }
        let providerInstance = try ProviderFactory.create(provider: provider.rawValue, model: model)
        print("  Using AI provider: \(providerInstance.name)")
        let result = try await Stages.normalize(western: western, config: config,
                                                provider: providerInstance, verbose: verbose)
        try store.write(result, kind: .normalized, contentHash: inputsHash, inputsHash: inputsHash,
                        producedBy: ProducedBy.jpresume(providerSlug: provider.rawValue, modelOverride: model))
        return result
    }

    private func resolveJPData(
        store: ArtifactStore,
        repaired: NormalizedResume,
        config: JapanConfig,
        genOptions: GenerationOptions,
        inputsHash: String,
        rirekishoHash: String,
        shokumuHash: String,
        producedBy: String
    ) async throws -> (RirekishoData?, ShokumukeirekishoData?) {
        let generateR = !shokumukeirekishoOnly
        let generateS = !rirekishoOnly

        var rirekishoData: RirekishoData?
        var shokumuData: ShokumukeirekishoData?

        if generateR && !noCache {
            if store.status(.rirekisho, expectedContentHash: rirekishoHash) == .fresh,
               let artifact = try? store.read(.rirekisho, as: RirekishoData.self) {
                let age = store.producedAt(.rirekisho).map { formatAge($0) } ?? "?"
                let by = store.producedBy(.rirekisho) ?? "unknown"
                print("  Using cached 履歴書 data (\(by), \(age))")
                rirekishoData = artifact.data
            } else if let legacy: RirekishoData = store.loadLegacy(.rirekisho, expectedHash: inputsHash) {
                // Legacy cache was keyed by inputsHash only; era/options weren't in the hash.
                // Trusting it matches the spirit of the pre-existing behavior for one release.
                print("  Using legacy cached 履歴書 data (upgrading to workspace format)")
                try store.write(legacy, kind: .rirekisho, contentHash: rirekishoHash, inputsHash: inputsHash,
                                producedBy: ProducedBy.jpresume())
                rirekishoData = legacy
            }
        }
        if generateS && !noCache {
            if store.status(.shokumukeirekisho, expectedContentHash: shokumuHash) == .fresh,
               let artifact = try? store.read(.shokumukeirekisho, as: ShokumukeirekishoData.self) {
                let age = store.producedAt(.shokumukeirekisho).map { formatAge($0) } ?? "?"
                let by = store.producedBy(.shokumukeirekisho) ?? "unknown"
                print("  Using cached 職務経歴書 data (\(by), \(age))")
                shokumuData = artifact.data
            } else if let legacy: ShokumukeirekishoData = store.loadLegacy(.shokumukeirekisho, expectedHash: inputsHash) {
                print("  Using legacy cached 職務経歴書 data (upgrading to workspace format)")
                try store.write(legacy, kind: .shokumukeirekisho, contentHash: shokumuHash, inputsHash: inputsHash,
                                producedBy: ProducedBy.jpresume())
                shokumuData = legacy
            }
        }

        let needsAI = (generateR && rirekishoData == nil) || (generateS && shokumuData == nil)
        if needsAI {
            let providerInstance = try ProviderFactory.create(provider: provider.rawValue, model: model)
            print("  Using AI provider: \(providerInstance.name)")

            if generateR && rirekishoData == nil {
                print("  Generating 履歴書...")
                rirekishoData = try await Stages.generateRirekisho(
                    repaired: repaired, config: config, era: era,
                    provider: providerInstance, verbose: verbose
                )
            }
            if generateS && shokumuData == nil {
                print("  Generating 職務経歴書...")
                shokumuData = try await Stages.generateShokumukeirekisho(
                    repaired: repaired, config: config, era: era, options: genOptions,
                    provider: providerInstance, verbose: verbose
                )
            }
        }

        return (rirekishoData, shokumuData)
    }

    private func renderOutput(
        rirekisho rirekishoData: RirekishoData?,
        shokumukeirekisho shokumuData: ShokumukeirekishoData?,
        to outputURL: URL
    ) throws {
        let wantMarkdown = format == .markdown || format == .both
        let wantPDF = format == .pdf || format == .both

        if let data = rirekishoData {
            if wantMarkdown {
                let path = outputURL.appendingPathComponent("rirekisho.md")
                try Stages.renderMarkdown(rirekisho: data).write(to: path, atomically: true, encoding: .utf8)
                print("  ✓ \(path.path)")
            }
            if wantPDF {
                let path = outputURL.appendingPathComponent("rirekisho.pdf")
                try Stages.renderPDF(rirekisho: data, to: path)
                print("  ✓ \(path.path)")
            }
        }

        if let data = shokumuData {
            if wantMarkdown {
                let path = outputURL.appendingPathComponent("shokumukeirekisho.md")
                try Stages.renderMarkdown(shokumukeirekisho: data).write(to: path, atomically: true, encoding: .utf8)
                print("  ✓ \(path.path)")
            }
            if wantPDF {
                let path = outputURL.appendingPathComponent("shokumukeirekisho.pdf")
                try Stages.renderPDF(shokumukeirekisho: data, to: path)
                print("  ✓ \(path.path)")
            }
        }
    }

    private func printRepairs(_ repaired: NormalizedResume) {
        for repair in repaired.repairs {
            print("  ⚙ \(repair.field): \(repair.reason)")
        }
        if let derived = repaired.derivedExperience {
            print("  Derived: \(derived.totalSoftwareYears) years total software experience")
            if let ios = derived.iosYears { print("  Derived: \(ios) years iOS experience") }
            if let jp = derived.jpWorkYears { print("  Derived: \(jp) years Japan-based work") }
            if derived.hasInternationalTeamExperience { print("  Derived: international team experience detected") }
        }
    }
}

// MARK: - Enums

enum OutputFormat: String, ExpressibleByArgument, Sendable {
    case markdown, pdf, both
}

enum ProviderChoice: String, ExpressibleByArgument, Sendable {
    case anthropic, openai, openrouter, ollama
    case claudeCli = "claude-cli"
    case codexCli = "codex-cli"
}

enum EraStyle: String, ExpressibleByArgument, Sendable {
    case western, japanese
}

// MARK: - Age formatter (shared by commands)

func formatAge(_ date: Date) -> String {
    let secs = -date.timeIntervalSinceNow
    if secs < 3600 { return "\(Int(secs / 60))m ago" }
    if secs < 86400 { return "\(Int(secs / 3600))h ago" }
    return "\(Int(secs / 86400))d ago"
}
