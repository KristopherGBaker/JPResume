import Foundation

struct AnthropicProvider: AIProvider, Sendable {
    let model: String
    let apiKey: String

    var name: String { "Anthropic (\(model))" }

    init(model: String) throws {
        guard let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] else {
            throw AIProviderError.missingAPIKey("ANTHROPIC_API_KEY")
        }
        self.model = model
        self.apiKey = key
    }

    func chat(system: String, user: String, temperature: Double) async throws -> String {
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "temperature": temperature,
            "system": [
                ["type": "text", "text": system,
                 "cache_control": ["type": "ephemeral"]],
            ],
            "messages": [
                ["role": "user", "content": user],
            ],
        ]
        let json = try await HTTPJSONClient.postJSON(
            url: URL(string: "https://api.anthropic.com/v1/messages")!,
            headers: [
                "x-api-key": apiKey,
                "anthropic-version": "2023-06-01",
            ],
            body: body
        )
        let content = json["content"] as? [[String: Any]]
        guard let text = content?.first?["text"] as? String else {
            throw AIProviderError.invalidResponse("No text in response")
        }
        return text
    }
}
