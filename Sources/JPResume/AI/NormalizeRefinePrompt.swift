import DocPipeline
import Foundation

/// Prompts for the normalize stage's validation feedback loop. Mirrors the structure of
/// the critique prompts (system + user message that pairs the current artifact with the
/// detected issues) but for the normalize → validate → refine flow.
enum NormalizeRefinePrompt {
    static func system() -> String {
        """
        You produced a NormalizedResume in a prior turn. The validator found issues that
        the user message lists explicitly. Return a corrected NormalizedResume that:

        1. Resolves every issue the validator can resolve from the available inputs.
           Common issues you should fix when the data supports it:
           - Low-confidence dates → recheck japan_config.work_japanese /
             education_japanese; if there's a matching entry, use its date verbatim and
             set confidence to 1.0 with no further note.
           - Suspicious overlaps → confirm against japan_config; only fix when config
             gives ground truth, otherwise add a clarifying timeline_warnings entry.
           - Missing required field that the source clearly provides → fill it in.
        2. Does NOT fabricate dates, employers, titles, or any other fact to silence the
           validator. If you cannot fix an issue from the available inputs, leave the
           data as-is and append a normalizer_notes entry explaining why.
        3. Preserves every fact, name, and entry from the current output that the
           validator didn't flag. Do not reorder, drop, or rename unrelated entries.
        4. Keeps the same JSON schema and field names.

        Return ONLY the corrected JSON. No prose, no code fences, no commentary.
        """
    }

    static func userMessage(
        current: NormalizedResume,
        validation: ValidationResult,
        inputs: InputsData
    ) throws -> String {
        let enc = JSONCoders.prettySorted
        let currentJSON = try enc.encode(current)
        let validationJSON = try enc.encode(validation)
        let configJSON = try enc.encode(inputs.config)
        return """
        {
          "current_normalized": \(String(data: currentJSON, encoding: .utf8)!),
          "validation_issues": \(String(data: validationJSON, encoding: .utf8)!),
          "japan_config": \(String(data: configJSON, encoding: .utf8)!)
        }
        """
    }
}
