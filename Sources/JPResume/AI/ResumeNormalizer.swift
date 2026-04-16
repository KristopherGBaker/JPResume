import Foundation

struct ResumeNormalizer: Sendable {
    let provider: any AIProvider
    let verbose: Bool

    func normalize(western: WesternResume, config: JapanConfig) async throws -> NormalizedResume {
        let system = SystemPrompts.normalization()
        let user = try buildUserMessage(western: western, config: config)

        if verbose {
            print("\n  [Normalizer] System prompt (\(system.count) chars)")
            print("  [Normalizer] User message (\(user.count) chars)")
        }

        // First attempt
        do {
            let response = try await provider.chat(system: system, user: user, temperature: 0.2)
            if verbose { print("  [Normalizer] Response (\(response.count) chars)") }
            let data = try JSONExtractor.extract(from: response)
            return try JSONDecoder().decode(NormalizedResume.self, from: data)
        } catch {
            if verbose { print("  [Normalizer] First attempt failed: \(error). Retrying...") }
        }

        // Retry with error context
        do {
            let retryUser = user + "\n\nNOTE: Your previous response failed to parse. Return strictly valid JSON with no extra text."
            let response = try await provider.chat(system: system, user: retryUser, temperature: 0.1)
            if verbose { print("  [Normalizer] Retry response (\(response.count) chars)") }
            let data = try JSONExtractor.extract(from: response)
            return try JSONDecoder().decode(NormalizedResume.self, from: data)
        } catch {
            if verbose { print("  [Normalizer] Retry failed: \(error). Using deterministic fallback.") }
        }

        // Deterministic fallback
        print("  ⚠️  LLM normalization failed — using deterministic fallback (lower quality)")
        return deterministicFallback(western: western)
    }

    // MARK: - Private

    private func buildUserMessage(western: WesternResume, config: JapanConfig) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let westernJSON = try encoder.encode(western)
        let configJSON = try encoder.encode(config)
        return """
        {
          "western_resume": \(String(data: westernJSON, encoding: .utf8)!),
          "japan_config": \(String(data: configJSON, encoding: .utf8)!)
        }
        """
    }

    /// Build a NormalizedResume from WesternResume without any LLM call.
    /// Dates are parsed with simple regex. All bullets are classified as responsibilities.
    private func deterministicFallback(western: WesternResume) -> NormalizedResume {
        let experience = western.experience.map { entry in
            NormalizedWorkEntry(
                company: entry.company,
                title: entry.title,
                startDate: parseDate(entry.startDate),
                endDate: entry.endDate.flatMap { parseDate($0) },
                isCurrent: isCurrentDate(entry.endDate),
                location: entry.location,
                bullets: entry.bullets.map { NormalizedBullet(text: $0, category: .responsibility) }
            )
        }

        let education = western.education.map { entry in
            NormalizedEducationEntry(
                institution: entry.institution,
                degree: entry.degree,
                field: entry.field,
                graduationDate: parseDate(entry.graduationDate),
                gpa: entry.gpa
            )
        }

        let skillCategories: [SkillCategory] = western.skills.isEmpty
            ? []
            : [SkillCategory(name: "General", skills: western.skills)]

        return NormalizedResume(
            name: western.name,
            contact: western.contact,
            summary: western.summary,
            experience: experience,
            education: education,
            skillCategories: skillCategories,
            certifications: western.certifications,
            languages: western.languages,
            normalizerNotes: ["Deterministic fallback used — LLM normalization failed"],
            rawSections: western.rawSections
        )
    }

    private func parseDate(_ string: String?) -> StructuredDate? {
        guard let s = string?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        let lower = s.lowercased()
        if lower == "present" || lower == "current" || lower == "now" { return nil }

        // Match "Month YYYY" or "Mon YYYY" e.g. "April 2020", "Apr 2020"
        let monthNames = ["january": 1, "february": 2, "march": 3, "april": 4, "may": 5,
                          "june": 6, "july": 7, "august": 8, "september": 9, "october": 10,
                          "november": 11, "december": 12,
                          "jan": 1, "feb": 2, "mar": 3, "apr": 4, "jun": 6, "jul": 7,
                          "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12]

        let words = lower.components(separatedBy: .whitespaces)
        for (i, word) in words.enumerated() {
            if let month = monthNames[word] {
                for candidate in words.dropFirst(i) {
                    if let year = Int(candidate.filter(\.isNumber)), year > 1950 && year < 2100 {
                        return StructuredDate(year: year, month: month)
                    }
                }
            }
        }

        // Match bare year (4 digits)
        let digits = s.filter(\.isNumber)
        if digits.count == 4, let year = Int(digits), year > 1950 && year < 2100 {
            return StructuredDate(year: year)
        }

        return nil
    }

    private func isCurrentDate(_ string: String?) -> Bool {
        guard let s = string?.trimmingCharacters(in: .whitespaces) else { return false }
        let lower = s.lowercased()
        return lower.isEmpty || lower == "present" || lower == "current" || lower == "now"
    }
}
