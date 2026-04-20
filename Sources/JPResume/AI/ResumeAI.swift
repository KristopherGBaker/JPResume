import Foundation

struct ResumeAI: Sendable {
    let provider: any AIProvider
    let verbose: Bool

    init(provider: String, model: String?, verbose: Bool) throws {
        self.provider = try ProviderFactory.create(provider: provider, model: model)
        self.verbose = verbose
        print("  Using AI provider: \(self.provider.name)")
    }

    init(provider: any AIProvider, verbose: Bool) {
        self.provider = provider
        self.verbose = verbose
    }

    func generateRirekisho(
        normalized: NormalizedResume,
        config: JapanConfig,
        era: EraStyle,
        targetContext: TargetCompanyContext? = nil
    ) async throws -> RirekishoData {
        let eraStyle = era == .japanese ? "Japanese era (令和/平成)" : "western year"
        let eraExample = era == .japanese ? "令和2年4月" : "2020年4月"

        let system = SystemPrompts.rirekisho(eraStyle: eraStyle, eraExample: eraExample,
                                              targetContext: targetContext)
        let user = try PromptPayload.adapt(normalized: normalized, config: config, targetContext: targetContext)

        let response = try await call(system: system, user: user)
        let json = try JSONExtractor.extract(from: response)
        return try JSONDecoder().decode(RirekishoData.self, from: json)
    }

    func generateShokumukeirekisho(
        normalized: NormalizedResume,
        config: JapanConfig,
        era: EraStyle,
        options: GenerationOptions = GenerationOptions(),
        targetContext: TargetCompanyContext? = nil
    ) async throws -> ShokumukeirekishoData {
        let eraStyle = era == .japanese ? "Japanese era (令和/平成)" : "western year"

        let system = SystemPrompts.shokumukeirekisho(eraStyle: eraStyle, options: options,
                                                      targetContext: targetContext)
        let user = try PromptPayload.adapt(normalized: normalized, config: config, targetContext: targetContext)

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
}
