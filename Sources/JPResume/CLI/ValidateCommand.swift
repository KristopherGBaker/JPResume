import ArgumentParser
import Foundation

struct ValidateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "validate",
        abstract: "Validate normalized or repaired resume (writes validation.json)"
    )

    @Option(help: "Workspace directory (default: ./.jpresume)")
    var workspace: String?

    @Option(help: "Which artifact to validate: normalized or repaired (default: repaired if present)")
    var on: ValidateOn?

    @Flag(help: "Treat warnings as errors")
    var strict = false

    func run() async throws {
        let workspaceURL = workspace.map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".jpresume")
        let store = ArtifactStore(root: workspaceURL)

        let inputsArtifact = try store.read(.inputs, as: InputsData.self)
        let inputsHash = inputsArtifact.data.markdownHash

        let resume: NormalizedResume
        let source: ArtifactKind

        let useRepaired: Bool
        if let explicit = on {
            useRepaired = explicit == .repaired
        } else {
            useRepaired = store.status(.repaired) != .missing
        }

        if useRepaired {
            let artifact = try store.read(.repaired, as: NormalizedResume.self)
            resume = artifact.data
            source = .repaired
        } else {
            let artifact = try store.read(.normalized, as: NormalizedResume.self)
            resume = artifact.data
            source = .normalized
        }

        print("Validating \(source.rawValue) resume...")
        let validation = Stages.validate(resume)

        if validation.hasIssues {
            ResumeValidator.printResult(validation)
            if strict && !validation.isValid {
                throw ValidationError("Validation errors found. Fix and re-run, or omit --strict.")
            }
        } else {
            if let years = validation.totalYearsExperience {
                print("  ✓ Valid — \(String(format: "%.1f", years)) years experience")
            } else {
                print("  ✓ Valid")
            }
        }

        let by = ProducedBy.jpresume()
        let warnings = validation.issues.map { $0.asArtifactWarning }
        try store.write(validation, kind: .validation, contentHash: inputsHash, inputsHash: inputsHash,
                        producedBy: by, warnings: warnings)
        print("  ✓ \(workspaceURL.path)/validation.json")
    }
}

enum ValidateOn: String, ExpressibleByArgument, Sendable {
    case normalized, repaired
}

struct ValidationError: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { description = message }
}
