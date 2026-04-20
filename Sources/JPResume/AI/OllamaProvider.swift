import Foundation

struct OllamaProvider: AIProvider, Sendable {
    let model: String
    let baseURL: String

    var name: String { "Ollama (\(model))" }

    init(model: String, baseURL: String = "http://localhost:11434") {
        self.model = model
        self.baseURL = baseURL
    }

    func chat(system: String, user: String, temperature: Double) async throws -> String {
        let body: [String: Any] = [
            "model": model,
            "stream": false,
            "options": ["temperature": temperature],
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ]
        let json = try await HTTPJSONClient.postJSON(
            url: URL(string: "\(baseURL)/api/chat")!,
            body: body
        )
        let message = json["message"] as? [String: Any]
        guard let content = message?["content"] as? String else {
            throw AIProviderError.invalidResponse("No content in response")
        }
        return content
    }
}
