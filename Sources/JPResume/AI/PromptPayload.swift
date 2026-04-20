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
        return """
        {
          "western_resume": \(string(westernJSON)),
          "japan_config": \(string(configJSON)),
          "source_input": {
            "kind": \(string(sourceKindJSON)),
            "cleaned_text": \(string(cleanedTextJSON)),
            "preprocessing_notes": \(string(notesJSON))
          }
        }
        """
    }

    /// Payload for the adapt stages (rirekisho / shokumukeirekisho). Includes
    /// today's date so the LLM can compute durations and current-role flags, and
    /// an optional target-company context for tailored application mode.
    static func adapt(
        normalized: NormalizedResume,
        config: JapanConfig,
        targetContext: TargetCompanyContext? = nil
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
        msg += "\n}"
        return msg
    }

    /// Force-unwrap is safe: bytes came from `JSONEncoder`, which always emits valid UTF-8.
    private static func string(_ data: Data) -> String {
        String(bytes: data, encoding: .utf8)!
    }
}
