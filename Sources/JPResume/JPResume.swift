import ArgumentParser

@main
struct JPResume: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "jpresume",
        abstract: "Convert western-style resumes to Japanese format (履歴書・職務経歴書)",
        version: "0.2.0",
        subcommands: [
            ConvertCommand.self,
            ParseCommand.self,
            NormalizeCommand.self,
            ValidateCommand.self,
            RepairCommand.self,
            GenerateCommand.self,
            RenderCommand.self,
            InspectCommand.self
        ]
    )
}
