import DocPipeline
import Foundation

/// User-message payloads shared between internal AI calls and external prompt
/// bundles. Producing them in one place guarantees that `--external` writes the
/// same bytes the in-process LLM call would have sent.
enum PromptPayload {
    /// Payload for the normalize stage. Combines the parsed western resume,
    /// effective `JapanConfig`, and the source-text context the preprocessor
    /// emitted so the model can reconcile structured fields against raw text.
    static func normalize(
        western: WesternResume,
        inputs: InputsData,
        config: JapanConfig
    ) throws -> String {
        let enc = JSONCoders.prettySorted
        let westernJSON = try enc.encode(western)
        let configJSON = try enc.encode(config)
        let sourceKindJSON = try enc.encode(inputs.sourceKind?.rawValue)
        let cleanedTextJSON = try enc.encode(inputs.cleanedText ?? inputs.sourceText)
        let notesJSON = try enc.encode(inputs.preprocessingNotes)
        var body = """
        {
          "western_resume": \(string(westernJSON)),
          "japan_config": \(string(configJSON)),
          "source_input": {
            "kind": \(string(sourceKindJSON)),
            "cleaned_text": \(string(cleanedTextJSON)),
            "preprocessing_notes": \(string(notesJSON))
          }
        """
        if let user = inputs.userNotes, !user.isEmpty {
            let userJSON = try enc.encode(user)
            body += ",\n  \"additional_context\": \(string(userJSON))"
        }
        body += "\n}"
        return body
    }

    /// Payload for the adapt stages (rirekisho / shokumukeirekisho). Includes
    /// today's date so the LLM can compute durations and current-role flags, and
    /// an optional target-company context for tailored application mode.
    static func adapt(
        normalized: NormalizedResume,
        config: JapanConfig,
        targetContext: TargetCompanyContext? = nil,
        additionalContext: String? = nil
    ) throws -> String {
        let enc = JSONCoders.prettySorted
        let normalizedJSON = try enc.encode(normalized)
        let configJSON = try enc.encode(config)
        let today = ISO8601DateFormatter().string(from: Date()).prefix(10)
        var msg = """
        {
          "normalized_resume": \(string(normalizedJSON)),
          "japan_config": \(string(configJSON)),
          "today": "\(today)"
        """
        if let ctx = targetContext {
            let ctxJSON = try enc.encode(ctx)
            msg += ",\n  \"target_company_context\": \(string(ctxJSON))"
        }
        if let extra = additionalContext, !extra.isEmpty {
            let extraJSON = try enc.encode(extra)
            msg += ",\n  \"additional_context\": \(string(extraJSON))"
        }
        msg += "\n}"
        return msg
    }

    /// Force-unwrap is safe: bytes came from `JSONEncoder`, which always emits valid UTF-8.
    private static func string(_ data: Data) -> String {
        String(bytes: data, encoding: .utf8)!
    }
}
