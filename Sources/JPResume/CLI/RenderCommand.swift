import DocPipeline
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
            let photo = wantPDF ? resolvePhoto(data: data, workspace: workspaceURL, store: store) : nil
            if wantMarkdown {
                let path = outputURL.appendingPathComponent("rirekisho.md")
                try Stages.renderMarkdown(rirekisho: data).write(to: path, atomically: true, encoding: .utf8)
                print("  ✓ \(path.path)")
            }
            if wantPDF {
                let path = outputURL.appendingPathComponent("rirekisho.pdf")
                try Stages.renderPDF(rirekisho: data, to: path, photo: photo)
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

    /// The 写真 path comes from `rirekisho.json` when it has one, otherwise from the
    /// config snapshot in `inputs.json` — so a workspace generated before `photo_path`
    /// was set picks the photo up on a plain re-render.
    private func resolvePhoto(data: RirekishoData, workspace: URL,
                              store: ArtifactStore) -> URL? {
        let configured = (try? store.read(.inputs, as: InputsData.self))?.data.config.photoPath
        guard let path = data.photoPath ?? configured else { return nil }

        let bases = [workspace.deletingLastPathComponent(), workspace,
                     URL(fileURLWithPath: FileManager.default.currentDirectoryPath)]
        guard let url = RirekishoPhoto.resolve(path, relativeTo: bases) else {
            print("  ! photo_path '\(path)' not found — leaving the 写真 box empty")
            return nil
        }
        let ext = url.pathExtension.lowercased()
        guard RirekishoPhoto.supportedExtensions.contains(ext) else {
            print("  ! photo_path '\(path)' is not a supported image (\(RirekishoPhoto.supportedExtensions.sorted().joined(separator: ", ")))")
            return nil
        }
        guard RirekishoPhoto.load(url) != nil else {
            print("  ! photo_path '\(path)' could not be decoded — leaving the 写真 box empty")
            return nil
        }
        return url
    }
}

enum RenderTarget: String, ExpressibleByArgument, Sendable {
    case rirekisho, shokumukeirekisho, both
}
