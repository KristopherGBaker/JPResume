import Foundation

protocol AIProvider: Sendable {
    var name: String { get }
    func chat(system: String, user: String, temperature: Double) async throws -> String
}

extension AIProvider {
    func chat(system: String, user: String) async throws -> String {
        try await chat(system: system, user: user, temperature: 0.3)
    }
}

enum AIProviderError: Error, LocalizedError {
    case missingAPIKey(String)
    case requestFailed(String, underlying: Error? = nil)
    case invalidResponse(String)
    case jsonExtractionFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let key):
            return "\(key) environment variable is required"
        case .requestFailed(let msg, let underlying):
            if let underlying {
                return "API request failed: \(msg) (\(underlying.localizedDescription))"
            }
            return "API request failed: \(msg)"
        case .invalidResponse(let msg):
            return "Invalid response: \(msg)"
        case .jsonExtractionFailed(let msg):
            return "Could not extract JSON: \(msg)"
        }
    }
}
