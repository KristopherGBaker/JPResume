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

        if dryRun {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let json = try encoder.encode(western)
            print("\nParsed resume data:")
            print(String(data: json, encoding: .utf8)!)
            print("\nDry run complete. No output generated.")
            return
        }

        // Step 2: Config
        print("\nStep 2: Gathering Japan-specific information...")
        let japanConfig = try ConfigManager.loadOrPrompt(
            path: configURL, western: western, forceReconfigure: reconfigure
        )

        // Step 3: AI
        let generateRirekisho = !shokumukeirekishoOnly
        let generateShokumukeirekisho = !rirekishoOnly

        var rirekishoData: RirekishoData?
        var shokumukeirekishoData: ShokumukeirekishoData?

        let rirekishoCache = outputURL.appendingPathComponent(".rirekisho_cache.json")
        let shokumuCache = outputURL.appendingPathComponent(".shokumukeirekisho_cache.json")

        // Check caches
        if generateRirekisho && !noCache {
            rirekishoData = AICache.load(from: rirekishoCache)
            if rirekishoData != nil {
                print("\nStep 3: Using cached 履歴書 data")
            }
        }
        if generateShokumukeirekisho && !noCache {
            shokumukeirekishoData = AICache.load(from: shokumuCache)
            if shokumukeirekishoData != nil {
                print("  Using cached 職務経歴書 data")
            }
        }

        let needsAI = (generateRirekisho && rirekishoData == nil)
            || (generateShokumukeirekisho && shokumukeirekishoData == nil)

        if needsAI {
            print("\nStep 3: Translating and adapting with AI...")
            let ai = try ResumeAI(provider: provider.rawValue, model: model, verbose: verbose)

            if generateRirekisho && rirekishoData == nil {
                print("  Generating 履歴書...")
                rirekishoData = try await ai.generateRirekisho(
                    western: western, config: japanConfig, era: era
                )
                try AICache.save(rirekishoData!, to: rirekishoCache)
            }

            if generateShokumukeirekisho && shokumukeirekishoData == nil {
                print("  Generating 職務経歴書...")
                shokumukeirekishoData = try await ai.generateShokumukeirekisho(
                    western: western, config: japanConfig, era: era
                )
                try AICache.save(shokumukeirekishoData!, to: shokumuCache)
            }
        }

        // Step 4: Render
        print("\nStep 4: Generating output files...")
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

        print("\nDone!")
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
