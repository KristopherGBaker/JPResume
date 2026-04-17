import ArgumentParser
import Foundation

struct RepairCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "repair",
        abstract: "Run consistency checker on normalized resume (reads normalized.json, writes repaired.json)"
    )

    @Option(help: "Workspace directory (default: ./.jpresume)")
    var workspace: String?

    func run() async throws {
        let workspaceURL = workspace.map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".jpresume")
        let store = ArtifactStore(root: workspaceURL)

        let inputsArtifact = try store.read(.inputs, as: InputsData.self)
        let normalizedArtifact = try store.read(.normalized, as: NormalizedResume.self)
        let inputsHash = inputsArtifact.data.markdownHash

        print("Running consistency check and repair...")
        let repaired = Stages.repair(normalizedArtifact.data)

        for note in repaired.repairs {
            print("  ⚙ \(note.field): \(note.reason)")
        }
        if let derived = repaired.derivedExperience {
            print("  Derived: \(derived.totalSoftwareYears) years total software experience")
            if let ios = derived.iosYears { print("  Derived: \(ios) years iOS experience") }
            if let jp = derived.jpWorkYears { print("  Derived: \(jp) years Japan-based work") }
            if derived.hasInternationalTeamExperience {
                print("  Derived: international team experience detected")
            }
        }

        let by = ProducedBy.jpresume()
        try store.write(repaired, kind: .repaired, contentHash: inputsHash, inputsHash: inputsHash, producedBy: by)
        print("  ✓ \(workspaceURL.path)/repaired.json")
    }
}
