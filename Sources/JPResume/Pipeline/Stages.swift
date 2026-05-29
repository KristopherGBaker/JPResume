import DocPipeline
import Foundation
import Shikisha

/// Stateless wrappers over existing pipeline functions.
/// Commands call these; no orchestration logic lives here.
enum Stages {

    // MARK: - Parse

    static func parse(text: String, sourceKind: ResumeSourceKind) -> WesternResume {
        switch sourceKind {
        case .markdown:
            return MarkdownParser.parse(text)
        case .docx, .pdf, .text:
            return PlainTextResumeParser.parse(text)
        }
    }

    // MARK: - Normalize

    /// Normalize with an optional validation feedback loop. After the initial pass,
    /// if validation surfaces issues, hand the validation context back to the LLM and
    /// re-normalize. Only accept the refined result when its issue count strictly
    /// decreases (oscillation guard). Capped at `maxRefinements` extra passes.
    static func normalize(
        western: WesternResume,
        inputs: InputsData,
        config: JapanConfig,
        model: any ChatModel,
        verbose: Bool,
        maxRefinements: Int = 2
    ) async throws -> NormalizedResume {
        let normalizer = ResumeNormalizer(model: model, verbose: verbose)
        var current = try await normalizer.normalize(western: western, inputs: inputs, config: config)
        var currentIssues = ResumeValidator.validate(current).issues.count

        guard maxRefinements > 0 else { return current }

        for pass in 1...maxRefinements where currentIssues > 0 {
            let validation = ResumeValidator.validate(current)
            if verbose {
                print("  [Feedback pass \(pass)/\(maxRefinements)] \(currentIssues) validation issue(s); refining...")
            }
            do {
                let refined = try await normalizer.refine(current: current, validation: validation,
                                                          inputs: inputs)
                let refinedIssues = ResumeValidator.validate(refined).issues.count
                if refinedIssues < currentIssues {
                    if verbose {
                        print("  [Feedback] \(currentIssues) → \(refinedIssues) issues; accepting")
                    }
                    current = refined
                    currentIssues = refinedIssues
                } else {
                    if verbose {
                        print("  [Feedback] \(currentIssues) → \(refinedIssues) (no improvement); reverting")
                    }
                    break
                }
            } catch {
                if verbose { print("  [Feedback] Refinement call failed: \(error); keeping prior pass") }
                break
            }
        }
        return current
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
        targetContext: TargetCompanyContext? = nil,
        additionalContext: String? = nil,
        model: any ChatModel,
        verbose: Bool,
        maxCritiquePasses: Int = 3
    ) async throws -> GenerationResult<RirekishoData> {
        let ai = ResumeAI(model: model, verbose: verbose, maxCritiquePasses: maxCritiquePasses)
        return try await ai.generateRirekisho(normalized: repaired, config: config, era: era,
                                               targetContext: targetContext,
                                               additionalContext: additionalContext)
    }

    static func generateShokumukeirekisho(
        repaired: NormalizedResume,
        config: JapanConfig,
        era: EraStyle,
        options: GenerationOptions,
        targetContext: TargetCompanyContext? = nil,
        namingContext: NamingContext? = nil,
        additionalContext: String? = nil,
        model: any ChatModel,
        verbose: Bool,
        maxCritiquePasses: Int = 3
    ) async throws -> GenerationResult<ShokumukeirekishoData> {
        let ai = ResumeAI(model: model, verbose: verbose, maxCritiquePasses: maxCritiquePasses)
        return try await ai.generateShokumukeirekisho(normalized: repaired, config: config, era: era,
                                                       options: options, targetContext: targetContext,
                                                       namingContext: namingContext,
                                                       additionalContext: additionalContext)
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
