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
        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": model,
            "temperature": temperature,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AIProviderError.requestFailed(String(data: data, encoding: .utf8) ?? "Unknown error")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        guard let content = message?["content"] as? String else {
            throw AIProviderError.invalidResponse("No content in response")
        }
        return content
    }
}
