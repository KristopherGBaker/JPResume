import Foundation

struct ResumeAI: Sendable {
    let provider: any AIProvider
    let verbose: Bool

    init(provider: String, model: String?, verbose: Bool) throws {
        self.provider = try ProviderFactory.create(provider: provider, model: model)
        self.verbose = verbose
        print("  Using AI provider: \(self.provider.name)")
    }

    func generateRirekisho(western: WesternResume, config: JapanConfig, era: EraStyle) async throws -> RirekishoData {
        let eraStyle = era == .japanese ? "Japanese era (令和/平成)" : "western year"
        let eraExample = era == .japanese ? "令和2年4月" : "2020年4月"

        let system = SystemPrompts.rirekisho(eraStyle: eraStyle, eraExample: eraExample)
        let user = try buildUserMessage(western: western, config: config)

        let response = try await call(system: system, user: user)
        let json = try extractJSON(from: response)
        return try JSONDecoder().decode(RirekishoData.self, from: json)
    }

    func generateShokumukeirekisho(western: WesternResume, config: JapanConfig, era: EraStyle) async throws -> ShokumukeirekishoData {
        let eraStyle = era == .japanese ? "Japanese era (令和/平成)" : "western year"

        let system = SystemPrompts.shokumukeirekisho(eraStyle: eraStyle)
        let user = try buildUserMessage(western: western, config: config)

        let response = try await call(system: system, user: user)
        let json = try extractJSON(from: response)
        return try JSONDecoder().decode(ShokumukeirekishoData.self, from: json)
    }

    private func call(system: String, user: String) async throws -> String {
        if verbose {
            print("\n  System prompt (\(system.count) chars)")
            print("  User message (\(user.count) chars)")
        }
        let response = try await provider.chat(system: system, user: user)
        if verbose {
            print("  Response (\(response.count) chars)")
        }
        return response
    }

    private func buildUserMessage(western: WesternResume, config: JapanConfig) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let westernJSON = try encoder.encode(western)
        let configJSON = try encoder.encode(config)

        let today = ISO8601DateFormatter().string(from: Date()).prefix(10)
        return """
        {
          "western_resume": \(String(data: westernJSON, encoding: .utf8)!),
          "japan_config": \(String(data: configJSON, encoding: .utf8)!),
          "today": "\(today)"
        }
        """
    }

    func extractJSON(from text: String) throws -> Data {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try extracting from code fences
        if cleaned.contains("```") {
            let parts = cleaned.components(separatedBy: "```")
            for part in parts.dropFirst() {
                var content = part.trimmingCharacters(in: .whitespacesAndNewlines)
                if content.hasPrefix("json") || content.hasPrefix("JSON") {
                    content = String(content.drop(while: { $0 != "\n" }).dropFirst())
                }
                content = content.trimmingCharacters(in: .whitespacesAndNewlines)
                if content.hasPrefix("{"),
                   let data = content.data(using: .utf8),
                   (try? JSONSerialization.jsonObject(with: data)) != nil {
                    return data
                }
            }
        }

        // Try direct parse
        if let data = cleaned.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil {
            return data
        }

        // Extract first JSON object by brace matching
        guard let startIdx = cleaned.firstIndex(of: "{") else {
            throw AIProviderError.jsonExtractionFailed(String(cleaned.prefix(200)))
        }

        var depth = 0
        for (i, ch) in cleaned[startIdx...].enumerated() {
            if ch == "{" { depth += 1 }
            else if ch == "}" {
                depth -= 1
                if depth == 0 {
                    let endOffset = cleaned.index(startIdx, offsetBy: i + 1)
                    let jsonStr = String(cleaned[startIdx..<endOffset])
                    if let data = jsonStr.data(using: .utf8) {
                        return data
                    }
                }
            }
        }

        throw AIProviderError.jsonExtractionFailed(String(cleaned.prefix(200)))
    }
}
