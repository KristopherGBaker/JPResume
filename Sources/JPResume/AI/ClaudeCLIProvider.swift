import Foundation

struct ClaudeCLIProvider: AIProvider, Sendable {
    let model: String

    var name: String { "Claude CLI" }

    func chat(system: String, user: String, temperature: Double) async throws -> String {
        let prompt = "\(system)\n\n\(user)"
        var args = ["-p", prompt]
        if !model.isEmpty {
            args += ["--model", model]
        }
        return try await runCLI(executable: "claude", arguments: args)
    }
}

struct CodexCLIProvider: AIProvider, Sendable {
    let model: String

    var name: String { "Codex CLI" }

    func chat(system: String, user: String, temperature: Double) async throws -> String {
        let prompt = "\(system)\n\n\(user)"
        var args = ["exec", "--skip-git-repo-check", prompt]
        if !model.isEmpty {
            args += ["--model", model]
        }
        return try await runCLI(executable: "codex", arguments: args)
    }
}

private func runCLI(executable: String, arguments: [String]) async throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [executable] + arguments

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    process.standardInput = FileHandle.nullDevice

    try process.run()
    process.waitUntilExit()

    let outData = stdout.fileHandleForReading.readDataToEndOfFile()
    let errData = stderr.fileHandleForReading.readDataToEndOfFile()

    guard process.terminationStatus == 0 else {
        let errStr = String(data: errData, encoding: .utf8)
            ?? String(data: outData, encoding: .utf8)
            ?? "Unknown error"
        throw AIProviderError.requestFailed("\(executable) failed (exit \(process.terminationStatus)): \(errStr)")
    }

    return String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}
