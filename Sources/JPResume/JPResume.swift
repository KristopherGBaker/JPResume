import ArgumentParser

@main
struct JPResume: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "jpresume",
        abstract: "Convert western-style resumes to Japanese format (履歴書・職務経歴書)",
        version: "0.1.0",
        subcommands: [ConvertCommand.self]
    )
}
