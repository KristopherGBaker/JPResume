import Foundation

struct ResumeAI: Sendable {
    let provider: any AIProvider
    let verbose: Bool

    init(provider: String, model: String?, verbose: Bool) throws {
        self.provider = try ProviderFactory.create(provider: provider, model: model)
        self.verbose = verbose
        print("  Using AI provider: \(self.provider.name)")
    }

    func generateRirekisho(
        normalized: NormalizedResume,
        config: JapanConfig,
        era: EraStyle
    ) async throws -> RirekishoData {
        let eraStyle = era == .japanese ? "Japanese era (令和/平成)" : "western year"
        let eraExample = era == .japanese ? "令和2年4月" : "2020年4月"

        let system = SystemPrompts.rirekisho(eraStyle: eraStyle, eraExample: eraExample)
        let user = try buildUserMessage(normalized: normalized, config: config)

        let response = try await call(system: system, user: user)
        let json = try JSONExtractor.extract(from: response)
        return try JSONDecoder().decode(RirekishoData.self, from: json)
    }

    func generateShokumukeirekisho(
        normalized: NormalizedResume,
        config: JapanConfig,
        era: EraStyle
    ) async throws -> ShokumukeirekishoData {
        let eraStyle = era == .japanese ? "Japanese era (令和/平成)" : "western year"

        let system = SystemPrompts.shokumukeirekisho(eraStyle: eraStyle)
        let user = try buildUserMessage(normalized: normalized, config: config)

        let response = try await call(system: system, user: user)
        let json = try JSONExtractor.extract(from: response)
        return try JSONDecoder().decode(ShokumukeirekishoData.self, from: json)
    }

    private func call(system: String, user: String) async throws -> String {
        if verbose {
            print("\n  System prompt (\(system.count) chars)")
            print("  User message (\(user.count) chars)")
        }
        let response = try await provider.chat(system: system, user: user)
        if verbose {
            print("  Response (\(response.count) chars)")
        }
        return response
    }

    private func buildUserMessage(normalized: NormalizedResume, config: JapanConfig) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let normalizedJSON = try encoder.encode(normalized)
        let configJSON = try encoder.encode(config)

        let today = ISO8601DateFormatter().string(from: Date()).prefix(10)
        return """
        {
          "normalized_resume": \(String(data: normalizedJSON, encoding: .utf8)!),
          "japan_config": \(String(data: configJSON, encoding: .utf8)!),
          "today": "\(today)"
        }
        """
    }
}
