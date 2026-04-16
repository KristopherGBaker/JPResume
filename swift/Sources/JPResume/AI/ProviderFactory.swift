import Foundation

enum ProviderFactory {
    static let defaultModels: [String: String] = [
        "anthropic": "claude-sonnet-4-6",
        "openai": "gpt-5.4",
        "openrouter": "gemma4",
        "ollama": "gemma4",
        "claude-cli": "",
        "codex-cli": "",
    ]

    static func create(provider: String, model: String? = nil) throws -> any AIProvider {
        let resolvedModel = model ?? defaultModels[provider] ?? ""

        switch provider {
        case "anthropic":
            return try AnthropicProvider(model: resolvedModel)
        case "openai":
            return try OpenAIProvider(model: resolvedModel)
        case "openrouter":
            return try OpenRouterProvider(model: resolvedModel)
        case "ollama":
            return OllamaProvider(model: resolvedModel)
        case "claude-cli":
            return ClaudeCLIProvider(model: resolvedModel)
        case "codex-cli":
            return CodexCLIProvider(model: resolvedModel)
        default:
            throw AIProviderError.requestFailed("Unknown provider: \(provider)")
        }
    }
}
