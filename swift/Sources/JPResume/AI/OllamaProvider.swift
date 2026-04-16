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
        let url = URL(string: "\(baseURL)/api/chat")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "stream": false,
            "options": ["temperature": temperature],
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
        let message = json?["message"] as? [String: Any]
        guard let content = message?["content"] as? String else {
            throw AIProviderError.invalidResponse("No content in response")
        }
        return content
    }
}
