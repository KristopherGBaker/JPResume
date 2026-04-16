import Foundation

enum JSONExtractor {
    /// Extract the first valid JSON object from an LLM response.
    /// Handles: markdown code fences, direct JSON, and brace-matched fallback.
    static func extract(from text: String) throws -> Data {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

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
