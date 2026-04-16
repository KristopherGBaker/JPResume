import Foundation

struct OpenRouterProvider: AIProvider, Sendable {
    private let inner: OpenAIProvider

    var name: String { "OpenRouter (\(inner.model))" }

    init(model: String) throws {
        self.inner = try OpenAIProvider(
            model: model,
            baseURL: "https://openrouter.ai/api/v1",
            apiKeyEnv: "OPENROUTER_API_KEY",
            providerName: "OpenRouter"
        )
    }

    func chat(system: String, user: String, temperature: Double) async throws -> String {
        try await inner.chat(system: system, user: user, temperature: temperature)
    }
}
