import ArgumentParser
import Foundation

struct ParseCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "parse",
        abstract: "Parse a resume (.md, .docx, or .pdf) into structured JSON (parsed.json, inputs.json)"
    )

    @Argument(help: "Path to western-style resume (.md, .docx, or .pdf)")
    var input: String

    @Option(help: "Workspace directory (default: <input-dir>/.jpresume)")
    var workspace: String?

    @Option(name: [.short, .long], help: "Path to YAML config file")
    var config: String?

    @Flag(help: "Re-prompt for all Japan-specific fields")
    var reconfigure = false

    func run() async throws {
        let inputURL = URL(fileURLWithPath: input)
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            print("Error: Input file not found: \(input)")
            throw ExitCode.failure
        }

        let inputDir = inputURL.deletingLastPathComponent()
        let configURL = config.map { URL(fileURLWithPath: $0) }
            ?? inputDir.appendingPathComponent("jpresume_config.yaml")
        let workspaceURL = workspace.map { URL(fileURLWithPath: $0) }
            ?? inputDir.appendingPathComponent(".jpresume")
        let store = ArtifactStore(root: workspaceURL)

        print("Parsing \(inputURL.lastPathComponent)...")
        let sourceKind = ResumeSourceKind.from(url: inputURL)
        let text = try await ResumeInputReader.read(from: inputURL)
        let preprocessed = ResumeTextPreprocessor.preprocess(text, sourceKind: sourceKind)
        let western = Stages.parse(text: preprocessed.cleanedText, sourceKind: sourceKind)
        print("  Found: \(western.experience.count) work entries, "
              + "\(western.education.count) education entries, "
              + "\(western.skills.count) skills")

        let japanConfig = try ConfigManager.loadOrPrompt(
            path: configURL, western: western, forceReconfigure: reconfigure
        )
        let configData = try? JSONCoders.sorted.encode(japanConfig)
        let inputsHash = ArtifactHashes.inputs(markdownContent: preprocessed.cleanedText, configData: configData)
        let by = ProducedBy.jpresume()

        let inputsData = InputsData(
            sourcePath: inputURL.path,
            markdownHash: inputsHash,
            config: japanConfig,
            sourceKind: sourceKind,
            sourceText: text,
            cleanedText: preprocessed.cleanedText,
            preprocessingNotes: preprocessed.notes
        )
        try store.write(inputsData, kind: .inputs, contentHash: inputsHash, inputsHash: inputsHash, producedBy: by)
        try store.write(western, kind: .parsed, contentHash: inputsHash, inputsHash: inputsHash, producedBy: by)

        print("  ✓ \(workspaceURL.path)/inputs.json")
        print("  ✓ \(workspaceURL.path)/parsed.json")
    }
}
