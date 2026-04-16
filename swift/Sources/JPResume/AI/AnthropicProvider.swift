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
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

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
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AIProviderError.requestFailed(String(data: data, encoding: .utf8) ?? "Unknown error")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let content = json?["content"] as? [[String: Any]]
        guard let text = content?.first?["text"] as? String else {
            throw AIProviderError.invalidResponse("No text in response")
        }
        return text
    }
}
