import Foundation

struct OpenAIProvider: AIProvider, Sendable {
    let model: String
    let baseURL: String
    let apiKey: String
    private let providerName: String

    var name: String { "\(providerName) (\(model))" }

    init(model: String, baseURL: String = "https://api.openai.com/v1",
         apiKeyEnv: String = "OPENAI_API_KEY", providerName: String = "OpenAI") throws {
        guard let key = ProcessInfo.processInfo.environment[apiKeyEnv] else {
            throw AIProviderError.missingAPIKey(apiKeyEnv)
        }
        self.model = model
        self.baseURL = baseURL
        self.apiKey = key
        self.providerName = providerName
    }

    func chat(system: String, user: String, temperature: Double) async throws -> String {
        let body: [String: Any] = [
            "model": model,
            "temperature": temperature,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ]
        let json = try await HTTPJSONClient.postJSON(
            url: URL(string: "\(baseURL)/chat/completions")!,
            headers: ["Authorization": "Bearer \(apiKey)"],
            body: body
        )
        let choices = json["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        guard let content = message?["content"] as? String else {
            throw AIProviderError.invalidResponse("No content in response")
        }
        return content
    }
}
