import Foundation

/// Stateless wrappers over existing pipeline functions.
/// Commands call these; no orchestration logic lives here.
enum Stages {

    // MARK: - Parse

    static func parse(markdown: String) -> WesternResume {
        MarkdownParser.parse(markdown)
    }

    // MARK: - Normalize

    static func normalize(
        western: WesternResume,
        config: JapanConfig,
        provider: any AIProvider,
        verbose: Bool
    ) async throws -> NormalizedResume {
        let normalizer = ResumeNormalizer(provider: provider, verbose: verbose)
        return try await normalizer.normalize(western: western, config: config)
    }

    // MARK: - Validate

    static func validate(_ resume: NormalizedResume) -> ValidationResult {
        ResumeValidator.validate(resume)
    }

    // MARK: - Repair

    static func repair(_ resume: NormalizedResume) -> NormalizedResume {
        ResumeConsistencyChecker.check(resume)
    }

    // MARK: - Generate

    static func generateRirekisho(
        repaired: NormalizedResume,
        config: JapanConfig,
        era: EraStyle,
        provider: any AIProvider,
        verbose: Bool
    ) async throws -> RirekishoData {
        let ai = ResumeAI(provider: provider, verbose: verbose)
        return try await ai.generateRirekisho(normalized: repaired, config: config, era: era)
    }

    static func generateShokumukeirekisho(
        repaired: NormalizedResume,
        config: JapanConfig,
        era: EraStyle,
        options: GenerationOptions,
        provider: any AIProvider,
        verbose: Bool
    ) async throws -> ShokumukeirekishoData {
        let ai = ResumeAI(provider: provider, verbose: verbose)
        return try await ai.generateShokumukeirekisho(normalized: repaired, config: config, era: era, options: options)
    }

    // MARK: - Polish

    static func polish(_ data: RirekishoData, derived: DerivedExperience?) -> RirekishoData {
        JapanesePolishRules.polish(data, derived: derived)
    }

    static func polish(_ data: ShokumukeirekishoData, derived: DerivedExperience?) -> ShokumukeirekishoData {
        JapanesePolishRules.polish(data, derived: derived)
    }

    // MARK: - Render

    static func renderMarkdown(rirekisho: RirekishoData) -> String {
        MarkdownRenderer.renderRirekisho(rirekisho)
    }

    static func renderMarkdown(shokumukeirekisho: ShokumukeirekishoData) -> String {
        MarkdownRenderer.renderShokumukeirekisho(shokumukeirekisho)
    }

    static func renderPDF(rirekisho: RirekishoData, to url: URL) throws {
        try RirekishoPDFRenderer.render(data: rirekisho, to: url)
    }

    static func renderPDF(shokumukeirekisho: ShokumukeirekishoData, to url: URL) throws {
        try ShokumukeirekishoPDFRenderer.render(data: shokumukeirekisho, to: url)
    }
}
