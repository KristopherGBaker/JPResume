import ArgumentParser
import Foundation

struct ConvertCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "convert",
        abstract: "Convert a western resume to Japanese format"
    )

    @Argument(help: "Path to western-style markdown resume")
    var input: String

    @Option(name: [.short, .long], help: "Output directory (default: same as input)")
    var outputDir: String?

    @Option(name: [.short, .long], help: "Path to YAML config file")
    var config: String?

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

        // Step 1: Parse
        print("\nStep 1: Parsing western resume...")
        let text = try String(contentsOf: inputURL, encoding: .utf8)
        let western = MarkdownParser.parse(text)
        print("  Found: \(western.experience.count) work entries, "
              + "\(western.education.count) education entries, "
              + "\(western.skills.count) skills")

        // Step 2: Config
        print("\nStep 2: Gathering Japan-specific information...")
        let japanConfig = try ConfigManager.loadOrPrompt(
            path: configURL, western: western, forceReconfigure: reconfigure
        )

        // Compute content hash for all caches (markdown + config + schema version)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let configData = try? encoder.encode(japanConfig)
        let cacheHash = AICache.contentHash(markdownContent: text, configData: configData)

        // Step 3: Normalize
        print("\nStep 3: Normalizing resume...")
        let normalizedCache = outputURL.appendingPathComponent(".normalized_cache.json")
        var normalized: NormalizedResume

        if !noCache, let cached: NormalizedResume = AICache.load(from: normalizedCache, expectedHash: cacheHash) {
            print("  Using cached normalized resume")
            normalized = cached
        } else {
            let providerInstance = try ProviderFactory.create(provider: provider.rawValue, model: model)
            print("  Using AI provider: \(providerInstance.name)")
            let normalizer = ResumeNormalizer(provider: providerInstance, verbose: verbose)
            normalized = try await normalizer.normalize(western: western, config: japanConfig)
            try AICache.save(normalized, to: normalizedCache, contentHash: cacheHash)
        }

        // Step 4: Validate
        print("\nStep 4: Validating...")
        let validation = ResumeValidator.validate(normalized)
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

        if dryRun {
            let prettyEncoder = JSONEncoder()
            prettyEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]

            print("\nParsed resume (WesternResume):")
            let westernJSON = try prettyEncoder.encode(western)
            print(String(data: westernJSON, encoding: .utf8)!)

            print("\nNormalized resume (NormalizedResume):")
            let normalizedJSON = try prettyEncoder.encode(normalized)
            print(String(data: normalizedJSON, encoding: .utf8)!)

            print("\nDry run complete. No output generated.")
            return
        }

        // Steps 5 & 6: Adapt and Render
        let (rirekishoData, shokumukeirekishoData) = try await adapt(
            normalized: normalized, config: japanConfig, outputURL: outputURL, cacheHash: cacheHash
        )
        try render(rirekisho: rirekishoData, shokumukeirekisho: shokumukeirekishoData, to: outputURL)

        print("\nDone!")
    }
}

// MARK: - Private helpers

extension ConvertCommand {
    private func adapt(
        normalized: NormalizedResume,
        config: JapanConfig,
        outputURL: URL,
        cacheHash: String
    ) async throws -> (RirekishoData?, ShokumukeirekishoData?) {
        let generateRirekisho = !shokumukeirekishoOnly
        let generateShokumukeirekisho = !rirekishoOnly

        var rirekishoData: RirekishoData?
        var shokumukeirekishoData: ShokumukeirekishoData?

        let rirekishoCache = outputURL.appendingPathComponent(".rirekisho_cache.json")
        let shokumuCache = outputURL.appendingPathComponent(".shokumukeirekisho_cache.json")

        if generateRirekisho && !noCache {
            rirekishoData = AICache.load(from: rirekishoCache, expectedHash: cacheHash)
            if rirekishoData != nil { print("\nStep 5: Using cached 履歴書 data") }
        }
        if generateShokumukeirekisho && !noCache {
            shokumukeirekishoData = AICache.load(from: shokumuCache, expectedHash: cacheHash)
            if shokumukeirekishoData != nil { print("  Using cached 職務経歴書 data") }
        }

        let needsAI = (generateRirekisho && rirekishoData == nil)
            || (generateShokumukeirekisho && shokumukeirekishoData == nil)

        if needsAI {
            print("\nStep 5: Translating and adapting with AI...")
            let ai = try ResumeAI(provider: provider.rawValue, model: model, verbose: verbose)

            if generateRirekisho && rirekishoData == nil {
                print("  Generating 履歴書...")
                rirekishoData = try await ai.generateRirekisho(
                    normalized: normalized, config: config, era: era
                )
                try AICache.save(rirekishoData!, to: rirekishoCache, contentHash: cacheHash)
            }

            if generateShokumukeirekisho && shokumukeirekishoData == nil {
                print("  Generating 職務経歴書...")
                shokumukeirekishoData = try await ai.generateShokumukeirekisho(
                    normalized: normalized, config: config, era: era
                )
                try AICache.save(shokumukeirekishoData!, to: shokumuCache, contentHash: cacheHash)
            }
        }

        return (rirekishoData, shokumukeirekishoData)
    }

    private func render(
        rirekisho rirekishoData: RirekishoData?,
        shokumukeirekisho shokumukeirekishoData: ShokumukeirekishoData?,
        to outputURL: URL
    ) throws {
        print("\nStep 6: Generating output files...")
        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

        let wantMarkdown = format == .markdown || format == .both
        let wantPDF = format == .pdf || format == .both

        if let data = rirekishoData {
            if wantMarkdown {
                let md = MarkdownRenderer.renderRirekisho(data)
                let path = outputURL.appendingPathComponent("rirekisho.md")
                try md.write(to: path, atomically: true, encoding: .utf8)
                print("  ✓ \(path.path)")
            }
            if wantPDF {
                let path = outputURL.appendingPathComponent("rirekisho.pdf")
                try RirekishoPDFRenderer.render(data: data, to: path)
                print("  ✓ \(path.path)")
            }
        }

        if let data = shokumukeirekishoData {
            if wantMarkdown {
                let md = MarkdownRenderer.renderShokumukeirekisho(data)
                let path = outputURL.appendingPathComponent("shokumukeirekisho.md")
                try md.write(to: path, atomically: true, encoding: .utf8)
                print("  ✓ \(path.path)")
            }
            if wantPDF {
                let path = outputURL.appendingPathComponent("shokumukeirekisho.pdf")
                try ShokumukeirekishoPDFRenderer.render(data: data, to: path)
                print("  ✓ \(path.path)")
            }
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
