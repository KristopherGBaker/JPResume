import ArgumentParser
import Foundation

struct RenderCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "render",
        abstract: "Render Japanese resume JSON to markdown and/or PDF"
    )

    @Argument(help: "What to render: rirekisho | shokumukeirekisho | both")
    var target: RenderTarget = .both

    @Option(help: "Workspace directory (default: ./.jpresume)")
    var workspace: String?

    @Option(help: "Output directory (default: workspace parent directory)")
    var outputDir: String?

    @Option(help: "Output format")
    var format: OutputFormat = .both

    func run() async throws {
        let workspaceURL = workspace.map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".jpresume")
        let outputURL = outputDir.map { URL(fileURLWithPath: $0) }
            ?? workspaceURL.deletingLastPathComponent()
        let store = ArtifactStore(root: workspaceURL)

        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
        print("Rendering to \(outputURL.path)...")

        let wantMarkdown = format == .markdown || format == .both
        let wantPDF = format == .pdf || format == .both

        if target == .rirekisho || target == .both {
            let artifact = try store.read(.rirekisho, as: RirekishoData.self)
            let data = artifact.data
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

        if target == .shokumukeirekisho || target == .both {
            let artifact = try store.read(.shokumukeirekisho, as: ShokumukeirekishoData.self)
            let data = artifact.data
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
}

enum RenderTarget: String, ExpressibleByArgument, Sendable {
    case rirekisho, shokumukeirekisho, both
}
