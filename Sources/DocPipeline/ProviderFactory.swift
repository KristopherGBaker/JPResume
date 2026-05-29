import Foundation
import Shikisha

/// Builds Shikisha `ChatModel` instances for the providers a document pipeline supports.
/// One model per stage — temperature is set at construction because Shikisha models don't
/// take per-call temperature, and each pipeline stage uses its own value.
///
/// `defaultModels` ships sensible defaults and is `public` so a consuming pipeline can
/// read them (e.g. to label runs).
public enum ProviderFactory {
    public static let defaultModels: [String: String] = [
        "anthropic": "claude-sonnet-4-6",
        "openai": "gpt-5.4",
        "openrouter": "gemma4",
        "ollama": "gemma4",
    ]

    /// Resolve a model name for a provider, falling back to the default if none is supplied.
    public static func resolveModel(provider: String, model: String?) -> String {
        model ?? defaultModels[provider] ?? ""
    }

    public static func create(
        provider: String,
        model: String? = nil,
        temperature: Double? = nil
    ) throws -> any ChatModel {
        let resolved = resolveModel(provider: provider, model: model)

        switch provider {
        case "anthropic":
            return AnthropicChatModel(
                config: AnthropicConfig(apiKey: try requireEnv("ANTHROPIC_API_KEY")),
                model: resolved,
                maxTokens: 4096,
                temperature: temperature,
                cacheSystem: true
            )
        case "openai":
            return OpenAIChatModel(
                config: OpenAIConfig(apiKey: try requireEnv("OPENAI_API_KEY")),
                model: resolved,
                temperature: temperature,
                responseFormat: OpenAIResponseFormat.jsonObject()
            )
        case "openrouter":
            return OpenAIChatModel(
                config: OpenAIConfig(
                    apiKey: try requireEnv("OPENROUTER_API_KEY"),
                    baseURL: "https://openrouter.ai/api/v1"
                ),
                model: resolved,
                temperature: temperature,
                responseFormat: OpenAIResponseFormat.jsonObject()
            )
        case "ollama":
            return OllamaChatModel(
                config: OllamaConfig(),
                model: resolved,
                temperature: temperature
            )
        default:
            throw ProviderFactoryError.unknownProvider(provider)
        }
    }

    /// Human-readable label used by CLI logs.
    public static func label(provider: String, model: String?) -> String {
        let resolved = resolveModel(provider: provider, model: model)
        let prettyProvider: String = {
            switch provider {
            case "anthropic": return "Anthropic"
            case "openai": return "OpenAI"
            case "openrouter": return "OpenRouter"
            case "ollama": return "Ollama"
            default: return provider
            }
        }()
        return resolved.isEmpty ? prettyProvider : "\(prettyProvider) (\(resolved))"
    }

    private static func requireEnv(_ key: String) throws -> String {
        guard let value = ProcessInfo.processInfo.environment[key] else {
            throw ProviderFactoryError.missingAPIKey(key)
        }
        return value
    }
}

public enum ProviderFactoryError: Error, LocalizedError {
    case missingAPIKey(String)
    case unknownProvider(String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey(let key):
            return "\(key) environment variable is required"
        case .unknownProvider(let name):
            return "Unknown provider: \(name)"
        }
    }
}
