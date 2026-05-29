import DocPipeline
import Foundation
import Shikisha

struct ResumeAI: Sendable {
    let model: any ChatModel
    let verbose: Bool
    let maxCritiquePasses: Int

    init(provider: String, modelName: String?, verbose: Bool, maxCritiquePasses: Int = 3) throws {
        self.model = try ProviderFactory.create(provider: provider, model: modelName, temperature: 0.3)
        self.verbose = verbose
        self.maxCritiquePasses = maxCritiquePasses
        print("  Using AI provider: \(ProviderFactory.label(provider: provider, model: modelName))")
    }

    init(model: any ChatModel, verbose: Bool, maxCritiquePasses: Int = 3) {
        self.model = model
        self.verbose = verbose
        self.maxCritiquePasses = maxCritiquePasses
    }

    func generateRirekisho(
        normalized: NormalizedResume,
        config: JapanConfig,
        era: EraStyle,
        targetContext: TargetCompanyContext? = nil,
        additionalContext: String? = nil
    ) async throws -> GenerationResult<RirekishoData> {
        let eraStyle = era == .japanese ? "Japanese era (令和/平成)" : "western year"
        let eraExample = era == .japanese ? "令和2年4月" : "2020年4月"
        let system = SystemPrompts.rirekisho(eraStyle: eraStyle, eraExample: eraExample,
                                              targetContext: targetContext)
        let user = try PromptPayload.adapt(normalized: normalized, config: config,
                                           targetContext: targetContext,
                                           additionalContext: additionalContext)

        let initial: RirekishoData = try await invokeStructured(system: system, user: user)
        return try await refineWithCritique(initial: initial, stage: "rirekisho",
                                            checker: JapaneseConstraintChecker.check(_:))
    }

    func generateShokumukeirekisho(
        normalized: NormalizedResume,
        config: JapanConfig,
        era: EraStyle,
        options: GenerationOptions = GenerationOptions(),
        targetContext: TargetCompanyContext? = nil,
        namingContext: NamingContext? = nil,
        additionalContext: String? = nil
    ) async throws -> GenerationResult<ShokumukeirekishoData> {
        let eraStyle = era == .japanese ? "Japanese era (令和/平成)" : "western year"
        let system = SystemPrompts.shokumukeirekisho(eraStyle: eraStyle, options: options,
                                                      targetContext: targetContext,
                                                      namingContext: namingContext)
        let user = try PromptPayload.adapt(normalized: normalized, config: config,
                                           targetContext: targetContext,
                                           additionalContext: additionalContext)

        let initial: ShokumukeirekishoData = try await invokeStructured(system: system, user: user)
        return try await refineWithCritique(initial: initial, stage: "shokumukeirekisho",
                                            checker: JapaneseConstraintChecker.check(_:))
    }

    // MARK: - Private

    private func invokeStructured<T: Decodable & Sendable>(system: String, user: String) async throws -> T {
        if verbose {
            print("\n  System prompt (\(system.count) chars)")
            print("  User message (\(user.count) chars)")
        }
        let messages: [any Message] = [SystemMessage(content: system), HumanMessage(content: user)]
        return try await ChatModelDecoder.decode(T.self, model: model, messages: messages)
    }

    /// Critique loop: run the deterministic checker; on violations, ask the LLM to
    /// repair them; re-check; repeat up to `maxCritiquePasses`. Always returns the
    /// latest data plus whatever violations remain — caller decides how to surface them.
    private func refineWithCritique<T: Codable & Sendable>(
        initial: T,
        stage: String,
        checker: (T) -> [ConstraintViolation]
    ) async throws -> GenerationResult<T> {
        var current = initial
        var passes = 0

        for pass in 1...maxCritiquePasses {
            let violations = checker(current)
            if violations.isEmpty {
                if verbose && pass > 1 {
                    print("  [Critique] Clean after \(passes) pass\(passes == 1 ? "" : "es")")
                }
                return GenerationResult(data: current, critiquePasses: passes, remainingViolations: [])
            }
            if verbose {
                print("  [Critique pass \(pass)/\(maxCritiquePasses)] \(violations.count) violation(s):")
                for v in violations { print("    - \(v.rule) (\(v.field))") }
            }
            current = try await critique(current: current, violations: violations, stage: stage)
            passes = pass
        }

        // Loop exhausted — return whatever's left.
        let remaining = checker(current)
        if !remaining.isEmpty {
            print("  ⚠️  [Critique] \(remaining.count) violation(s) remain after \(passes) pass(es); shipping anyway")
        }
        return GenerationResult(data: current, critiquePasses: passes, remainingViolations: remaining)
    }

    private func critique<T: Codable & Sendable>(
        current: T,
        violations: [ConstraintViolation],
        stage: String
    ) async throws -> T {
        let system = CritiquePrompts.system(stage: stage)
        let user = try CritiquePrompts.userMessage(current: current, violations: violations)
        return try await invokeStructured(system: system, user: user)
    }
}
