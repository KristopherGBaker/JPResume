import Foundation

/// Naming choices that should remain consistent across rirekisho and shokumukeirekisho.
/// When generating both in one run, the rirekisho output is the source of truth — the
/// shokumukeirekisho prompt receives this so it picks the same company-name rendering
/// (Japanese legal entity vs. English, particles, suffixes) and the same candidate name.
struct NamingContext: Codable, Sendable {
    let candidateName: String?
    /// Company names exactly as they appear in the rirekisho work_history rows.
    /// Order matches the source timeline, but consumers should use them by lookup not by index.
    let companyNames: [String]

    /// Build a NamingContext from a generated RirekishoData. Extracts the leading
    /// company token (everything before the first space) from each work_history
    /// description that isn't a continuation row.
    static func from(_ rirekisho: RirekishoData) -> NamingContext {
        var seen = Set<String>()
        var names: [String] = []
        for row in rirekisho.workHistory {
            // Skip the 「現在に至る」continuation row.
            if row.description.contains("現在に至る") && row.date.isEmpty { continue }
            guard let name = extractCompanyName(row.description) else { continue }
            if seen.insert(name).inserted { names.append(name) }
        }
        return NamingContext(
            candidateName: rirekisho.nameKanji.isEmpty ? nil : rirekisho.nameKanji,
            companyNames: names
        )
    }

    /// Pull the company token from a rirekisho work_history description.
    /// Descriptions are of the form `「株式会社〇〇 入社」` / `「〇〇株式会社 退職」` — the
    /// company name is everything before the final action verb (入社/退職/etc).
    private static func extractCompanyName(_ description: String) -> String? {
        let trimmed = description.trimmingCharacters(in: .whitespaces)
        let actionWords = ["入社", "退職", "離職", "転職", "出向", "復職"]
        for action in actionWords {
            if let range = trimmed.range(of: action) {
                let prefix = trimmed[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
                if !prefix.isEmpty { return prefix }
            }
        }
        // No action verb found — fall back to the full string.
        return trimmed.isEmpty ? nil : trimmed
    }
}
