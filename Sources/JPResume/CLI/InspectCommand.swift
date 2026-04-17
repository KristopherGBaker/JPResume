import ArgumentParser
import Foundation

struct InspectCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "inspect",
        abstract: "Inspect workspace status or a specific artifact"
    )

    @Argument(help: "Artifact to inspect: inputs | parsed | normalized | repaired | validation | rirekisho | shokumukeirekisho")
    var artifact: String?

    @Option(help: "Workspace directory (default: ./.jpresume)")
    var workspace: String?

    @Flag(help: "Print raw artifact JSON instead of a summary")
    var json = false

    func run() async throws {
        let workspaceURL = workspace.map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".jpresume")
        let store = ArtifactStore(root: workspaceURL)

        if let artifactName = artifact {
            guard let kind = ArtifactKind(rawValue: artifactName) else {
                print("Unknown artifact '\(artifactName)'. Valid: \(ArtifactKind.allCases.map(\.rawValue).joined(separator: ", "))")
                throw ExitCode.failure
            }
            try inspectArtifact(kind: kind, store: store, workspaceURL: workspaceURL)
        } else {
            inspectWorkspace(store: store, workspaceURL: workspaceURL)
        }
    }

    private func inspectArtifact(kind: ArtifactKind, store: ArtifactStore, workspaceURL: URL) throws {
        let url = workspaceURL.appendingPathComponent(kind.filename)
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("Artifact '\(kind.filename)' not found in workspace: \(workspaceURL.path)")
            throw ExitCode.failure
        }

        if json {
            let raw = try String(contentsOf: url, encoding: .utf8)
            print(raw)
            return
        }

        // Banner for derived artifacts
        if kind.role == "derived" {
            print("┌─ Note: \(kind.filename) is a derived artifact.")
            print("│  Edits will not stick — run 'jpresume \(derivedCommand(kind))' to regenerate.")
            print("└──────────────────────────────────────────────────────────")
        }

        let rawData = try Data(contentsOf: url)
        printArtifactSummary(kind: kind, rawData: rawData)
    }

    private func printArtifactSummary(kind: ArtifactKind, rawData: Data) {
        switch kind {
        case .inputs:         printInputsSummary(rawData)
        case .parsed:         printParsedSummary(rawData)
        case .normalized:     printNormalizedSummary(rawData)
        case .repaired:       printRepairedSummary(rawData)
        case .validation:     printValidationSummary(rawData)
        case .rirekisho:      printRirekishoSummary(rawData)
        case .shokumukeirekisho: printShokumukeirekishoSummary(rawData)
        }
    }

    /// Decode an artifact of the given type or print a clear failure message and return nil.
    private func decodeArtifact<T: Codable>(_ rawData: Data, as type: T.Type, kindName: String) -> Artifact<T>? {
        do {
            return try JSONDecoder().decode(Artifact<T>.self, from: rawData)
        } catch {
            print("⚠️  \(kindName) artifact exists but could not be parsed: \(error)")
            return nil
        }
    }

    private func printInputsSummary(_ rawData: Data) {
        guard let artifact = decodeArtifact(rawData, as: InputsData.self, kindName: "inputs") else { return }
        print("Source: \(artifact.data.sourcePath)")
        print("Hash:   \(artifact.data.markdownHash.prefix(16))…")
        print("Config: \(artifact.data.config.nameKanji ?? "(no name)")")
    }

    private func printParsedSummary(_ rawData: Data) {
        guard let artifact = decodeArtifact(rawData, as: WesternResume.self, kindName: "parsed") else { return }
        let w = artifact.data
        print("Name:       \(w.name ?? "(none)")")
        print("Experience: \(w.experience.count) entries")
        print("Education:  \(w.education.count) entries")
        print("Skills:     \(w.skills.count)")
    }

    private func printNormalizedSummary(_ rawData: Data) {
        guard let artifact = decodeArtifact(rawData, as: NormalizedResume.self, kindName: "normalized") else { return }
        let n = artifact.data
        print("Name:       \(n.name ?? "(none)")")
        print("Experience: \(n.experience.count) entries")
        for (i, e) in n.experience.enumerated() {
            let start = e.startDate.map { "\($0.year)/\(String(format: "%02d", $0.month ?? 1))" } ?? "?"
            let end = e.isCurrent ? "present" : (e.endDate.map { "\($0.year)/\(String(format: "%02d", $0.month ?? 12))" } ?? "?")
            print("  [\(i+1)] \(e.company) (\(start) – \(end))")
        }
        print("Skills:     \(n.skillCategories.count) categories")
        if !n.normalizerNotes.isEmpty {
            print("Notes:")
            for note in n.normalizerNotes { print("  - \(note)") }
        }
    }

    private func printRepairedSummary(_ rawData: Data) {
        guard let artifact = decodeArtifact(rawData, as: NormalizedResume.self, kindName: "repaired") else { return }
        let n = artifact.data
        print("Experience: \(n.experience.count) entries")
        if !n.repairs.isEmpty {
            print("Repairs applied:")
            for r in n.repairs { print("  ⚙ \(r.field): \(r.reason)") }
        }
        if let derived = n.derivedExperience {
            print("Derived experience:")
            print("  Total software: \(derived.totalSoftwareYears) years")
            if let ios = derived.iosYears { print("  iOS: \(ios) years") }
            if let jp = derived.jpWorkYears { print("  Japan-based: \(jp) years") }
            if derived.hasInternationalTeamExperience { print("  International team: yes") }
        }
    }

    private func printValidationSummary(_ rawData: Data) {
        guard let artifact = decodeArtifact(rawData, as: ValidationResult.self, kindName: "validation") else { return }
        let v = artifact.data
        print("Issues: \(v.errors.count) error(s), \(v.warnings.count) warning(s), \(v.infos.count) info(s)")
        if let years = v.totalYearsExperience {
            print("Total experience: \(String(format: "%.1f", years)) years")
        }
        for issue in v.issues {
            let icon: String
            switch issue.severity {
            case .info:    icon = "ℹ️ "
            case .warning: icon = "⚠️ "
            case .error:   icon = "✘ "
            }
            print("  \(icon) \(issue.field): \(issue.message)")
        }
    }

    private func printRirekishoSummary(_ rawData: Data) {
        guard let artifact = decodeArtifact(rawData, as: RirekishoData.self, kindName: "rirekisho") else { return }
        let r = artifact.data
        print("Name:        \(r.nameKanji)")
        print("Address:     \(r.address ?? "(none)")")
        print("Produced by: \(artifact.producedBy)")
        print("Produced at: \(artifact.producedAt)")
    }

    private func printShokumukeirekishoSummary(_ rawData: Data) {
        guard let artifact = decodeArtifact(rawData, as: ShokumukeirekishoData.self, kindName: "shokumukeirekisho") else { return }
        let s = artifact.data
        print("Name:         \(s.name)")
        print("Work entries: \(s.workDetails.count)")
        print("Produced by:  \(artifact.producedBy)")
        print("Produced at:  \(artifact.producedAt)")
    }

    private func inspectWorkspace(store: ArtifactStore, workspaceURL: URL) {
        print("Workspace: \(workspaceURL.path)")
        print("")

        // Try to load source info from inputs.json
        if let artifact = try? store.read(.inputs, as: InputsData.self) {
            print("Source:  \(artifact.data.sourcePath)")
            print("Hash:    \(artifact.data.markdownHash.prefix(16))…")
        }

        print("")
        print("Artifact                  Status     Produced by                     Age")
        print("─────────────────────────────────────────────────────────────────────────────")

        var issues: [(String, String)] = []
        for kind in ArtifactKind.allCases {
            let s = store.status(kind)
            let byStr = store.producedBy(kind) ?? ""
            let ageStr = store.producedAt(kind).map { formatAge($0) } ?? ""
            let name = kind.filename.padding(toLength: 25, withPad: " ", startingAt: 0)
            let status = statusLabel(s).padding(toLength: 10, withPad: " ", startingAt: 0)
            let by = byStr.prefix(30).description.padding(toLength: 32, withPad: " ", startingAt: 0)
            print("\(name) \(status) \(by) \(ageStr)")
            if let reason = statusReason(s) {
                issues.append((kind.filename, reason))
            }
        }

        if !issues.isEmpty {
            print("")
            print("Issues:")
            for (name, reason) in issues {
                print("  \(name): \(reason)")
            }
        }

        // Warning summary
        let summaries = store.list()
        let totalInfos = summaries.reduce(0) { $0 + $1.infoCount }
        let totalWarnings = summaries.reduce(0) { $0 + $1.warningCount }
        let totalErrors = summaries.reduce(0) { $0 + $1.errorCount }
        if totalErrors > 0 || totalWarnings > 0 || totalInfos > 0 {
            print("")
            print("Warnings: \(totalErrors) error(s), \(totalWarnings) warning(s), \(totalInfos) info(s) across artifacts")
        }
    }

    private func statusLabel(_ status: ArtifactStatus) -> String {
        switch status {
        case .fresh:   return "✓ fresh"
        case .stale:   return "~ stale"
        case .missing: return "  missing"
        case .invalid: return "✘ invalid"
        }
    }

    private func statusReason(_ status: ArtifactStatus) -> String? {
        switch status {
        case .fresh, .missing:      return nil
        case .stale(let reason):    return "stale — \(reason)"
        case .invalid(let reason):  return "invalid — \(reason)"
        }
    }

    private func derivedCommand(_ kind: ArtifactKind) -> String {
        switch kind {
        case .repaired:   return "repair"
        case .validation: return "validate"
        default:          return kind.rawValue
        }
    }
}
