import Foundation
import Shikisha

struct ResumeAI: Sendable {
    let model: any ChatModel
    let verbose: Bool

    init(provider: String, modelName: String?, verbose: Bool) throws {
        self.model = try ProviderFactory.create(provider: provider, model: modelName, temperature: 0.3)
        self.verbose = verbose
        print("  Using AI provider: \(ProviderFactory.label(provider: provider, model: modelName))")
    }

    init(model: any ChatModel, verbose: Bool) {
        self.model = model
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
        return try await invokeStructured(system: system, user: user)
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
        return try await invokeStructured(system: system, user: user)
    }

    private func invokeStructured<T: Decodable & Sendable>(system: String, user: String) async throws -> T {
        if verbose {
            print("\n  System prompt (\(system.count) chars)")
            print("  User message (\(user.count) chars)")
        }
        let messages: [any Message] = [SystemMessage(content: system), HumanMessage(content: user)]
        return try await ChatModelDecoder.decode(T.self, model: model, messages: messages)
    }
}
