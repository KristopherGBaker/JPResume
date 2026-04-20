import Foundation

/// Minimal helper for the HTTP+JSON pattern shared by Anthropic, OpenAI, and Ollama
/// providers: POST a JSON body, expect a JSON object back, surface non-200 as
/// `AIProviderError.requestFailed` so providers can stay focused on body shape and
/// response-key extraction.
enum HTTPJSONClient {
    static func postJSON(
        url: URL,
        headers: [String: String] = [:],
        body: [String: Any]
    ) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AIProviderError.requestFailed(String(data: data, encoding: .utf8) ?? "Unknown error")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIProviderError.invalidResponse("Response was not a JSON object")
        }
        return json
    }
}
