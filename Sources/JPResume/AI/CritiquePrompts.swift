import DocPipeline
import Foundation

/// Prompts used by the self-critique loop. Lives separately from `SystemPrompts` because
/// it composes with any base stage rather than belonging to one, and keeps SystemPrompts
/// under the file-length lint.
enum CritiquePrompts {
    /// System message for the critique pass. The original generation prompt's contract
    /// still applies — this message extends it with a focused instruction to repair
    /// specific violations while preserving everything else.
    static func system(stage: String) -> String {
        """
        You are revising a Japanese resume artifact (\(stage)) that you produced in a prior
        turn. A deterministic checker found constraint violations that the user message
        lists explicitly. Your job is to return a corrected JSON object that:

        1. Fixes every listed violation. The rule IDs identify the exact constraint —
           rewrite the offending content so the rule no longer triggers.
        2. Preserves every fact, name, date, and metric from the current output that the
           violations don't ask you to change. Do NOT invent new facts or remove unrelated
           content.
        3. Keeps the same JSON schema and field names as the current output.
        4. Maintains the formal Japanese register from the original system prompt
           (modest, factual, no hype, no superlatives).

        Return ONLY the corrected JSON. No prose, no code fences, no commentary.
        """
    }

    /// Build the user message body for a critique pass. Pairs the current JSON with the
    /// violation list so the model sees what's wrong and where.
    static func userMessage<T: Encodable>(current: T, violations: [ConstraintViolation]) throws -> String {
        let enc = JSONCoders.prettySorted
        let currentJSON = try enc.encode(current)
        let violationDicts = violations.map { ["rule": $0.rule, "field": $0.field, "message": $0.message] }
        let violationsJSON = try enc.encode(violationDicts)
        return """
        {
          "current_output": \(String(data: currentJSON, encoding: .utf8)!),
          "violations": \(String(data: violationsJSON, encoding: .utf8)!)
        }
        """
    }
}
